import Foundation

/// Zone bits stored in Player.zones.
public enum Zone {
    public static let bloom: UInt8 = 1
    public static let staging: UInt8 = 2
    public static let network: UInt8 = 4
    public static let build: UInt8 = 8
    public static let tower: UInt8 = 16
}

nonisolated(unsafe) private var circleCache: [Int: [(Int, Int)]] = [:]

func circleOffsets(_ r: Double) -> [(Int, Int)] {
    let key = Int((r * 2).rounded(.up))
    if let c = circleCache[key] { return c }
    let rr = Double(key) / 2
    var out: [(Int, Int)] = []
    let ir = Int(rr.rounded(.up))
    for dy in -ir...ir { for dx in -ir...ir where Double(dx * dx + dy * dy) <= rr * rr { out.append((dx, dy)) } }
    circleCache[key] = out
    return out
}

extension World {

    func stamp(_ grid: inout [UInt8], _ x: Double, _ y: Double, _ r: Double, _ bit: UInt8) {
        let cx = Int(x), cy = Int(y), n = map.size
        for (dx, dy) in circleOffsets(r) {
            let tx = cx + dx, ty = cy + dy
            if tx >= 0 && ty >= 0 && tx < n && ty < n { grid[ty * n + tx] |= bit }
        }
    }

    // MARK: Zones

    func refreshZones() {
        let tr = data.rules.territory
        for p in players {
            var z = [UInt8](repeating: 0, count: map.size * map.size)
            let f = p.faction
            for b in entities where b.isBuilding && b.alive && b.owner == p.index {
                let d = bdef(b)
                stamp(&z, b.x, b.y, 12 + Double(b.size) / 2, Zone.build)
                if b.complete && [.hq, .forward, .depot].contains(d.kind) {
                    stamp(&z, b.x, b.y, data.rules.combat.towerBuildRadius, Zone.tower)
                }
                guard b.complete else { continue }
                switch f {
                case .aliens:
                    let r: Double = d.kind == .hq ? 10 : (d.kind == .forward ? (d.params?["bloomRadius"] ?? 10) + p.mods.bloomAdd : 4)
                    stamp(&z, b.x, b.y, r, Zone.bloom)
                case .humans:
                    if d.kind == .hq { stamp(&z, b.x, b.y, 8, Zone.staging) }
                    if d.kind == .forward { stamp(&z, b.x, b.y, (d.params?["repairRadius"] ?? 6) + p.mods.stagingAdd, Zone.staging) }
                case .machines:
                    if d.kind == .hq { stamp(&z, b.x, b.y, 8, Zone.network) }
                    if let nr = d.params?["nodeRadius"] { stamp(&z, b.x, b.y, nr + p.mods.linkRadius, Zone.network) }
                }
            }
            for s in sites where s.owner == p.index && s.control >= 1 {
                stamp(&z, s.x, s.y, 9, Zone.build)
                stamp(&z, s.x, s.y, data.rules.combat.towerBuildRadius * 0.7, Zone.tower)
                switch f {
                case .aliens: stamp(&z, s.x, s.y, tr.alienBloomRadius + p.mods.bloomAdd, Zone.bloom)
                case .humans: stamp(&z, s.x, s.y, tr.humanStagingRadius + p.mods.stagingAdd, Zone.staging)
                case .machines: stamp(&z, s.x, s.y, tr.machineNodeRadius + p.mods.linkRadius, Zone.network)
                }
            }
            for u in entities where u.isUnit && u.onMap && u.owner == p.index && !u.isMine {
                let t = traits[u.type]
                if t.networkNode { stamp(&z, u.x, u.y, t.nodeRadius + p.mods.linkRadius, Zone.network) }
                if t.bloomNode && !u.moving { stamp(&z, u.x, u.y, t.bloomRadius + p.mods.bloomAdd, Zone.bloom) }
            }
            p.zones = z
        }
    }

    // MARK: Auras (network links, jamming, slow fields, bloom, staging)

