import Foundation

extension World {

    /// Orders during which a unit will not auto-acquire targets.
    @inline(__always) func passiveOrder(_ o: OrderKind) -> Bool {
        switch o {
        case .move, .gather, .returnCargo, .build, .repair, .load, .unload: return true
        default: return false
        }
    }

    @inline(__always) func canHit(_ w: EffWeapon, _ t: Entity) -> Bool { t.isAir ? w.air : w.ground }

    func validTarget(_ e: Entity, _ w: EffWeapon, _ t: Entity) -> Bool {
        t.alive && t.onMap && t.kind != .resource && isEnemy(e.owner, t.owner) && canHit(w, t) && canSee(e.owner, t)
    }

    func updateCombat() {
        for e in entities where e.alive && e.onMap && e.kind != .resource {
            if e.cooldown > 0 { e.cooldown -= dt }
            if e.abilityCooldown > 0 { e.abilityCooldown -= dt }
            if e.isMine { updateMine(e); continue }
            if e.isUnit {
                let t = traits[e.type]
                if t.emp { autoEMP(e) }
                if t.mines { layMines(e) }
            }
            guard let w = weapon(e) else { continue }
            if e.isBuilding && e.disruptedUntil > time { continue }
            if e.isUnit && passiveOrder(e.order) {
                // Workers defend themselves only if explicitly attacked in melee range.
                e.target = -1
                continue
            }
            var tg = entity(e.target)
            if let t = tg, !validTarget(e, w, t) { tg = nil; e.target = -1 }
            if e.order == .attack, let ot = entity(e.orderTarget), validTarget(e, w, ot) { tg = ot; e.target = ot.id }

            e.retargetTimer -= dt
            if e.retargetTimer <= 0 && e.order != .attack {
                e.retargetTimer = 0.35 + Double(e.id % 7) * 0.02
                // Reacquire: no target, or current target is a building/non-threat while threats are near.
                if tg == nil || tg!.isBuilding || weapon(tg!) == nil || edgeDist(e, tg!) > w.range {
                    let acquire: Double
                    if e.isBuilding || e.order == .hold { acquire = w.range }
                    else { acquire = max(w.range, sight(e)) }
                    if let n = findTarget(e, w, acquire) { tg = n; e.target = n.id }
                }
            }
            guard let target = tg else { continue }
            let d = edgeDist(e, target)
            if d > w.range || d < w.minRange { continue }
            if e.isUnit {
                e.facing = atan2(target.y - e.y, target.x - e.x)
                let t = traits[e.type]
                if t.setup && e.setupTimer < t.setupTime { continue }
            }
            if e.cooldown <= 0 {
                fire(e, target, w)
                e.cooldown = w.interval
            }
        }
    }

    func findTarget(_ e: Entity, _ w: EffWeapon, _ r: Double) -> Entity? {
        var best: Entity? = nil
        var bestScore = Double.infinity
        forEachNear(e.x, e.y, r + 1) { o in
            guard o.kind != .resource, isEnemy(e.owner, o.owner), o.onMap, canHit(w, o) else { return }
            let d = edgeDist(e, o)
            if d > r || d < w.minRange { return }
            guard canSee(e.owner, o) else { return }
            // Prefer armed units, then other units, then buildings; tie-break by distance.
            var score = d
            if o.isBuilding { score += weapon(o) != nil ? 6 : 14 }
            else if o.isMine { score += 3 }
            else if weapon(o) == nil { score += traits[o.type].worker ? 5 : 3 }
            if let b = w.bonus { for tag in tags(o) { if let m = b[tag], m > 1 { score -= 2 * (m - 1) } } }
            if score < bestScore || (score == bestScore && o.id < (best?.id ?? .max)) { bestScore = score; best = o }
        }
        return best
    }

