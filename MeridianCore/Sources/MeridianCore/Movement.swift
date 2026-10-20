import Foundation

extension World {

    // MARK: Per-unit order processing

    func updateOrders() {
        for e in entities where e.isUnit && e.onMap && !e.isMine {
            updateUnit(e)
        }
    }

    func updateUnit(_ e: Entity) {
        let wasX = e.x, wasY = e.y
        let t = traits[e.type]
        switch e.order {
        case .idle, .hold:
            if let tg = entity(e.target), e.order == .idle, weapon(e) != nil {
                // Chase a target we acquired, but within a leash of our guard position.
                if dist2(e.x, e.y, e.ox, e.oy) < 14 * 14 || e.isAir {
                    engage(e, tg)
                } else {
                    e.target = -1
                    _ = moveTo(e, e.ox, e.oy, arrive: 0.5)
                }
            } else if (t.healBio || t.repairMech) && e.order == .idle {
                followWounded(e)
            }
        case .move:
            if moveFormation(e) {
                if e.fleeing { e.fleeing = false; e.order = e.gatherNode >= 0 ? .gather : .idle; if e.order == .idle { becomeIdle(e) } }
                else { becomeIdle(e) }
            }
        case .attackMove, .patrol:
            if let tg = entity(e.target) {
                engage(e, tg)
            } else if t.healBio || t.repairMech, followWounded(e) {
                // support units in an attack-move group tend to the wounded
            } else if moveFormation(e) {
                if e.order == .patrol {
                    swap(&e.ox, &e.px2); swap(&e.oy, &e.py2)
                    e.formationDX = 0; e.formationDY = 0
                } else { becomeIdle(e) }
            }
        case .attack:
            if let tg = entity(e.orderTarget), canSee(e.owner, tg) {
                e.target = tg.id
                engage(e, tg)
            } else {
                becomeIdle(e)
            }
        case .gather: orderGather(e)
        case .returnCargo: orderReturn(e)
        case .build: orderBuild(e)
        case .repair: orderRepair(e)
        case .load:
            if let tr = entity(e.orderTarget), tr.owner == e.owner, traits[tr.type].capacity > 0 {
                if edgeDist(e, tr) < 1.2 || (tr.isAir && dist2(e.x, e.y, tr.x, tr.y) < 2.5) {
                    load(e, into: tr)
                } else {
                    _ = moveTo(e, tr.x, tr.y, arrive: 0.8)
                }
            } else { becomeIdle(e) }
        case .unload:
            if moveTo(e, e.ox, e.oy, arrive: 0.6) { unloadAll(e); becomeIdle(e) }
        }
        e.moving = abs(e.x - wasX) > 0.0005 || abs(e.y - wasY) > 0.0005
        if e.moving { e.setupTimer = 0 } else if t.setup { e.setupTimer += dt }
        // Units pushed into a freshly placed building get nudged out.
        if !e.isAir && nav.isBlocked(Int(e.x), Int(e.y)) { pushOutOfBlocked(e) }
    }

    func becomeIdle(_ e: Entity) {
        e.order = .idle
        e.ox = e.x; e.oy = e.y
        e.formationDX = 0; e.formationDY = 0
        e.stuckTimer = 0
    }

    /// Move into weapon range of the target, or stand and fight.
    func engage(_ e: Entity, _ tg: Entity) {
        guard let w = weapon(e) else { return }
        let d = edgeDist(e, tg)
        if d <= w.range {
            if d < w.minRange {
                // Too close for artillery: back off.
                let ax = e.x - tg.x, ay = e.y - tg.y
                let l = max(0.01, (ax * ax + ay * ay).squareRoot())
                step(e, ax / l, ay / l, speed(e) * dt)
            }
            return
        }
        if e.order == .hold { return }
        if tg.isBuilding || tg.isResource {
            _ = moveToRect(e, tg, range: w.range * 0.9)
        } else {
            _ = moveTo(e, tg.x, tg.y, arrive: max(0.2, w.range * 0.85))
        }
    }

    @discardableResult
    func followWounded(_ e: Entity) -> Bool {
        let t = traits[e.type]
        var best: Entity? = nil
        var bd = Double.infinity
        let s = sight(e)
        forEachNear(e.x, e.y, s) { o in
            guard o.owner == e.owner, o.id != e.id, o.isUnit, !o.isMine, o.hp < o.maxHp else { return }
            let tags = udef(o).tags
            if (t.healBio && tags.contains("bio")) || (t.repairMech && tags.contains("mech")) {
                let d = dist2(e.x, e.y, o.x, o.y)
                if d < bd { bd = d; best = o }
            }
        }
        guard let b = best else { return false }
        if bd > t.healRange * t.healRange * 0.6 { _ = moveTo(e, b.x, b.y, arrive: t.healRange * 0.7) }
        return true
    }