    func updateAuras() {
        let cr = data.rules.combat
        for e in entities where e.alive && e.onMap {
            e.slowMult = 1; e.jammedMult = 1; e.linked = false; e.supplied = false; e.inBloom = false
        }
        // Jammers and suppression fields.
        for e in entities where e.isUnit && e.onMap && !e.isMine {
            let t = traits[e.type]
            if t.jam {
                forEachNear(e.x, e.y, t.jamRadius) { o in
                    guard isEnemy(e.owner, o.owner), o.onMap, dist2(o.x, o.y, e.x, e.y) <= t.jamRadius * t.jamRadius else { return }
                    o.jammedMult = max(o.jammedMult, t.jamMult)
                    let resist = players[o.owner].mods.empResist
                    o.disruptedUntil = max(o.disruptedUntil, time + 0.4 * (1 - resist))
                }
            }
            if t.slowField {
                forEachNear(e.x, e.y, t.slowRadius) { o in
                    guard isEnemy(e.owner, o.owner), o.isUnit, !o.isAir, !o.isMine, o.onMap,
                          dist2(o.x, o.y, e.x, e.y) <= t.slowRadius * t.slowRadius else { return }
                    o.slowMult = min(o.slowMult, t.slowMult)
                    applyDamage(o, t.fieldDps * dt * 4, bonus: nil, attackerOwner: e.owner, sourceID: e.id, ignoreArmor: true)
                }
            }
        }
        // Faction zones and machine links.
        for e in entities where e.alive && e.onMap && e.kind != .resource && !e.isMine {
            let p = players[e.owner]
            let z = p.zones[tileIndex(e.x, e.y)]
            switch p.faction {
            case .aliens: e.inBloom = z & Zone.bloom != 0
            case .humans: e.supplied = e.isUnit && z & Zone.staging != 0
            case .machines:
                guard e.disruptedUntil <= time else { continue }
                if e.isBuilding {
                    if bdef(e).kind == .tower { e.linked = towerLinked(e) }
                } else if z & Zone.network != 0 {
                    e.linked = true
                } else {
                    let r = cr.networkLinkRadius + p.mods.linkRadius
                    var c = 0
                    forEachNear(e.x, e.y, r) { o in
                        if c < cr.networkLinkMinNeighbors, o.id != e.id, o.owner == e.owner, o.isUnit, !o.isMine, o.onMap,
                           dist2(o.x, o.y, e.x, e.y) <= r * r { c += 1 }
                    }
                    e.linked = c >= cr.networkLinkMinNeighbors
                }
            }
        }
    }

    func towerLinked(_ t: Entity) -> Bool {
        let p = players[t.owner]
        for b in entities where b.isBuilding && b.alive && b.complete && b.owner == t.owner && b.id != t.id {
            let d = bdef(b)
            let r: Double
            switch d.kind {
            case .hq: r = 9
            case .forward: r = (d.params?["nodeRadius"] ?? 9) + p.mods.linkRadius
            case .tower: r = (d.params?["nodeRadius"] ?? 5) + p.mods.linkRadius
            default: continue
            }
            if dist2(b.x, b.y, t.x, t.y) <= r * r { return true }
        }
        for s in sites where s.owner == t.owner && s.control >= 1 {
            let r = data.rules.territory.machineNodeRadius + p.mods.linkRadius
            if dist2(s.x, s.y, t.x, t.y) <= r * r { return true }
        }
        return false
    }

    // MARK: Fog of war

    func updateFog() {
        let n = map.size
        let tr = data.rules.territory
        for p in players {
            for i in 0..<(n * n) { p.visible[i] = 0; p.detected[i] = false }
        }
        // Allies share vision and detection: everything a team member sees is stamped into every teammate's grid.
        for e in entities where e.alive && e.onMap && e.kind != .resource && e.owner >= 0 {
            let s = e.isMine ? 1.5 : sight(e)
            var det = 0.0
            if e.isUnit && !e.isMine { det = traits[e.type].detectRange }
            else if e.isBuilding && e.complete && e.jammedMult == 1 && e.disruptedUntil <= time { det = bdef(e).params?["detectRange"] ?? 0 }
            for pi in teammates[e.owner] {
                let p = players[pi]
                stamp(&p.visible, e.x, e.y, s, 1)
                if det > 0 { stampDetect(p, e.x, e.y, det) }
            }
        }
        for s in sites where s.owner >= 0 && s.control >= 1 {
            let v = s.installation == .watchpost ? tr.watchVision : tr.vision
            for pi in teammates[s.owner] {
                let p = players[pi]
                stamp(&p.visible, s.x, s.y, v, 1)
                if s.installation == .watchpost { stampDetect(p, s.x, s.y, v) }
            }
        }
        for p in players {
            for i in 0..<(n * n) where p.visible[i] != 0 { p.explored[i] = true }
        }
    }