    func fire(_ e: Entity, _ target: Entity, _ w: EffWeapon) {
        e.lastFireTime = time
        e.lastAttackTime = time
        let fy = e.y, fx = e.x
        emit(.shot(from: e.id, fx: fx, fy: fy, tx: target.x, ty: target.y, style: w.style, owner: e.owner, air: target.isAir))
        let srcType = e.isUnit ? e.type : -1 - e.type
        if e.isUnit && traits[e.type].pierce {
            pierceShot(e, target, w)
            return
        }
        if w.speed <= 0 {
            hit(at: target.x, target.y, primary: target, damage: w.damage, splash: w.splash, w: w, owner: e.owner, srcType: srcType, sourceID: e.id)
            if e.isUnit && traits[e.type].chain { chain(e, from: target, w) }
        } else {
            let homing = !(w.splash > 0 && ["shell", "acid", "spore", "bomb"].contains(w.style))
            var p = Projectile(x: fx, y: fy, tx: target.x, ty: target.y, sx: fx, sy: fy, target: homing ? target.id : -1,
                               owner: e.owner, source: e.id, speed: w.speed, damage: w.damage, splash: w.splash,
                               hitsGround: w.ground, hitsAir: w.air, targetAir: target.isAir, style: w.style, sourceType: srcType)
            p.total = max(0.05, dist2(fx, fy, target.x, target.y).squareRoot() / w.speed)
            projectiles.append(p)
        }
    }

    func updateProjectiles() {
        var i = 0
        while i < projectiles.count {
            var p = projectiles[i]
            if let t = entity(p.target), t.onMap { p.tx = t.x; p.ty = t.y }
            let dx = p.tx - p.x, dy = p.ty - p.y
            let l = (dx * dx + dy * dy).squareRoot()
            let s = p.speed * dt
            p.age += dt
            if l <= s {
                let primary = entity(p.target)
                let w = EffWeapon(damage: p.damage, interval: 1, range: 0, minRange: 0, ground: p.hitsGround, air: p.hitsAir,
                                  splash: p.splash, speed: p.speed, bonus: bonusFor(p.sourceType), style: p.style)
                var prim: Entity? = nil
                if let pr = primary, pr.onMap, dist2(pr.x, pr.y, p.tx, p.ty) < 1 { prim = pr }
                hit(at: p.tx, p.ty, primary: prim, damage: p.damage, splash: p.splash, w: w, owner: p.owner, srcType: p.sourceType, sourceID: p.source)
                projectiles.swapAt(i, projectiles.count - 1)
                projectiles.removeLast()
                continue
            }
            p.x += dx / l * s; p.y += dy / l * s
            projectiles[i] = p
            i += 1
        }
    }

    func bonusFor(_ srcType: Int) -> [String: Double]? {
        if srcType >= 0 { return data.units[srcType].weapon?.bonus }
        return data.buildings[-1 - srcType].weapon?.bonus
    }

    func hit(at x: Double, _ y: Double, primary: Entity?, damage: Double, splash: Double, w: EffWeapon, owner: Int, srcType: Int, sourceID: Int) {
        let airImpact = primary?.isAir ?? false
        emit(.impact(x: x, y: y, radius: splash, style: w.style, air: airImpact))
        if splash > 0 {
            forEachNear(x, y, splash + 1) { o in
                guard o.kind != .resource, o.onMap, isEnemy(owner, o.owner), canHit(w, o) else { return }
                if o.isMine { return }
                let d = o.isBuilding ? max(0, dist2(x, y, o.x, o.y).squareRoot() - Double(o.size) * 0.5) : dist2(x, y, o.x, o.y).squareRoot()
                if d > splash + o.radius * 0.5 { return }
                let f = o.id == primary?.id ? 1.0 : max(0.4, 1 - 0.5 * d / splash)
                applyDamage(o, damage * f, bonus: w.bonus, attackerOwner: owner, sourceID: sourceID)
            }
        } else if let p = primary {
            applyDamage(p, damage, bonus: w.bonus, attackerOwner: owner, sourceID: sourceID)
        }
        // Special on-hit effects.
        if srcType >= 0 {
            let t = traits[srcType]
            if t.shred, let p = primary, p.alive {
                p.shredUntil = time + t.shredDuration; p.shredAmount = t.shredAmount
            }
            if t.sporeCloud {
                clouds.append(Cloud(x: x, y: y, radius: t.cloudRadius, dps: t.cloudDps, slow: t.cloudSlow, remaining: t.cloudDuration, owner: owner))
            }
        }
    }

