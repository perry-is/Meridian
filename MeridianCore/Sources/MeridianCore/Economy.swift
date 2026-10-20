import Foundation

extension World {

    public func isDropoff(_ b: Entity) -> Bool {
        b.isBuilding && b.complete && (bdef(b).abilities?.contains("dropoff") ?? false)
    }

    // MARK: Gathering

    func orderGather(_ e: Entity) {
        let carry = data.rules.economy.carry
        var node = entity(e.gatherNode)
        if node == nil || node!.amount <= 0 {
            node = nearestResource(kind: e.carryAmount > 0 ? e.carryKind : e.gatherKind,
                                   x: e.x, y: e.y, maxDist: 12, owner: e.owner)
            if let n = node { e.gatherNode = n.id } else {
                if e.carryAmount > 0 { e.order = .returnCargo } else { becomeIdle(e) }
                return
            }
        }
        guard let n = node else { return }
        let kind = ResourceKind(rawValue: n.type)!
        if e.carryAmount > 0 && (e.carryKind != kind || e.carryAmount >= carry[kind.rawValue]) {
            e.order = .returnCargo
            return
        }
        e.gatherKind = kind
        if !moveToRect(e, n, range: 0.45) { e.gatherTimer = 0; return }
        e.facing = atan2(n.y - e.y, n.x - e.x)
        e.gatherTimer += dt * players[e.owner].mods.gather
        e.lastFireTime = time
        let need = data.rules.economy.gatherTime[kind.rawValue]
        if e.gatherTimer >= need {
            e.gatherTimer = 0
            let take = min(carry[kind.rawValue], n.amount)
            n.amount -= take
            e.carryKind = kind
            e.carryAmount = take
            if n.amount <= 0 { depleteNode(n) }
            e.order = .returnCargo
        }
    }

    func depleteNode(_ n: Entity) {
        n.alive = false
        occupy(n, false)
    }

    public func nearestResource(kind: ResourceKind, x: Double, y: Double, maxDist: Double, owner: Int) -> Entity? {
        var best: Entity? = nil
        var bd = maxDist * maxDist
        for r in entities where r.isResource && r.alive && r.type == kind.rawValue && r.amount > 0 {
            let d = dist2(x, y, r.x, r.y)
            if d < bd && (owner < 0 || players[owner].explored[tileIndex(r.x, r.y)]) { bd = d; best = r }
        }
        return best
    }

    /// Nearest drop-off: own complete HQ/depot/forward structures, plus (for Humans) captured sites.
    func nearestDropoff(_ e: Entity) -> (x: Double, y: Double, building: Entity?)? {
        var best: (Double, Double, Entity?)? = nil
        var bd = Double.infinity
        for b in entities where b.isBuilding && b.alive && b.owner == e.owner && isDropoff(b) {
            let d = dist2(e.x, e.y, b.x, b.y)
            if d < bd { bd = d; best = (b.x, b.y, b) }
        }
        if players[e.owner].faction == .humans {
            for s in sites where s.owner == e.owner && s.control >= 1 {
                let d = dist2(e.x, e.y, s.x, s.y)
                if d < bd { bd = d; best = (s.x, s.y, nil) }
            }
        }
        return best.map { (x: $0.0, y: $0.1, building: $0.2) }
    }

    func orderReturn(_ e: Entity) {
        guard e.carryAmount > 0 else { e.order = e.gatherNode >= 0 ? .gather : .idle; return }
        guard let drop = nearestDropoff(e) else { return }
        let arrived: Bool
        if let b = drop.building { arrived = moveToRect(e, b, range: 0.5) }
        else { arrived = moveTo(e, drop.x, drop.y, arrive: 1.6) }
        guard arrived else { return }
        let p = players[e.owner]
        p.res[e.carryKind.rawValue] += e.carryAmount
        p.stats.gathered[e.carryKind.rawValue] += e.carryAmount
        e.carryAmount = 0
        e.order = .gather
    }

    // MARK: Construction & repair