    func stampDetect(_ p: Player, _ x: Double, _ y: Double, _ r: Double) {
        let cx = Int(x), cy = Int(y), n = map.size
        for (dx, dy) in circleOffsets(r) {
            let tx = cx + dx, ty = cy + dy
            if tx >= 0 && ty >= 0 && tx < n && ty < n { p.detected[ty * n + tx] = true }
        }
    }

    // MARK: Territory capture & income

    func updateTerritory(_ step: Double) {
        let tr = data.rules.territory
        var present = [Int](repeating: 0, count: players.count)
        for i in sites.indices {
            for k in present.indices { present[k] = 0 }
            let s = sites[i]
            forEachNear(s.x, s.y, tr.captureRadius) { o in
                guard o.isUnit, o.onMap, !o.isMine, traits[o.type].canCapture, dist2(o.x, o.y, s.x, s.y) <= tr.captureRadius * tr.captureRadius else { return }
                present[o.owner] += 1
            }
            // Allies capture together: a site is contested only when two different teams stand on it.
            let teamsPresent = Set(present.indices.filter { present[$0] > 0 }.map { teamOf[$0] })
            sites[i].contested = teamsPresent.count > 1
            if teamsPresent.count == 1 {
                let team = teamsPresent.first!
                let members = present.indices.filter { present[$0] > 0 }
                let strength = members.reduce(0) { $0 + present[$1] }
                // The site goes to the ally with the most units on it (an allied owner keeps it).
                let p = s.owner >= 0 && teamOf[s.owner] == team ? s.owner : members.max { (present[$0], -$0) < (present[$1], -$1) }!
                let rate = step / tr.captureTime * min(tr.maxCaptureMult, 1 + 0.5 * Double(strength - 1))
                if s.owner == p {
                    sites[i].control = min(1, s.control + rate)
                } else if s.owner >= 0 {
                    sites[i].control -= rate
                    if sites[i].control <= 0 {
                        let old = s.owner
                        sites[i].owner = -1
                        sites[i].control = 0
                        sites[i].capturer = p
                        if let b = entity(s.bulwarkID) { kill(b, killer: p) }
                        sites[i].installation = .none
                        sites[i].bulwarkID = -1
                        emit(.message(owner: old, text: "Lost control of a strategic site"))
                        refreshZonesSoon = true
                    }
                } else {
                    if s.capturer != p { sites[i].capturer = p; sites[i].control = max(0, s.capturer < 0 ? s.control : 0) }
                    sites[i].control += rate
                    if sites[i].control >= 1 {
                        sites[i].control = 1
                        sites[i].owner = p
                        sites[i].capturer = -1
                        emit(.captured(site: i, owner: p))
                        refreshZonesSoon = true
                    }
                }
            } else if teamsPresent.isEmpty {
                if s.owner < 0 { sites[i].control = max(0, s.control - step / tr.captureTime * 0.5) }
                else { sites[i].control = min(1, s.control + step / tr.captureTime * 0.5) }
            }
            // Income.
            let o = sites[i].owner
            if o >= 0 && sites[i].control >= 1 {
                let m = sites[i].installation == .extractor ? tr.extractorIncomeMult : 1
                for k in 0..<3 {
                    sites[i].incomeAcc[k] += tr.income[k] * m * step
                    let whole = Int(sites[i].incomeAcc[k])
                    if whole > 0 {
                        sites[i].incomeAcc[k] -= Double(whole)
                        players[o].res[k] += whole
                        players[o].stats.territoryIncome[k] += Double(whole)
                    }
                }
            }
        }
        // Dominance victory (optional mode): a team holding enough sites runs down a shared countdown.
        guard config.victory == .dominance, !sandbox else { return }
        let need = dominanceRequirement
        var teamOwned: [Int: Int] = [:]
        for s in sites where s.owner >= 0 && s.control >= 1 { teamOwned[teamOf[s.owner], default: 0] += 1 }
        for p in players where !p.defeated {
            if (teamOwned[p.team] ?? 0) >= need && time >= tr.dominanceStart { p.dominanceTimer += step } else { p.dominanceTimer = 0 }
            if p.dominanceTimer >= tr.dominanceSeconds && winner == nil {
                winner = activePlayers(team: p.team).first?.index ?? p.index
                victoryReason = "Territorial dominance"
            }
        }
    }

