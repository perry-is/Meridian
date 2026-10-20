import Foundation

/// Group formations for move / attack-move orders.
public enum Formation: String, CaseIterable, Sendable {
    case balanced, assault, defensive
    public var title: String { rawValue.capitalized }
}

/// Player-facing command API shared by the touch UI, desktop input, and the AI.
extension World {

    // MARK: Movement & combat

    /// Move or attack-move a group with a loose formation that preserves relative layout.
    public func commandMove(_ ids: [Int], x: Double, y: Double, attack: Bool, patrol: Bool = false, formation: Formation = .balanced) {
        let units = ids.compactMap { entity($0) }.filter { $0.isUnit && $0.onMap && !$0.isMine }
        guard !units.isEmpty else { return }
        var slots: [Int: (Double, Double)] = [:]
        if !tactics.formations {
            // Legacy layout (pre-formation): keep relative positions, or a plain grid.
            let cx = units.reduce(0) { $0 + $1.x } / Double(units.count), cy = units.reduce(0) { $0 + $1.y } / Double(units.count)
            let cols = max(1, Int(Double(units.count).squareRoot().rounded(.up)))
            let spread = units.reduce(0.0) { max($0, dist2($1.x, $1.y, cx, cy)) }.squareRoot()
            let sorted = units.sorted { ($0.y - $0.x, $0.id) < ($1.y - $1.x, $1.id) }
            let ang = atan2(y - cy, x - cx)
            for (k, u) in sorted.enumerated() {
                if spread < Double(cols) * 1.2 + 2 { slots[u.id] = (u.x - cx, u.y - cy); continue }
                let ox = (Double(k % cols) - Double(cols - 1) / 2) * 0.95, oy = (Double(k / cols) - Double((units.count - 1) / cols) / 2) * 0.95
                slots[u.id] = (ox * cos(ang + .pi / 2) + oy * cos(ang), ox * sin(ang + .pi / 2) + oy * sin(ang))
            }
        } else if units.count <= 3 {
            // Tiny groups just keep their shape.
            let cx = units.reduce(0) { $0 + $1.x } / Double(units.count), cy = units.reduce(0) { $0 + $1.y } / Double(units.count)
            for u in units { slots[u.id] = units.count == 1 ? (0, 0) : (u.x - cx, u.y - cy) }
        } else {
            slots = formationSlots(units, goalX: x, goalY: y, formation: formation)
        }
        nextGroupID += 1
        let group = nextGroupID
        let groundSpeeds = units.filter { !$0.isAir }.map { udef($0).speed * players[$0.owner].mods.unit[$0.type].speed }
        let groupSpeed = groundSpeeds.min() ?? units.map { udef($0).speed }.min() ?? 2
        for u in units {
            var (dx, dy) = slots[u.id] ?? (0, 0)
            if !u.isAir, nav.isBlocked(Int(x + dx), Int(y + dy)) { dx = 0; dy = 0 }
            u.order = patrol ? .patrol : (attack ? .attackMove : .move)
            if patrol { u.px2 = u.x; u.py2 = u.y }
            u.ox = x; u.oy = y
            u.formationDX = dx; u.formationDY = dy
            u.groupID = units.count > 3 ? group : 0
            u.groupSpeed = groupSpeed
            u.target = -1
            u.stuckTimer = 0
            u.fleeing = false
            u.losTimer = 0
            u.lastProgressX = u.x; u.lastProgressY = u.y
            if traits[u.type].worker { u.gatherNode = -1 }
        }
    }

    public func commandAttack(_ ids: [Int], target: Int) {
        guard let t = entity(target) else { return }
        for id in ids {
            guard let u = entity(id), u.isUnit, u.onMap, !u.isMine, weapon(u) != nil else { continue }
            guard let w = weapon(u), canHit(w, t) else {
                // Can't hit it: attack-move toward instead.
                commandMove([id], x: t.x, y: t.y, attack: true); continue
            }
            u.order = .attack
            u.orderTarget = target
            u.target = target
        }
    }

    public func commandStop(_ ids: [Int]) {
        for id in ids { if let u = entity(id), u.isUnit { becomeIdle(u); u.target = -1 } }
    }

    public func commandHold(_ ids: [Int]) {
        for id in ids { if let u = entity(id), u.isUnit { becomeIdle(u); u.order = .hold } }
    }