    /// Move toward the group goal (ox,oy) plus this unit's formation offset. Returns true on arrival.
    func moveFormation(_ e: Entity) -> Bool {
        let gx = e.ox + e.formationDX, gy = e.oy + e.formationDY
        let d2 = dist2(e.x, e.y, gx, gy)
        if d2 < 0.3 * 0.3 { return true }
        // Crowd arrival: if we are close but haven't made progress for a while, stop.
        if d2 < 9 {
            if dist2(e.x, e.y, e.lastProgressX, e.lastProgressY) < 0.04 {
                e.stuckTimer += dt
                if e.stuckTimer > 0.8 { return true }
            } else {
                e.stuckTimer = 0; e.lastProgressX = e.x; e.lastProgressY = e.y
            }
        }
        let offLen2 = e.formationDX * e.formationDX + e.formationDY * e.formationDY
        if e.isAir || d2 < offLen2 + 16 && nav.lineClear(e.x, e.y, gx, gy) {
            return moveDirect(e, gx, gy, arrive: 0.3)
        }
        // Path toward the group centre; the final approach uses the offset.
        return moveTo(e, gx, gy, arrive: 0.3, pathGoalX: e.ox, pathGoalY: e.oy)
    }

    /// Generic point movement with pathfinding. Returns true when within `arrive` of the goal.
    @discardableResult
    func moveTo(_ e: Entity, _ gx: Double, _ gy: Double, arrive: Double, pathGoalX: Double? = nil, pathGoalY: Double? = nil) -> Bool {
        let d2 = dist2(e.x, e.y, gx, gy)
        if d2 <= arrive * arrive { return true }
        let sp = speed(e) * dt
        if sp <= 0 { return false }
        if e.isAir { return moveDirect(e, gx, gy, arrive: arrive) }
        if d2 < 144 && nav.lineClear(e.x, e.y, gx, gy) { return moveDirect(e, gx, gy, arrive: arrive) }
        let px = pathGoalX ?? gx, py = pathGoalY ?? gy
        if let f = nav.field(toTileX: Int(px), Int(py)), let dir = nav.direction(f, e.x, e.y) {
            if dir.0 == 0 && dir.1 == 0 { return moveDirect(e, gx, gy, arrive: arrive) }
            step(e, dir.0, dir.1, sp)
            return false
        }
        return moveDirect(e, gx, gy, arrive: arrive)
    }

    /// Move until edge distance to a building/resource footprint is within range.
    @discardableResult
    func moveToRect(_ e: Entity, _ tg: Entity, range: Double) -> Bool {
        if edgeDist(e, tg) <= range { return true }
        let sp = speed(e) * dt
        if sp <= 0 { return false }
        if e.isAir { return moveDirect(e, tg.x, tg.y, arrive: 0) && false }
        let dd = dist2(e.x, e.y, tg.x, tg.y)
        if dd < 64, nav.lineClear(e.x, e.y, clamp(tg.x, Double(tg.tileX) - 0.5, Double(tg.tileX + tg.size) + 0.5),
                                  clamp(tg.y, Double(tg.tileY) - 0.5, Double(tg.tileY + tg.size) + 0.5)) || dd < 4 {
            let s = Double(tg.size)
            let nx = clamp(e.x, Double(tg.tileX), Double(tg.tileX) + s), ny = clamp(e.y, Double(tg.tileY), Double(tg.tileY) + s)
            let dx = nx - e.x, dy = ny - e.y
            let l = (dx * dx + dy * dy).squareRoot()
            if l > 0.001 { step(e, dx / l, dy / l, min(sp, l)) }
            return false
        }
        if let f = nav.field(toRectX: tg.tileX, tg.tileY, size: max(1, tg.size)), let dir = nav.direction(f, e.x, e.y) {
            if dir.0 == 0 && dir.1 == 0 {
                let dx = tg.x - e.x, dy = tg.y - e.y
                let l = max(0.001, (dx * dx + dy * dy).squareRoot())
                step(e, dx / l, dy / l, sp)
            } else { step(e, dir.0, dir.1, sp) }
            return false
        }
        let dx = tg.x - e.x, dy = tg.y - e.y
        let l = max(0.001, (dx * dx + dy * dy).squareRoot())
        step(e, dx / l, dy / l, sp)
        return false
    }