    func chain(_ e: Entity, from first: Entity, _ w: EffWeapon) {
        let t = traits[e.type]
        var hitIDs: Set<Int> = [first.id]
        var cur = first
        for _ in 0..<t.chainCount {
            var best: Entity? = nil
            var bd = t.chainRange * t.chainRange
            forEachNear(cur.x, cur.y, t.chainRange) { o in
                guard !hitIDs.contains(o.id), o.isUnit, !o.isMine, o.onMap, isEnemy(e.owner, o.owner), canHit(w, o), canSee(e.owner, o) else { return }
                let d = dist2(cur.x, cur.y, o.x, o.y)
                if d < bd { bd = d; best = o }
            }
            guard let b = best else { break }
            hitIDs.insert(b.id)
            emit(.shot(from: -1, fx: cur.x, fy: cur.y, tx: b.x, ty: b.y, style: "arc", owner: e.owner, air: b.isAir))
            applyDamage(b, w.damage * t.chainFalloff, bonus: w.bonus, attackerOwner: e.owner, sourceID: e.id)
            cur = b
        }
    }

    func pierceShot(_ e: Entity, _ target: Entity, _ w: EffWeapon) {
        let t = traits[e.type]
        let dx = target.x - e.x, dy = target.y - e.y
        let l = max(0.01, (dx * dx + dy * dy).squareRoot())
        let ux = dx / l, uy = dy / l
        let len = l + t.pierceLength
        let ex = e.x + ux * len, ey = e.y + uy * len
        emit(.shot(from: e.id, fx: e.x, fy: e.y, tx: ex, ty: ey, style: "rail", owner: e.owner, air: false))
        applyDamage(target, w.damage, bonus: w.bonus, attackerOwner: e.owner, sourceID: e.id)
        var count = 0
        forEachNear((e.x + ex) / 2, (e.y + ey) / 2, len / 2 + 1) { o in
            guard o.id != target.id, o.kind == .unit, !o.isMine, o.onMap, isEnemy(e.owner, o.owner), canHit(w, o), count < 4 else { return }
            let rx = o.x - e.x, ry = o.y - e.y
            let along = rx * ux + ry * uy
            if along < 0 || along > len { return }
            let perp = abs(rx * uy - ry * ux)
            if perp <= 0.45 + o.radius {
                applyDamage(o, w.damage * 0.6, bonus: w.bonus, attackerOwner: e.owner, sourceID: e.id)
                count += 1
            }
        }
    }

    /// Core damage model: bonus multipliers by tag, flat armor with a minimum damage floor, network mitigation.
    func applyDamage(_ t: Entity, _ raw: Double, bonus: [String: Double]?, attackerOwner: Int, sourceID: Int, ignoreArmor: Bool = false) {
        guard t.alive else { return }
        var dmg = raw
        if let b = bonus { for tag in tags(t) { if let m = b[tag] { dmg *= m } } }
        let a = ignoreArmor ? 0 : armor(t)
        let floor = dmg * data.rules.combat.minDamageFraction
        dmg = max(floor, dmg - a)
        if t.linked && t.isUnit { dmg *= 1 - data.rules.combat.networkDamageReduction - players[t.owner].mods.linkBonus }
        t.hp -= dmg
        t.lastDamagedTime = time
        t.lastHitTime = time
        // Idle units that cannot see their attacker move toward it (anti-outrange behaviour).
        if t.isUnit && t.order == .idle && t.target < 0, let src = entity(sourceID), weapon(t) != nil, !traits[t.type].worker {
            if canSee(t.owner, src) { t.target = src.id }
            else if dist2(t.x, t.y, src.x, src.y) < 18 * 18 {
                t.order = .attackMove; t.ox = src.x; t.oy = src.y; t.formationDX = 0; t.formationDY = 0
            }
        }
        // Wounded workers retreat toward a drop-off, then go back to work.
        if t.isUnit && traits[t.type].worker && !t.fleeing && t.hp < t.maxHp * 0.6 && t.hp > 0 && (t.order == .gather || t.order == .returnCargo),
           let src = entity(sourceID), src.isUnit, let drop = nearestDropoff(t) {
            let dx = drop.x - src.x, dy = drop.y - src.y
            let l = max(0.1, (dx * dx + dy * dy).squareRoot())
            t.order = .move; t.ox = drop.x + dx / l * 2; t.oy = drop.y + dy / l * 2
            t.formationDX = 0; t.formationDY = 0; t.fleeing = true
        }
        if t.hp <= 0 { kill(t, killer: attackerOwner) }
    }