    /// Contextual command (tap / right-click) at a world point, optionally on an entity.
    public func commandSmart(_ ids: [Int], x: Double, y: Double, targetID: Int?, player: Int, formation: Formation = .balanced) {
        guard let tid = targetID, let t = entity(tid) else {
            commandMove(ids, x: x, y: y, attack: false, formation: formation)
            for id in ids { if let b = entity(id), b.isBuilding, b.owner == player { setRally(b.id, x: x, y: y) } }
            return
        }
        var rest: [Int] = []
        for id in ids {
            guard let u = entity(id), u.owner == player else { continue }
            if u.isBuilding { setRally(u.id, x: t.x, y: t.y); continue }
            let tr = traits[u.type]
            if t.isResource && tr.worker {
                commandGather([id], node: tid)
            } else if t.owner == player && t.isBuilding && !t.complete && tr.worker {
                u.order = .build; u.orderTarget = tid
            } else if t.owner == player && tr.worker && t.hp < t.maxHp && (t.isBuilding || udef(t).tags.contains("mech")) {
                u.order = .repair; u.orderTarget = tid
            } else if t.owner == player && t.isUnit && traits[t.type].capacity > 0 && !u.isAir && t.id != u.id {
                u.order = .load; u.orderTarget = tid
            } else if t.owner == player && u.isUnit && tr.capacity > 0 {
                rest.append(id)
            } else if isEnemy(player, t.owner) {
                if tr.worker { rest.append(id) } else { commandAttack([id], target: tid) }
            } else {
                rest.append(id)
            }
        }
        if !rest.isEmpty { commandMove(rest, x: x, y: y, attack: false, formation: formation) }
    }

    public func commandGather(_ ids: [Int], node: Int) {
        guard let n = entity(node), n.isResource else { return }
        for id in ids {
            guard let u = entity(id), u.isUnit, traits[u.type].worker else { continue }
            u.order = .gather
            u.gatherNode = node
            u.gatherKind = ResourceKind(rawValue: n.type) ?? .iron
            u.gatherTimer = 0
        }
    }

    public func setRally(_ building: Int, x: Double, y: Double) {
        guard let b = entity(building), b.isBuilding else { return }
        b.rallyX = x; b.rallyY = y; b.hasRally = true
    }

    /// Cycle configurable modes (Skyguard AA/ground, Bastion brace, Sentry Tower balanced/ground/air).
    public func commandToggleMode(_ ids: [Int]) {
        for id in ids {
            guard let e = entity(id) else { continue }
            if e.isUnit && traits[e.type].modes > 0 { e.mode = (e.mode + 1) % 2; if e.mode == 1 { e.target = -1 } }
            else if e.isBuilding && bdef(e).kind == .tower && (bdef(e).abilities?.contains("modes") ?? false) { e.mode = (e.mode + 1) % 3 }
        }
    }

    public func modeName(_ e: Entity) -> String? {
        if e.isUnit {
            guard traits[e.type].modes > 0 else { return nil }
            let p = udef(e).params ?? [:]
            if p["altDamage"] != nil { return e.mode == 0 ? "AA Lock" : "Ground Mode" }
            if p["braceRange"] != nil { return e.mode == 0 ? "Mobile" : "Braced" }
            return nil
        }
        if e.isBuilding && (bdef(e).abilities?.contains("modes") ?? false) { return ["Balanced", "Anti-Ground", "Anti-Air"][e.mode] }
        return nil
    }

    public func commandUnload(_ transport: Int, x: Double, y: Double) {
        guard let t = entity(transport), traits[t.type].capacity > 0, !t.cargo.isEmpty else { return }
        t.order = .unload; t.ox = x; t.oy = y; t.formationDX = 0; t.formationDY = 0
    }

    public func commandEMP(_ ids: [Int], x: Double, y: Double) {
        for id in ids {
            guard let e = entity(id), e.isUnit, traits[e.type].emp, e.abilityCooldown <= 0 else { continue }
            let r = udef(e).params?["empRange"] ?? 8
            if dist2(e.x, e.y, x, y) <= r * r { castEMP(e, x, y); return }
        }
    }

    // MARK: Production

    public func unitAvailability(_ player: Int, _ type: Int) -> String? {
        let p = players[player]
        let d = data.units[type]
        guard d.faction == p.faction else { return "Wrong faction" }
        let miss = p.missing(d.requires, data)
        if !miss.isEmpty { return "Requires " + miss.joined(separator: ", ") }
        return nil
    }

    @discardableResult
    public func commandTrain(_ building: Int, unitType: Int) -> String? {
        guard let b = entity(building), b.isBuilding, b.complete else { return "Building not ready" }
        let p = players[b.owner]
        let d = data.units[unitType]
        guard d.producedAt == bdef(b).kind, d.faction == p.faction else { return "Cannot train here" }
        if let r = unitAvailability(b.owner, unitType) { return r }
        guard b.queue.count < 5 else { return "Queue full" }
        guard p.canAfford(d.cost) else { return "Not enough resources" }
        let queuedUnits = entities.reduce(0) { acc, e in
            acc + (e.isBuilding && e.alive && e.owner == b.owner ? e.queue.filter { !$0.isUpgrade }.count : 0)
        }
        if p.unitCount + queuedUnits >= data.rules.combat.unitCap { return "Unit cap reached (\(data.rules.combat.unitCap))" }
        p.pay(d.cost)
        let t = d.buildTime * p.mods.unit[unitType].buildTime
        b.queue.append(ProdItem(isUpgrade: false, index: unitType, remaining: t, total: t, paid: d.cost))
        return nil
    }