    func orderBuild(_ e: Entity) {
        guard let b = entity(e.orderTarget), b.isBuilding, b.owner == e.owner, !b.complete else {
            // Look for another unfinished building nearby to help with.
            if let other = entities.first(where: { $0.isBuilding && $0.alive && !$0.complete && $0.owner == e.owner && dist2($0.x, $0.y, e.x, e.y) < 100 }) {
                e.orderTarget = other.id
            } else { resumeGatherOrIdle(e) }
            return
        }
        guard moveToRect(e, b, range: 0.5) else { return }
        e.facing = atan2(b.y - e.y, b.x - e.x)
        e.lastFireTime = time
        let d = bdef(b)
        let bt = d.buildTime * players[e.owner].mods.building[b.type].buildTime
        let inc = dt / bt
        b.buildProgress += inc
        b.hp = min(b.maxHp, b.hp + b.maxHp * 0.9 * inc)
        if b.buildProgress >= 1 {
            buildingCompleted(b)
            resumeGatherOrIdle(e)
        }
    }

    func resumeGatherOrIdle(_ e: Entity) {
        if e.gatherNode >= 0, entity(e.gatherNode) != nil { e.order = .gather } else { becomeIdle(e) }
    }

    func orderRepair(_ e: Entity) {
        guard let t = entity(e.orderTarget), t.owner == e.owner, t.hp < t.maxHp else { resumeGatherOrIdle(e); return }
        if t.isBuilding && !t.complete { e.order = .build; return }
        let ok = t.isBuilding ? moveToRect(e, t, range: 0.5) : moveTo(e, t.x, t.y, arrive: e.radius + t.radius + 0.4)
        guard ok else { return }
        e.lastFireTime = time
        let rate: Double
        if t.isBuilding { rate = t.maxHp / max(10, bdef(t).buildTime) * 0.8 } else { rate = 8 }
        t.hp = min(t.maxHp, t.hp + rate * dt)
    }

    // MARK: Production / research timers

    func updateEconomyTimers() {
        let cap = data.rules.combat.unitCap
        for b in entities where b.isBuilding && b.alive && b.complete && !b.queue.isEmpty {
            let p = players[b.owner]
            var item = b.queue[0]
            if !item.isUpgrade {
                let batch = data.units[item.index].batch ?? 1
                if p.unitCount + batch > cap { continue }
            }
            item.remaining -= dt
            if item.remaining > 0 { b.queue[0] = item; continue }
            b.queue.removeFirst()
            if item.isUpgrade {
                p.researching.remove(item.index)
                completeUpgrade(p, item.index)
            } else {
                let n = data.units[item.index].batch ?? 1
                for k in 0..<n { produceUnit(b, item.index, k) }
            }
        }
    }

    func completeUpgrade(_ p: Player, _ u: Int) {
        let oldUnit = p.mods.unit, oldB = p.mods.building
        p.completedUpgrades.insert(u)
        p.recomputeMods(data)
        // Rescale existing hit points when HP multipliers change.
        for e in entities where e.alive && e.owner == p.index {
            if e.isUnit && !e.isMine {
                let r = p.mods.unit[e.type].hp / oldUnit[e.type].hp
                if r != 1 { e.maxHp *= r; e.hp *= r }
            } else if e.isBuilding {
                let r = p.mods.building[e.type].hp / oldB[e.type].hp
                if r != 1 { e.maxHp *= r; e.hp *= r }
            }
        }
        emit(.researched(owner: p.index, upgrade: u))
    }

    func produceUnit(_ b: Entity, _ type: Int, _ k: Int) {
        let p = players[b.owner]
        let d = data.units[type]
        // Spawn on the side facing the rally point.
        let rx = b.hasRally ? b.rallyX : b.x + 3, ry = b.hasRally ? b.rallyY : b.y + 3
        let ang = atan2(ry - b.y, rx - b.x) + Double(k) * 0.4
        let r = Double(b.size) * 0.5 + 0.7
        var sx = b.x + cos(ang) * r, sy = b.y + sin(ang) * r
        if d.domain == .ground && nav.isBlocked(Int(sx), Int(sy)) {
            let (ox, oy) = nav.nearestOpen(Int(sx), Int(sy)); sx = Double(ox) + 0.5; sy = Double(oy) + 0.5
        }
        let u = spawnUnit(type, owner: b.owner, x: sx, y: sy)
        u.facing = ang
        p.stats.unitsProduced += 1
        p.stats.producedByType[type, default: 0] += 1
        if b.hasRally {
            // Rally onto a resource sends workers to gather.
            if traits[type].worker, let res = resourceAt(b.rallyX, b.rallyY) {
                u.order = .gather; u.gatherNode = res.id
            } else {
                u.order = traits[type].worker ? .move : .attackMove
                u.ox = b.rallyX + Double(k) * 0.6; u.oy = b.rallyY
            }
        } else { becomeIdle(u) }
        emit(.produced(id: u.id))
    }