    func kill(_ e: Entity, killer: Int) {
        guard e.alive else { return }
        e.alive = false
        e.hp = 0
        let big: Bool
        if e.isUnit {
            big = udef(e).tags.contains("massive")
            if !e.isMine {
                let p = players[e.owner]
                p.unitCount -= 1
                p.stats.unitsLost += 1
                p.stats.lostByType[e.type, default: 0] += 1
                let v = udef(e).cost.value(data.rules.economy)
                p.stats.valueLost += v
                if killer >= 0 && killer != e.owner { players[killer].stats.kills += 1; players[killer].stats.valueKilled += v }
                for cid in e.cargo { if let c = entity(byIDAny: cid), c.alive { c.carriedBy = -1; kill(c, killer: killer) } }
                e.cargo.removeAll()
            }
        } else {
            big = true
            occupy(e, false)
            let p = players[e.owner]
            let d = bdef(e)
            if e.complete {
                p.completeBuildings[d.kind, default: 1] -= 1
            }
            if d.kind == .tower && e.siteIndex < 0 { p.towerCount -= 1 }
            p.stats.buildingsLost += 1
            if e.siteIndex >= 0 && e.siteIndex < sites.count && sites[e.siteIndex].bulwarkID == e.id {
                sites[e.siteIndex].bulwarkID = -1
                sites[e.siteIndex].installation = .none
            }
            if killer >= 0 && killer != e.owner {
                players[killer].stats.valueKilled += d.cost.value(data.rules.economy)
            }
            // Refund nothing; recompute available tech.
            p.completeBuildingIDs = Set(entities.filter { $0.alive && $0.isBuilding && $0.owner == e.owner && $0.complete }.map { $0.type })
            refreshZonesSoon = true
        }
        emit(.death(x: e.x, y: e.y, big: big, owner: e.owner, air: e.isAir, building: e.isBuilding))
    }

    // MARK: Clouds, mines, EMP

    func updateClouds() {
        guard !clouds.isEmpty else { return }
        var i = 0
        while i < clouds.count {
            let c = clouds[i]
            forEachNear(c.x, c.y, c.radius) { o in
                guard o.isUnit, !o.isAir, !o.isMine, o.onMap, isEnemy(c.owner, o.owner) else { return }
                if dist2(o.x, o.y, c.x, c.y) > c.radius * c.radius { return }
                applyDamage(o, c.dps * dt, bonus: nil, attackerOwner: c.owner, sourceID: -1, ignoreArmor: true)
                if tick % 4 == 0 { o.slowMult = min(o.slowMult, c.slow) }
            }
            clouds[i].remaining -= dt
            if clouds[i].remaining <= 0 { clouds.swapAt(i, clouds.count - 1); clouds.removeLast() } else { i += 1 }
        }
    }