    public func upgradeAvailability(_ player: Int, _ u: Int) -> String? {
        let p = players[player]
        let g = data.upgrades[u]
        if p.completedUpgrades.contains(u) { return "Researched" }
        if p.researching.contains(u) { return "In progress" }
        if let x = g.exclusiveWith, let xi = data.upgradeIndex[x], p.completedUpgrades.contains(xi) || p.researching.contains(xi) {
            return "Excluded by \(data.upgrades[xi].name)"
        }
        let miss = p.missing(g.requires, data)
        if !miss.isEmpty { return "Requires " + miss.joined(separator: ", ") }
        return nil
    }

    @discardableResult
    public func commandResearch(_ building: Int, upgrade: Int) -> String? {
        guard let b = entity(building), b.isBuilding, b.complete else { return "Building not ready" }
        let p = players[b.owner]
        let g = data.upgrades[upgrade]
        guard g.researchedAt == bdef(b).kind, g.faction == p.faction else { return "Cannot research here" }
        if let r = upgradeAvailability(b.owner, upgrade) { return r }
        guard b.queue.count < 5 else { return "Queue full" }
        guard p.canAfford(g.cost) else { return "Not enough resources" }
        p.pay(g.cost)
        p.researching.insert(upgrade)
        b.queue.append(ProdItem(isUpgrade: true, index: upgrade, remaining: g.time, total: g.time, paid: g.cost))
        return nil
    }

    public func commandCancel(_ building: Int, index: Int) {
        guard let b = entity(building), index >= 0, index < b.queue.count else { return }
        let it = b.queue.remove(at: index)
        players[b.owner].refund(it.paid)
        if it.isUpgrade { players[b.owner].researching.remove(it.index) }
    }

    // MARK: Construction

    public func buildingCost(_ player: Int, _ type: Int) -> Cost {
        let d = data.buildings[type]
        if d.kind == .tower {
            return d.cost.scaled(1 + data.rules.combat.towerCostGrowth * Double(players[player].towerCount))
        }
        return d.cost
    }

    /// Returns nil when placement is valid, otherwise a reason.
    public func placementError(_ player: Int, _ type: Int, tileX: Int, tileY: Int) -> String? {
        let p = players[player]
        let d = data.buildings[type]
        guard d.faction == p.faction else { return "Wrong faction" }
        let miss = p.missing(d.requires, data)
        if !miss.isEmpty { return "Requires " + miss.joined(separator: ", ") }
        for y in tileY..<(tileY + d.size) {
            for x in tileX..<(tileX + d.size) {
                guard map.inBounds(x, y), x > 0, y > 0, x < map.size - 1, y < map.size - 1 else { return "Out of bounds" }
                let i = map.idx(x, y)
                if nav.isBlocked(x, y) { return "Blocked" }
                if !p.explored[i] { return "Unexplored" }
                if d.kind != .hq && p.zones[i] & Zone.build == 0 { return "Too far from your territory" }
                if d.kind == .tower && p.zones[i] & Zone.tower == 0 { return "Towers need a nearby HQ, depot, forward structure or site" }
            }
        }
        // Keep resource lines walkable: no buildings directly adjacent to HQ.
        for e in entities where e.isBuilding && e.alive && bdef(e).kind == .hq {
            let gap = 1
            if tileX < e.tileX + e.size + gap && tileX + d.size > e.tileX - gap && tileY < e.tileY + e.size + gap && tileY + d.size > e.tileY - gap {
                return "Too close to a headquarters"
            }
        }
        if d.kind == .hq {
            for e in entities where e.isBuilding && e.alive && isEnemy(player, e.owner) {
                if dist2(e.x, e.y, Double(tileX), Double(tileY)) < 18 * 18 { return "Too close to the enemy" }
            }
        }
        return nil
    }

    /// Place a foundation and send the workers to build it. Returns error or nil.
    @discardableResult
    public func commandBuild(_ workers: [Int], type: Int, tileX: Int, tileY: Int) -> String? {
        let ws = workers.compactMap { entity($0) }.filter { $0.isUnit && traits[$0.type].worker }
        guard let first = ws.first else { return "No worker selected" }
        let player = first.owner
        if let err = placementError(player, type, tileX: tileX, tileY: tileY) { return err }
        let cost = buildingCost(player, type)
        let p = players[player]
        guard p.canAfford(cost) else { return "Not enough resources" }
        p.pay(cost)
        let b = spawnBuilding(type, owner: player, tileX: tileX, tileY: tileY, complete: false)
        for w in ws {
            if w.carryAmount > 0 { /* keep cargo; deliver later */ }
            w.order = .build
            w.orderTarget = b.id
        }
        // Nudge units out of the footprint.
        for u in entities where u.isUnit && u.onMap && !u.isAir {
            if Int(u.x) >= tileX && Int(u.x) < tileX + b.size && Int(u.y) >= tileY && Int(u.y) < tileY + b.size { pushOutOfBlocked(u) }
        }
        return nil
    }

    /// Cancel an unfinished building for a 75% refund.
    public func commandCancelConstruction(_ building: Int) {
        guard let b = entity(building), b.isBuilding, !b.complete else { return }
        let c = data.buildings[b.type].cost.scaled(0.75)
        players[b.owner].refund(c)
        b.alive = false
        occupy(b, false)
        if bdef(b).kind == .tower { players[b.owner].towerCount -= 1 }
    }
}