    @discardableResult
    func moveDirect(_ e: Entity, _ gx: Double, _ gy: Double, arrive: Double) -> Bool {
        let dx = gx - e.x, dy = gy - e.y
        let l = (dx * dx + dy * dy).squareRoot()
        if l <= arrive { return true }
        let sp = speed(e) * dt
        if sp <= 0 { return false }
        let m = min(sp, l)
        step(e, dx / l, dy / l, m)
        return l - m <= arrive
    }

    /// Translate with axis-separated sliding against blocked tiles.
    func step(_ e: Entity, _ dx: Double, _ dy: Double, _ m: Double) {
        let nx = e.x + dx * m, ny = e.y + dy * m
        if dx != 0 || dy != 0 { e.facing = atan2(dy, dx) }
        let lim = Double(map.size) - 0.01
        if e.isAir {
            e.x = clamp(nx, 0.01, lim); e.y = clamp(ny, 0.01, lim); return
        }
        if !nav.isBlocked(Int(nx), Int(ny)) { e.x = nx; e.y = ny; return }
        if !nav.isBlocked(Int(nx), Int(e.y)) { e.x = nx; return }
        if !nav.isBlocked(Int(e.x), Int(ny)) { e.y = ny; return }
    }

    // MARK: Separation

    func separate() {
        for e in entities where e.isUnit && e.onMap && !e.isMine {
            var pushX = 0.0, pushY = 0.0
            let r = e.radius
            forEachNear(e.x, e.y, 1.5) { o in
                guard o.id != e.id, o.isUnit, !o.isMine, o.isAir == e.isAir else { return }
                let minD = r + o.radius
                let dx = e.x - o.x, dy = e.y - o.y
                let d2 = dx * dx + dy * dy
                if d2 >= minD * minD { return }
                if d2 < 1e-6 {
                    // Deterministic tie-break by id.
                    let a = Double(e.id % 16) * 0.39
                    pushX += cos(a) * 0.05; pushY += sin(a) * 0.05
                    return
                }
                let d = d2.squareRoot()
                let overlap = minD - d
                // Moving units yield less to idle ones so blobs flow around.
                var share = 0.5
                if e.moving && !o.moving { share = 0.25 } else if !e.moving && o.moving { share = 0.75 }
                if e.owner != o.owner { share *= 0.6 }
                pushX += dx / d * overlap * share
                pushY += dy / d * overlap * share
            }
            if pushX != 0 || pushY != 0 {
                let l = (pushX * pushX + pushY * pushY).squareRoot()
                let maxPush = 0.12
                if l > maxPush { pushX *= maxPush / l; pushY *= maxPush / l }
                if e.isAir {
                    e.x = clamp(e.x + pushX, 0.01, Double(map.size) - 0.01)
                    e.y = clamp(e.y + pushY, 0.01, Double(map.size) - 0.01)
                } else {
                    let nx = e.x + pushX, ny = e.y + pushY
                    if !nav.isBlocked(Int(nx), Int(e.y)) { e.x = nx }
                    if !nav.isBlocked(Int(e.x), Int(ny)) { e.y = ny }
                }
            }
        }
    }

    // MARK: Transport

    func load(_ e: Entity, into tr: Entity) {
        let cap = traits[tr.type].capacity
        let used = tr.cargo.reduce(0) { $0 + cargoSize(entity(byIDAny: $1)) }
        let need = cargoSize(e)
        guard used + need <= cap, !e.isAir else { becomeIdle(e); return }
        tr.cargo.append(e.id)
        e.carriedBy = tr.id
        e.order = .idle
        e.target = -1
    }

    func cargoSize(_ e: Entity?) -> Int {
        guard let e = e else { return 0 }
        return udef(e).tags.contains("massive") ? 4 : 1
    }

    func entity(byIDAny id: Int) -> Entity? { id >= 0 && id < byID.count ? byID[id] : nil }

    /// Entity by id even if dead (renderer uses this to play death animations).
    public func anyEntity(_ id: Int) -> Entity? { entity(byIDAny: id) }

    func unloadAll(_ tr: Entity) {
        var k = 0
        for cid in tr.cargo {
            guard let c = entity(byIDAny: cid) else { continue }
            let a = Double(k) * 0.8
            let r = 0.8 + Double(k) * 0.12
            c.x = tr.x + cos(a) * r; c.y = tr.y + sin(a) * r
            c.carriedBy = -1
            c.px = c.x; c.py = c.y
            pushOutOfBlocked(c)
            becomeIdle(c)
            k += 1
        }
        tr.cargo.removeAll()
    }
}