    public func resourceAt(_ x: Double, _ y: Double) -> Entity? {
        let i = tileIndex(x, y)
        if let e = entity(Int(occupant[i])), e.isResource { return e }
        return nil
    }

    // MARK: Healing, auras, regeneration (support systems)

    func updateSupport() {
        guard tick % 4 == 2 else { return }
        let step = dt * 4
        let rules = data.rules
        for e in entities where e.alive && e.onMap && !e.isMine && e.kind != .resource {
            if e.isUnit {
                let t = traits[e.type]
                if t.healBio || t.repairMech { healPulse(e, t, step) }
                if t.regenAura { auraHeal(e, t.auraRegen * step, t.auraRadius, tag: "bio") }
                if t.fieldRepair { auraHeal(e, t.repairRate * step, t.repairRadius, tag: "mech") }
            } else if e.isBuilding && e.complete {
                let d = bdef(e)
                if d.kind == .forward && players[e.owner].faction == .humans {
                    let rate = (d.params?["repairRate"] ?? 4) * players[e.owner].mods.forwardRepair
                    auraHeal(e, rate * step, (d.params?["repairRadius"] ?? 6) + players[e.owner].mods.stagingAdd, tag: nil)
                }
            }
            // Alien regeneration in Bloom while out of combat.
            if players[e.owner].faction == .aliens && e.hp < e.maxHp && e.inBloom {
                let quiet = time - max(e.lastDamagedTime, e.lastAttackTime) > rules.combat.outOfCombatSeconds
                if quiet {
                    let m = players[e.owner].mods.regen
                    let r = e.isBuilding ? rules.combat.buildingRegenAliens : rules.combat.alienRegenFlat + e.maxHp * rules.combat.alienRegenPercent
                    e.hp = min(e.maxHp, e.hp + r * m * step)
                }
            }
        }
        // Human staging at captured sites repairs units.
        for s in sites where s.owner >= 0 && s.control >= 1 && players[s.owner].faction == .humans {
            let rr = rules.territory.humanStagingRadius + players[s.owner].mods.stagingAdd
            forEachNear(s.x, s.y, rr) { o in
                guard o.owner == s.owner, o.isUnit, !o.isMine, o.onMap, o.hp < o.maxHp, dist2(o.x, o.y, s.x, s.y) <= rr * rr else { return }
                o.hp = min(o.maxHp, o.hp + rules.territory.humanRepairRate * step)
            }
        }
    }

    func healPulse(_ e: Entity, _ t: UnitTraits, _ step: Double) {
        var best: Entity? = nil
        var worst = 1.0
        forEachNear(e.x, e.y, t.healRange) { o in
            guard o.owner == e.owner, o.id != e.id, o.onMap, !o.isMine, o.hp < o.maxHp else { return }
            if o.isBuilding { guard t.repairMech, o.complete else { return } }
            else {
                let tags = udef(o).tags
                guard (t.healBio && tags.contains("bio")) || (t.repairMech && tags.contains("mech")) else { return }
            }
            if edgeDist(e, o) > t.healRange { return }
            let f = o.hp / o.maxHp
            if f < worst { worst = f; best = o }
        }
        guard let b = best else { return }
        b.hp = min(b.maxHp, b.hp + t.healRate * step)
        e.lastFireTime = time
        if tick % 12 == 2 { emit(.heal(x: b.x, y: b.y)) }
    }

    func auraHeal(_ e: Entity, _ amount: Double, _ radius: Double, tag: String?) {
        forEachNear(e.x, e.y, radius) { o in
            guard o.owner == e.owner, o.onMap, !o.isMine, o.hp < o.maxHp, dist2(o.x, o.y, e.x, e.y) <= radius * radius else { return }
            if let tag = tag { guard o.isUnit, udef(o).tags.contains(tag) else { return } }
            o.hp = min(o.maxHp, o.hp + amount)
        }
    }
}