    func layMines(_ e: Entity) {
        let p = udef(e).params ?? [:]
        e.mineTimer += dt
        guard e.mineTimer >= (p["mineInterval"] ?? 10) else { return }
        e.mineTimer = 0
        let maxMines = Int(p["mineMax"] ?? 6)
        let mine = entities.filter { $0.isMine && $0.alive && $0.orderTarget == e.id }
        if mine.count >= maxMines { if let oldest = mine.first { oldest.alive = false } }
        let a = rng.range(0, 2 * .pi), r = rng.range(1.0, 2.6)
        let mx = e.x + cos(a) * r, my = e.y + sin(a) * r
        guard !nav.isBlocked(Int(mx), Int(my)) else { return }
        let m = Entity(id: allocID(), kind: .unit, type: e.type, owner: e.owner, x: mx, y: my, hp: 20, radius: 0.25)
        m.maxHp = 20
        m.isMine = true
        m.orderTarget = e.id
        add(m)
    }

    func updateMine(_ m: Entity) {
        guard tick % 2 == 0 else { return }
        let p = data.units[m.type].params ?? [:]
        var triggered = false
        forEachNear(m.x, m.y, 1.2) { o in
            if !triggered, o.isUnit, !o.isAir, !o.isMine, o.onMap, isEnemy(m.owner, o.owner), dist2(o.x, o.y, m.x, m.y) < 0.81 { triggered = true }
        }
        guard triggered else { return }
        let w = EffWeapon(damage: p["mineDamage"] ?? 70, interval: 1, range: 0, minRange: 0, ground: true, air: false,
                          splash: p["mineRadius"] ?? 1.6, speed: 0, bonus: nil, style: "mine")
        m.alive = false
        hit(at: m.x, m.y, primary: nil, damage: w.damage, splash: w.splash, w: w, owner: m.owner, srcType: -1_000_000, sourceID: m.id)
    }

    func autoEMP(_ e: Entity) {
        guard e.abilityCooldown <= 0, tick % 5 == 0 else { return }
        let p = udef(e).params ?? [:]
        let range = p["empRange"] ?? 8, radius = p["empRadius"] ?? 3
        var best: (Double, Double)? = nil
        var bestScore = 2.5
        forEachNear(e.x, e.y, range) { o in
            guard isEnemy(e.owner, o.owner), o.onMap, canSee(e.owner, o) else { return }
            guard o.isBuilding ? bdef(o).kind == .tower : (udef(o).tags.contains("mech") && !o.isMine) else { return }
            if dist2(e.x, e.y, o.x, o.y) > range * range { return }
            var score = 0.0
            forEachNear(o.x, o.y, radius) { q in
                guard isEnemy(e.owner, q.owner), q.onMap, dist2(q.x, q.y, o.x, o.y) <= radius * radius else { return }
                if q.isBuilding { score += bdef(q).kind == .tower ? 3 : 0 }
                else if !q.isMine && udef(q).tags.contains("mech") { score += q.linked ? 1.5 : 1 }
            }
            if score > bestScore { bestScore = score; best = (o.x, o.y) }
        }
        guard let (x, y) = best else { return }
        castEMP(e, x, y)
    }

    public func castEMP(_ e: Entity, _ x: Double, _ y: Double) {
        let p = udef(e).params ?? [:]
        let radius = p["empRadius"] ?? 3, dur = p["empDuration"] ?? 8, dmg = p["empDamage"] ?? 40
        e.abilityCooldown = p["empCooldown"] ?? 30
        e.revealedUntil = time + 2
        emit(.emp(x: x, y: y, radius: radius))
        forEachNear(x, y, radius) { q in
            guard isEnemy(e.owner, q.owner), q.onMap, dist2(q.x, q.y, x, y) <= radius * radius else { return }
            let resist = players[q.owner].mods.empResist
            q.disruptedUntil = max(q.disruptedUntil, time + dur * (1 - resist))
            if q.isBuilding || (!q.isMine && udef(q).tags.contains("mech")) {
                applyDamage(q, dmg, bonus: nil, attackerOwner: e.owner, sourceID: e.id, ignoreArmor: true)
            }
        }
    }
}