    public var dominanceRequirement: Int { Int((Double(sites.count) * data.rules.territory.dominanceFraction).rounded(.up)) }
    /// Sites held (fully controlled) by a team.
    public func sitesHeld(team: Int) -> Int { sites.filter { $0.owner >= 0 && $0.control >= 1 && teamOf[$0.owner] == team }.count }

    // MARK: Site installations

    @discardableResult
    public func configureSite(_ i: Int, player: Int, installation: Installation) -> String? {
        guard i >= 0 && i < sites.count else { return "No site" }
        let s = sites[i]
        guard s.owner == player, s.control >= 1 else { return "You must control this site" }
        guard s.installation == .none else { return "Site already configured" }
        let cost = data.rules.territory.installCost
        let p = players[player]
        guard p.canAfford(cost) else { return "Not enough resources" }
        p.pay(cost)
        sites[i].installation = installation
        if installation == .bulwark {
            let t = data.building(p.faction, .tower)
            let tx = Int(s.x) - 1, ty = Int(s.y) - 1
            for y in ty..<(ty + 2) { for x in tx..<(tx + 2) where occupant[map.idx(x, y)] >= 0 {
                if let r = entity(Int(occupant[map.idx(x, y)])), r.isResource { depleteNode(r) } } }
            let b = spawnBuilding(t, owner: player, tileX: tx, tileY: ty, complete: true)
            b.siteIndex = i
            b.maxHp = data.rules.territory.bulwarkHp * data.faction(p.faction).hpMult
            b.hp = b.maxHp
            p.towerCount -= 1     // bulwarks don't count toward tower cost scaling
            sites[i].bulwarkID = b.id
        }
        refreshZonesSoon = true
        return nil
    }

    // MARK: Victory

    /// A commander with no structures left is out of the fight: their remaining forces disband and their
    /// production stops. The match ends when a single team remains.
    func checkVictory() {
        guard winner == nil, !sandbox else { return }
        for p in players where !p.defeated {
            let hasBuilding = entities.contains { $0.isBuilding && $0.alive && $0.owner == p.index && $0.siteIndex < 0 }
            if !hasBuilding { eliminate(p) }
        }
        let teamsAlive = Set(players.filter { !$0.defeated }.map { $0.team })
        if teamsAlive.count == 1 {
            let team = teamsAlive.first!
            winner = activePlayers(team: team).first?.index ?? -1
            victoryReason = players.count > 2 ? "All enemies eliminated" : "Enemy base destroyed"
        } else if teamsAlive.isEmpty {
            winner = -1
            victoryReason = "Mutual destruction"
        }
    }

    func eliminate(_ p: Player) {
        p.defeated = true
        for e in entities where e.alive && e.owner == p.index {
            if e.isUnit { kill(e, killer: -1) }
            else if e.isBuilding { e.queue.removeAll() }
        }
        p.researching.removeAll()
        // Their sites fall neutral (and their bulwarks with them): nobody holds ground without a commander.
        for i in sites.indices where sites[i].owner == p.index {
            if let b = entity(sites[i].bulwarkID) { kill(b, killer: -1) }
            sites[i].owner = -1; sites[i].control = 0; sites[i].capturer = -1
            sites[i].installation = .none; sites[i].bulwarkID = -1
        }
        p.dominanceTimer = 0
        refreshZonesSoon = true
        for pl in players { emit(.message(owner: pl.index, text: "\(p.name) has been eliminated")) }
    }
}
