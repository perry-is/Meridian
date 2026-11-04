import Foundation

public enum Difficulty: String, CaseIterable, Sendable {
    case easy, normal, hard
    public var title: String { rawValue.capitalized }
}

/// Strategy personalities give matches variety and are used by the balance harness.
public enum AIStrategy: String, CaseIterable, Sendable {
    case balanced, aggressive, territorial, tech
}

/// Rule-based computer opponent. It only issues the same commands a human can.
public final class AIController {
    public let player: Int
    public let difficulty: Difficulty
    public let strategy: AIStrategy
    var rng: RNG
    var nextThink = 0.0
    var thinkInterval: Double
    var workerTarget: Int
    var attackThreshold: Double
    var maxQueue: Int
    /// Difficulty shaping (decision-making only — the AI never gets or loses stats or resources):
    var firstAttack: Double = 330      // earliest attack time
    var attackGap: Double = 45         // rest between attacks
    var waveCap = 0                    // most units sent per attack (0 = whole army)
    var retreatAt = 0.5                // fall back after losing this share of the attack force
    var attackGroup = Set<Int>()
    var attacking = false
    var attackTarget: (Double, Double)? = nil
    var attackStartValue = 0.0
    var lastAttackEnd = -1000.0
    var scoutID = -1
    var scouted = false
    var enemySeen: [Int: Int] = [:]     // unit def -> count recently seen
    var enemyTowersSeen = 0
    var enemyCloakSeen = false
    var siteSquads: [Int: [Int]] = [:]  // site index -> unit ids
    public private(set) var lastPlan = ""
    func setPlan(_ s: String) { lastPlan = s }
    /// Match time on the AI's clock: Quick Match runs faster, so its plans scale with it.
    @inline(__always) func clock(_ w: World) -> Double { w.time / (w.data.rules.tempo ?? 1) }
    var armyCount = 0
    var raided = false
    var assembling = false
    var assembleSince = 0.0
    /// Hard AI: a small raiding party that harasses enemy workers and lightly held sites between attacks.
    var raidGroup = Set<Int>()
    var raidTarget: (Double, Double)? = nil
    var raidStart = 0.0
    var raidStartValue = 0.0
    var lastRaidEnd = -1000.0
    /// Hard AI: the second prong of a large attack and its objective.
    var prongGroup = Set<Int>()
    var prongTarget: (Double, Double)? = nil
    /// Counters for the harness and tests (not saved).
    public private(set) var raidsLaunched = 0
    public private(set) var prongsLaunched = 0

    public init(player: Int, difficulty: Difficulty, strategy: AIStrategy = .balanced, seed: UInt64 = 1) {
        self.player = player
        self.difficulty = difficulty
        self.strategy = strategy
        rng = RNG(seed: seed &+ UInt64(player) &* 977)
        switch difficulty {
        case .easy:
            // A gentle opponent a beginner can beat: slow to react, small economy, late, small, cautious attacks.
            thinkInterval = 4.0; workerTarget = 6; attackThreshold = 5600; maxQueue = 1
            firstAttack = 780; attackGap = 300; waveCap = 8; retreatAt = 0.7
        case .normal:
            thinkInterval = 3.0; workerTarget = 8; attackThreshold = 5000; maxQueue = 1
            firstAttack = 600; attackGap = 230; retreatAt = 0.62
        case .hard: thinkInterval = 0.5; workerTarget = 34; attackThreshold = 2600; maxQueue = 2
        }
        switch strategy {
        case .aggressive: attackThreshold *= 0.7; workerTarget = max(6, workerTarget - 3); firstAttack -= 90
        case .territorial: attackThreshold *= 1.15
        case .tech: attackThreshold *= 1.3; workerTarget += 2
        case .balanced: break
        }
        nextThink = Double(player) * 0.13
    }

    // MARK: Main loop

    public func update(_ w: World) {
        // Reaction speed stays in real seconds, whatever the match pace.
        guard w.time >= nextThink, !w.players[player].defeated, w.winner == nil else { return }
        nextThink = w.time + thinkInterval
        let p = w.players[player]
        observe(w)
        let myUnits = w.units(of: player)
        let myBuildings = w.buildings(of: player)
        guard !myBuildings.isEmpty else { return }
        let workers = myUnits.filter { w.traits[$0.type].worker }
        let army = myUnits.filter { !w.traits[$0.type].worker && w.traits[$0.type].capacity == 0 && $0.id != scoutID }

        manageWorkers(w, workers, myBuildings)
        var reserve = manageConstruction(w, p, workers, myBuildings)
        // Units come first until a minimum army exists; only then save up for buildings.
        let minArmy = Int(3 + clock(w) / 25)
        if army.count < min(minArmy, 30) { reserve = Cost() }
        armyCount = army.count
        manageResearch(w, p, myBuildings, reserve: reserve)
        manageProduction(w, p, myBuildings, workers: workers.count, army: army, reserve: reserve)
        manageSites(w, p)
        manageArmy(w, p, army, myBuildings)
        manageScout(w, myUnits)
        manageModes(w, army)
    }

    // MARK: Observation

    func observe(_ w: World) {
        var seen: [Int: Int] = [:]
        var towers = 0
        for e in w.entities where e.alive && e.onMap && w.isEnemy(player, e.owner) && w.canSee(player, e) {
            if e.isUnit && !e.isMine { seen[e.type, default: 0] += 1; if w.isCloaked(e) { enemyCloakSeen = true } }
            else if e.isBuilding && w.bdef(e).kind == .tower { towers += 1 }
        }
        // Exponential memory of enemy composition.
        for (k, v) in enemySeen { enemySeen[k] = Int(Double(v) * 0.9) }
        for (k, v) in seen { enemySeen[k] = max(enemySeen[k] ?? 0, v) }
        enemyTowersSeen = max(towers, Int(Double(enemyTowersSeen) * 0.95))
        // Units killed by an invisible attacker hint at cloaked enemies.
        if !enemyCloakSeen {
            for f in [w.data.unitIndex["h_ghost"], w.data.unitIndex["a_shadeling"], w.data.unitIndex["m_jammer"]] {
                if let f = f, seen[f] != nil { enemyCloakSeen = true }
            }
        }
    }

    func enemyComposition(_ w: World) -> (air: Double, armored: Double, light: Double, total: Int) {
        // Uses the AI's own memory of what it has seen, not hidden information.
        var air = 0.0, arm = 0.0, light = 0.0, tot = 0
        for (k, v) in enemySeen where v > 0 {
            let u = w.data.units[k]
            guard u.role != "worker" else { continue }
            tot += v
            if u.domain == .air { air += Double(v) }
            if u.tags.contains("armored") { arm += Double(v) }
            if u.tags.contains("light") { light += Double(v) }
        }
        let t = Double(max(1, tot))
        return (air / t, arm / t, light / t, tot)
    }

    // MARK: Economy

    func manageWorkers(_ w: World, _ workers: [Entity], _ buildings: [Entity]) {
        let p = w.players[player]
        let drops = buildings.filter { w.isDropoff($0) }
        guard !drops.isEmpty else { return }
        // Desired split shifts toward gold once tier 2 is reachable.
        var counts = [0, 0, 0]
        for u in workers where u.order == .gather || u.order == .returnCargo { counts[u.gatherKind.rawValue] += 1 }
        let tier2 = p.completedUpgrades.contains(w.data.upgradeIndex["\(prefix(p))_tier2"]!)
        let n = Double(workers.count)
        // Base demand ratios, then shift away from resources we are already stockpiling.
        var demand = tier2 ? [0.45, 0.2, 0.35] : (clock(w) < 150 ? [0.62, 0.0, 0.38] : [0.52, 0.13, 0.35])
        for k in 0..<3 { demand[k] /= 1 + Double(max(0, p.res[k] - 150)) / 250 }
        let tot = demand.reduce(0, +)
        let want = demand.map { n * $0 / max(0.001, tot) }
        for u in workers where u.order == .idle || ((u.order == .gather) && w.entity(u.gatherNode) == nil && u.carryAmount == 0) {
            // Pick the most under-served resource that has a node near a drop-off.
            let order = (0..<3).sorted { (Double(counts[$0]) - want[$0]) < (Double(counts[$1]) - want[$1]) }
            for k in order {
                if let node = nodeNearDropoff(w, ResourceKind(rawValue: k)!, drops, from: u) {
                    w.commandGather([u.id], node: node.id)
                    counts[k] += 1
                    break
                }
            }
        }
        // Rebalance: if a resource is badly oversubscribed move one worker per think.
        for k in 0..<3 where Double(counts[k]) > want[k] + 3 {
            let target = (0..<3).min { Double(counts[$0]) - want[$0] < Double(counts[$1]) - want[$1] }!
            if let u = workers.first(where: { $0.order == .gather && $0.gatherKind.rawValue == k && $0.carryAmount == 0 }),
               let node = nodeNearDropoff(w, ResourceKind(rawValue: target)!, drops, from: u) {
                w.commandGather([u.id], node: node.id)
                break
            }
        }
    }

    func nodeNearDropoff(_ w: World, _ kind: ResourceKind, _ drops: [Entity], from u: Entity) -> Entity? {
        var best: Entity? = nil
        var bd = Double.infinity
        for r in w.entities where r.isResource && r.alive && r.type == kind.rawValue && r.amount > 0 {
            var dd = Double.infinity
            for d in drops { dd = min(dd, dist2(d.x, d.y, r.x, r.y)) }
            if dd > 15 * 15 { continue }
            let score = dd + dist2(u.x, u.y, r.x, r.y) * 0.1
            if score < bd { bd = score; best = r }
        }
        return best
    }

    // MARK: Construction

    func prefix(_ p: Player) -> String { ["humans": "h", "machines": "m", "aliens": "a"][p.faction.rawValue]! }

    func count(_ w: World, _ kind: BuildingKind, includeUnfinished: Bool = true) -> Int {
        w.entities.filter { $0.isBuilding && $0.alive && $0.owner == player && $0.siteIndex < 0 && w.bdef($0).kind == kind && (includeUnfinished || $0.complete) }.count
    }

    /// Returns the cost the AI is saving for (production avoids dipping into it).
    func manageConstruction(_ w: World, _ p: Player, _ workers: [Entity], _ buildings: [Entity]) -> Cost {
        let t = clock(w)
        let px = prefix(p)
        let tier2 = p.completedUpgrades.contains(w.data.upgradeIndex["\(px)_tier2"]!)
        let tier3 = p.completedUpgrades.contains(w.data.upgradeIndex["\(px)_tier3"]!)
        let ownedSites = w.sites.filter { $0.owner == player && $0.control >= 1 }.count
        let hard = difficulty == .hard, easy = difficulty != .hard
        var goals: [(BuildingKind, Int)] = [(.infantry, 1)]
        if workers.count >= 8 || t > 70 { goals.append((.depot, 1)) }
        if t > 150 || strategy == .tech { goals.append((.research, 1)) }
        if (strategy != .aggressive || t > 300) && (difficulty != .easy || t > 600) { goals.append((.tower, (t > 150 || raided) ? 1 : 0)) }
        if p.faction == .machines { goals.insert((.tower, t > 75 ? (t > 220 ? 2 : 1) : 0), at: 1) }
        if ownedSites > 0 && t > 200 { goals.append((.forward, 1)) }
        if tier2 { goals.append((.heavy, 1)); if t > 330 { goals.append((.air, 1)) } }
        let slow = w.data.faction(p.faction).buildTimeMult > 1.2
        let fast = w.data.faction(p.faction).buildTimeMult < 0.9
        if !easy && t > (slow ? 120 : (fast ? 260 : 170)) { goals.append((.infantry, 2)) }
        if slow && !easy && t > 380 { goals.append((.infantry, 3)) }
        if tier2 && !easy && t > 480 { goals.append((.heavy, 2)) }
        if hard && t > 420 { goals.append((.infantry, 3)) }
        if ownedSites >= 2 && t > 420 { goals.append((.depot, 2)); goals.append((.forward, 2)) }
        if t > 600 { goals.append((.tower, easy ? 1 : min(4, 1 + ownedSites))) }
        if tier3 && !easy { goals.append((.air, strategy == .tech ? 2 : 1)) }
        if strategy == .aggressive && !easy { goals.insert((.infantry, 2), at: 1) }
        // Saturated production: when every factory is busy and money is piling up, add a factory.
        let factories = buildings.filter { $0.complete && [.infantry, .heavy, .air].contains(w.bdef($0).kind) }
        let saturated = !factories.isEmpty && factories.allSatisfy { $0.queue.count >= maxQueue }
        let bankThreshold = easy ? 900 : (hard ? 300 : 450)
        if saturated && p.res[0] > bankThreshold && t > 200 && factories.count < (easy ? 3 : 9) {
            let inf = count(w, .infantry), hv = count(w, .heavy), ar = count(w, .air)
            if tier2 && hv < inf && p.res[1] > 150 { goals.append((.heavy, hv + 1)) }
            else if tier2 && ar < 2 && p.res[1] > 250 { goals.append((.air, ar + 1)) }
            else { goals.append((.infantry, inf + 1)) }
        }
        // Production capacity first, then economy, then tech and defence.
        let prio: [BuildingKind: Int] = [.infantry: 0, .depot: 1, .heavy: 2, .air: 3, .tower: 4, .research: 5, .forward: 6, .hq: 7]
        goals = goals.enumerated().sorted { (prio[$0.element.0]!, $0.offset) < (prio[$1.element.0]!, $1.offset) }.map { $0.element }
        // Unfinished buildings without builders get a worker.
        for b in buildings where !b.complete {
            let builders = workers.filter { $0.order == .build && $0.orderTarget == b.id }
            if builders.isEmpty, let wk = nearestWorker(workers, b.x, b.y) { wk.order = .build; wk.orderTarget = b.id }
        }
        if buildings.filter({ !$0.complete }).count >= (easy ? 1 : (hard ? 3 : 2)) { return Cost() }

        for (kind, want) in goals where count(w, kind) < want {
            let type = w.data.building(p.faction, kind)
            let d = w.data.buildings[type]
            if !p.meets(d.requires, w.data) { continue }
            let cost = w.buildingCost(player, type)
            if !p.canAfford(cost) { return cost }
            guard let spot = findSpot(w, p, type, kind, buildings) else { continue }
            guard let wk = nearestWorker(workers, Double(spot.0), Double(spot.1)) else { return Cost() }
            if w.commandBuild([wk.id], type: type, tileX: spot.0, tileY: spot.1) == nil {
                lastPlan = "Building \(d.name)"
            }
            return Cost()
        }
        return Cost()
    }

    func nearestWorker(_ workers: [Entity], _ x: Double, _ y: Double) -> Entity? {
        workers.filter { $0.order != .build && $0.carryAmount == 0 }.min { dist2($0.x, $0.y, x, y) < dist2($1.x, $1.y, x, y) }
            ?? workers.filter { $0.order != .build }.min { dist2($0.x, $0.y, x, y) < dist2($1.x, $1.y, x, y) }
    }

    func baseCenter(_ w: World) -> (Double, Double) {
        if let hq = w.entities.first(where: { $0.isBuilding && $0.alive && $0.owner == player && w.bdef($0).kind == .hq }) { return (hq.x, hq.y) }
        if let b = w.buildings(of: player).first { return (b.x, b.y) }
        return (Double(w.map.size) / 2, Double(w.map.size) / 2)
    }

    /// The nearest enemy commander's start (start positions are public knowledge). With several enemies the AI
    /// concentrates on the closest one still in the fight.
    func enemyBase(_ w: World) -> (Double, Double) {
        let (bx, by) = baseCenter(w)
        var best: (Double, Double)? = nil
        var bd = Double.infinity
        for e in w.players where w.isEnemy(player, e.index) && !e.defeated {
            let s = w.map.starts[e.index % w.map.starts.count]
            let p = (Double(s.x) + 2, Double(s.y) + 2)
            let d = dist2(p.0, p.1, bx, by)
            if d < bd { bd = d; best = p }
        }
        return best ?? (Double(w.map.size) / 2, Double(w.map.size) / 2)
    }

    /// Structures of allied commanders (defended when they are within reach of our own base).
    func allyBuildings(_ w: World) -> [Entity] {
        w.entities.filter { $0.isBuilding && $0.alive && w.isAlly(player, $0.owner) }
    }

    func findSpot(_ w: World, _ p: Player, _ type: Int, _ kind: BuildingKind, _ buildings: [Entity]) -> (Int, Int)? {
        let size = w.data.buildings[type].size
        let (bx, by) = baseCenter(w)
        let (ex, ey) = enemyBase(w)
        var anchor = (bx, by)
        var minR = 5, maxR = 13
        switch kind {
        case .depot:
            // Near the resource cluster that is furthest from current drop-offs but inside territory.
            let drops = buildings.filter { w.isDropoff($0) }
            var best: (Double, Double)? = nil
            var bestScore = -1.0
            let scarce = (0..<3).min { p.res[$0] < p.res[$1] }!
            for r in w.entities where r.isResource && r.alive && r.amount > 150 && p.zones[w.tileIndex(r.x, r.y)] & Zone.build != 0 {
                var dd = Double.infinity
                for d in drops { dd = min(dd, dist2(d.x, d.y, r.x, r.y)) }
                let score = min(dd, 400) * (r.type == scarce ? 2 : 1)
                if score > bestScore { bestScore = score; best = (r.x, r.y) }
            }
            if let b = best, bestScore > 36 { anchor = b; minR = 2; maxR = 6 } else { minR = 4; maxR = 10 }
        case .forward:
            let owned = w.sites.enumerated().filter { $0.element.owner == player && $0.element.control >= 1 }
            if let s = owned.min(by: { dist2($0.element.x, $0.element.y, ex, ey) < dist2($1.element.x, $1.element.y, ex, ey) }) {
                // Skip sites that already have a forward structure.
                let hasFwd = buildings.contains { w.bdef($0).kind == .forward && dist2($0.x, $0.y, s.element.x, s.element.y) < 64 }
                if hasFwd, let other = owned.first(where: { o in !buildings.contains { w.bdef($0).kind == .forward && dist2($0.x, $0.y, o.element.x, o.element.y) < 64 } }) {
                    anchor = (other.element.x, other.element.y)
                } else { anchor = (s.element.x, s.element.y) }
                minR = 3; maxR = 7
            }
        case .tower:
            // Between base and enemy, or guarding a forward structure.
            let fwd = buildings.filter { w.bdef($0).kind == .forward && $0.complete }
            let towers = count(w, .tower)
            if p.faction == .machines && towers < 2 {
                // Guard the mineral line: between HQ and the nearest iron cluster.
                if let iron = w.nearestResource(kind: .iron, x: bx, y: by, maxDist: 14, owner: player) {
                    anchor = ((bx + iron.x) / 2, (by + iron.y) / 2); minR = 1; maxR = 6
                }
            } else if let f = fwd.first, towers >= 1 { anchor = (f.x, f.y); minR = 2; maxR = 5 }
            else if !(p.faction == .machines && towers < 2) {
                let dx = ex - bx, dy = ey - by
                let l = max(1, (dx * dx + dy * dy).squareRoot())
                anchor = (bx + dx / l * 7, by + dy / l * 7); minR = 0; maxR = 5
            }
        default:
            // Production away from the mineral line: bias toward the enemy side a little.
            let dx = ex - bx, dy = ey - by
            let l = max(1, (dx * dx + dy * dy).squareRoot())
            anchor = (bx + dx / l * 5, by + dy / l * 5)
            minR = 2; maxR = 12
        }
        let ax = Int(anchor.0) - size / 2, ay = Int(anchor.1) - size / 2
        var candidates: [(Int, Int, Int)] = []
        for r in minR...maxR {
            for dy in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dy) == r {
                    candidates.append((ax + dx, ay + dy, r))
                }
            }
            if candidates.count > 400 { break }
        }
        for (x, y, _) in candidates {
            if w.placementError(player, type, tileX: x, tileY: y) != nil { continue }
            if !hasClearance(w, x, y, size) { continue }
            return (x, y)
        }
        return nil
    }

    /// Keep a one-tile walkway around buildings and stay off resource nodes' working ring.
    func hasClearance(_ w: World, _ x: Int, _ y: Int, _ size: Int) -> Bool {
        for yy in (y - 1)...(y + size) {
            for xx in (x - 1)...(x + size) {
                guard w.map.inBounds(xx, yy) else { return false }
                let occ = w.occupant[w.map.idx(xx, yy)]
                if occ >= 0 { return false }
            }
        }
        for r in w.entities where r.isResource && r.alive {
            if r.x > Double(x - 2) && r.x < Double(x + size + 2) && r.y > Double(y - 2) && r.y < Double(y + size + 2) { return false }
        }
        return true
    }

    // MARK: Research

    func manageResearch(_ w: World, _ p: Player, _ buildings: [Entity], reserve: Cost) {
        let px = prefix(p)
        var prio: [String] = ["\(px)_tier2", "\(px)_econ1", "\(px)_tier3", "\(px)_gw1", "\(px)_ga1", "\(px)_econ2", "\(px)_mob", "\(px)_gw2", "\(px)_tower", "\(px)_ga2", "\(px)_aw1", "\(px)_gw3"]
        switch p.faction {
        case .humans: prio.insert(contentsOf: ["h_doctrine", "h_logistics"], at: 5); prio.append("h_composite")
        case .machines: prio.insert(contentsOf: ["m_mesh", "m_harden"], at: 5); prio.append("m_overclock")
        case .aliens:
            // Adaptations: choose based on strategy (they are mutually exclusive).
            let first = strategy == .aggressive || strategy == .territorial ? "a_sinew" : "a_chitin"
            let second = strategy == .tech ? "a_acid" : "a_gestation"
            prio.insert(contentsOf: [first, "a_roots"], at: 5); prio.append(second)
        }
        if strategy == .tech { prio.swapAt(1, 4) }
        if difficulty != .hard && clock(w) < (difficulty == .easy ? 900 : 400) { prio = Array(prio.prefix(3)) }
        let maxResearch = difficulty == .hard ? 2 : 1
        if p.researching.count >= maxResearch { return }
        let rich = p.res[0] > 400 && p.res[1] > 150
        if armyCount < min(10, Int(2 + clock(w) / 30)) && !rich { prio = prio.filter { $0.hasSuffix("tier2") || $0.hasSuffix("tier3") } }
        // Tier 2 waits for a minimal army in aggressive mode.
        for id in prio {
            guard let u = w.data.upgradeIndex[id] else { continue }
            if w.upgradeAvailability(player, u) != nil { continue }
            let g = w.data.upgrades[u]
            if id.hasSuffix("tier2") && clock(w) < (difficulty == .easy ? 480 : (strategy == .aggressive ? 260 : 150)) { continue }
            guard let b = buildings.first(where: { $0.complete && w.bdef($0).kind == g.researchedAt && $0.queue.isEmpty }) else { continue }
            if p.canAfford(g.cost) {
                w.commandResearch(b.id, upgrade: u)
                lastPlan = "Researching \(g.name)"
            }
            return  // research is prioritised; don't skip ahead to cheaper items
        }
    }

    // MARK: Production

    func manageProduction(_ w: World, _ p: Player, _ buildings: [Entity], workers: Int, army: [Entity], reserve: Cost) {
        let cap = w.data.rules.combat.unitCap
        let workerType = w.data.worker(p.faction)
        let owned = w.sites.filter { $0.owner == player }.count
        let wantWorkers = min(workerTarget + owned * 3, 48)
        for hq in buildings where hq.complete && w.bdef(hq).kind == .hq {
            if workers + hq.queue.count < wantWorkers && hq.queue.count < 1 && p.unitCount < cap - 4 {
                if canSpend(p, w.data.units[workerType].cost, reserve) { w.commandTrain(hq.id, unitType: workerType) }
            }
        }
        let comp = enemyComposition(w)
        for b in buildings where b.complete {
            let kind = w.bdef(b).kind
            guard [.infantry, .heavy, .air].contains(kind) else { continue }
            if b.queue.count >= maxQueue { continue }
            if let u = chooseUnit(w, p, kind, army: army, comp: comp) {
                let c = w.data.units[u].cost
                if canSpend(p, c, reserve) { w.commandTrain(b.id, unitType: u) }
            }
            // Rally production to a staging point.
            let st = stagingPoint(w)
            w.setRally(b.id, x: st.0, y: st.1)
        }
    }

    func canSpend(_ p: Player, _ c: Cost, _ reserve: Cost) -> Bool {
        guard p.canAfford(c) else { return false }
        // Only hold back resources the unit actually uses, and only when the saved-for building is nearly affordable.
        let have = [p.res[0], p.res[1], p.res[2]], r = [reserve.iron, reserve.gold, reserve.wood], cc = [c.iron, c.gold, c.wood]
        let close = (0..<3).allSatisfy { have[$0] * 10 >= r[$0] * 6 }
        if !close { return true }
        for k in 0..<3 where cc[k] > 0 && r[k] > 0 && have[k] - cc[k] < r[k] { return false }
        return true
    }

    func chooseUnit(_ w: World, _ p: Player, _ kind: BuildingKind, army: [Entity], comp: (air: Double, armored: Double, light: Double, total: Int)) -> Int? {
        var have: [String: Int] = [:]
        for u in army { have[w.udef(u).role, default: 0] += 1 }
        let n = Double(max(1, army.count))
        var weights: [(Int, Double)] = []
        for i in w.data.unitIDs(p.faction) {
            let d = w.data.units[i]
            guard d.producedAt == kind, w.unitAvailability(player, i) == nil else { continue }
            var wt: Double
            switch d.role {
            case "scout":
                let scouts = (have["scout"] ?? 0) + (w.entity(scoutID) != nil ? 1 : 0)
                wt = scouts < (enemyCloakSeen ? 2 : 1) && (p.stats.producedByType[i] ?? 0) < (enemyCloakSeen ? 5 : 2) ? 3 : 0
            case "infantry": wt = 3
            case "assault": wt = 2 + 2 * comp.light
            case "antiarmor": wt = 0.6 + 6 * comp.armored
            case "antiair": wt = 0.2 + 9 * comp.air
            case "support": wt = Double(have["support"] ?? 0) < n * 0.12 ? 1.2 : 0
            case "infiltration": wt = 0.4
            case "fast": wt = strategy == .aggressive ? 2 : 1
            case "heavy": wt = 2.2
            case "siege": wt = 0.4 + 0.5 * Double(enemyTowersSeen)
            case "denial": wt = 0.5
            case "interceptor": wt = 0.4 + 6 * comp.air
            case "bomber": wt = 1.2
            case "transport": wt = 0
            default: wt = 0.5
            }
            if strategy == .tech && ["heavy", "siege", "bomber"].contains(d.role) { wt *= 1.6 }
            if strategy == .aggressive && ["infantry", "assault", "fast"].contains(d.role) { wt *= 1.4 }
            if p.res[1] < d.cost.gold + 50 && d.cost.gold > 0 { wt *= 0.5 }
            // Spend floating gold on the units that need it.
            if p.res[1] > 300 && d.cost.gold > 0 { wt *= 1 + min(3, Double(p.res[1]) / 400) }
            if wt > 0 { weights.append((i, wt)) }
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var r = rng.unit() * total
        for (i, wt) in weights { r -= wt; if r <= 0 { return i } }
        return weights.last?.0
    }

    func stagingPoint(_ w: World) -> (Double, Double) {
        let (bx, by) = baseCenter(w)
        let (ex, ey) = enemyBase(w)
        // Prefer an owned site toward the enemy.
        let owned = w.sites.filter { $0.owner == player && $0.control >= 1 }
        if let s = owned.min(by: { dist2($0.x, $0.y, ex, ey) < dist2($1.x, $1.y, ex, ey) }),
           dist2(s.x, s.y, bx, by) < dist2(bx, by, ex, ey) * 0.5 {
            return (s.x - (s.x - bx) * 0.15, s.y - (s.y - by) * 0.15)
        }
        let dx = ex - bx, dy = ey - by
        let l = max(1, (dx * dx + dy * dy).squareRoot())
        return (bx + dx / l * 10, by + dy / l * 10)
    }

    // MARK: Sites

    func manageSites(_ w: World, _ p: Player) {
        let (ex, ey) = enemyBase(w)
        let (bx, by) = baseCenter(w)
        for (i, s) in w.sites.enumerated() where s.owner == player && s.control >= 1 && s.installation == .none {
            let cost = w.data.rules.territory.installCost
            guard p.res[0] > cost.iron + 250, p.res[1] > cost.gold + 60, p.res[2] > cost.wood + 100 else { return }
            let nearEnemy = dist2(s.x, s.y, ex, ey) < dist2(s.x, s.y, bx, by)
            let inst: Installation = nearEnemy ? .bulwark : (i == 0 ? .watchpost : .extractor)
            w.configureSite(i, player: player, installation: inst)
            return
        }
    }

    // MARK: Army

    func armyValue(_ w: World, _ units: [Entity]) -> Double {
        units.reduce(0) { $0 + w.udef($1).cost.value(w.data.rules.economy) * ($1.hp / max(1, $1.maxHp)) }
    }

    func manageArmy(_ w: World, _ p: Player, _ allArmy: [Entity], _ buildings: [Entity]) {
        guard !allArmy.isEmpty else { return }
        if difficulty == .hard { micro(w, allArmy); if w.tactics.raids { manageRaid(w, p, allArmy) } }
        // The raiding party runs its own errand; everything else is the field army.
        let army = allArmy.filter { !raidGroup.contains($0.id) }
        guard !army.isEmpty else { return }
        let value = armyValue(w, army)

        // 1. Defence: enemies near our structures take priority; an ally's base within reach counts too
        //    (the AI only sees what its team sees). Hard commanders answer calls from further away.
        var threat: Entity? = nil
        var threatCount = 0
        var threatValue = 0.0
        let (hx0, hy0) = baseCenter(w)
        let reach = difficulty == .hard ? 90.0 : 55.0
        let guarded = buildings + allyBuildings(w).filter { dist2($0.x, $0.y, hx0, hy0) < reach * reach }
        for e in w.entities where e.isUnit && e.onMap && !e.isMine && w.isEnemy(player, e.owner) && w.canSee(player, e) {
            if guarded.contains(where: { dist2($0.x, $0.y, e.x, e.y) < 13 * 13 }) {
                threatCount += 1
                let role = w.udef(e).role
                if role != "scout" && role != "worker" { threatValue += w.udef(e).cost.value(w.data.rules.economy) }
                if threat == nil || role != "scout" { threat = e }
            }
        }
        if threatValue > 0 { raided = true }
        // Outnumbered at home: endangered workers fall back under the HQ's guns, then resume.
        if let t = threat, threatValue > 0 {
            let local = army.filter { dist2($0.x, $0.y, t.x, t.y) < 15 * 15 }
            if armyValue(w, local) < threatValue * 0.8 {
                let (hx, hy) = baseCenter(w)
                for wk in w.units(of: player) where w.traits[wk.type].worker && wk.order != .build && dist2(wk.x, wk.y, t.x, t.y) < 6 * 6 && dist2(wk.x, wk.y, hx, hy) > 9 {
                    w.commandMove([wk.id], x: hx + Double(wk.id % 5) - 2, y: hy + Double(wk.id % 3) - 1, attack: false)
                }
            }
        }
        // Scouts and lone workers are handled by towers / nearby units, not the whole army.
        if threatValue < 120 { threat = nil }
        if let t = threat, threatCount >= 2 || !attacking {
            let defenders = army.filter { dist2($0.x, $0.y, t.x, t.y) < 40 * 40 || !attacking }
            let idle = defenders.filter { $0.order != .attackMove || dist2($0.ox, $0.oy, t.x, t.y) > 25 }
            if !idle.isEmpty { w.commandMove(idle.map { $0.id }, x: t.x, y: t.y, attack: true, formation: .defensive) }
            lastPlan = "Defending"
            if threatCount >= 4 { attacking = false }
            return
        }

        // 1b. Hard AI defends its territory: respond to owned sites being contested or decapped.
        if difficulty == .hard && !attacking {
            for s in w.sites where s.owner == player && (s.contested || s.control < 0.95) {
                let responders = army.filter { dist2($0.x, $0.y, s.x, s.y) < 45 * 45 && ($0.order == .idle || $0.order == .hold) }
                if responders.count >= 3 { w.commandMove(responders.map { $0.id }, x: s.x, y: s.y, attack: true, formation: .defensive); lastPlan = "Holding territory"; return }
            }
        }
        // 2. Attack timing (assemble at the staging point first, then advance in formation).
        let growth = 1 + clock(w) / 900          // thresholds grow so late attacks are bigger
        let threshold = attackThreshold * growth
        let capped = p.unitCount >= w.data.rules.combat.unitCap - 10
        let enemyEst = enemySeen.reduce(0.0) { $0 + Double($1.value) * w.data.units[$1.key].cost.value(w.data.rules.economy) * (w.data.units[$1.key].role == "worker" ? 0 : 1) }
        let confident = difficulty != .hard || value > enemyEst * 1.25
        // The attack force: the whole army, or (gentler AIs) only a capped wave while the rest stays home.
        var force = army
        if attacking && waveCap > 0 { force = army.filter { attackGroup.contains($0.id) }; if force.isEmpty { attacking = false; assembling = false; lastAttackEnd = clock(w) } }
        if !attacking && (value >= threshold && confident || capped) && clock(w) - lastAttackEnd > attackGap && clock(w) > firstAttack {
            attacking = true
            if waveCap > 0 {
                attackGroup = Set(army.sorted { $0.id < $1.id }.prefix(waveCap).map { $0.id })
                force = army.filter { attackGroup.contains($0.id) }
            }
            attackStartValue = armyValue(w, force)
            attackTarget = chooseAttackTarget(w)
            // Hard: a big enough force attacks on two fronts. Aircraft and about a third of the ground units
            // take a second objective far enough from the first that one defence cannot cover both.
            prongGroup = []; prongTarget = nil
            if difficulty == .hard, w.tactics.prongs, force.count >= 18, let main = attackTarget, let second = chooseProngTarget(w, avoiding: main) {
                let flyers = force.filter { $0.isAir }
                let ground = force.filter { !$0.isAir && w.udef($0).role != "siege" }.sorted { $0.id < $1.id }
                let take = max(0, Int(Double(force.count) * 0.35) - flyers.count)
                let picked = ground.enumerated().filter { $0.offset % 3 == 0 }.prefix(take).map { $0.element }
                prongGroup = Set((flyers + picked).map { $0.id })
                prongTarget = second
                prongsLaunched += 1
            }
            if difficulty == .hard {
                assembling = true
                assembleSince = clock(w)
                let st = stagingPoint(w)
                w.commandMove(force.map { $0.id }, x: st.0, y: st.1, attack: true, formation: doctrine(w, p))
                lastPlan = "Assembling"
                return
            }
            lastPlan = "Attacking"
        }
        if attacking && assembling {
            let st = stagingPoint(w)
            let near = force.filter { dist2($0.x, $0.y, st.0, st.1) < 10 * 10 }.count
            if Double(near) < Double(force.count) * 0.7 && clock(w) - assembleSince < 25 { return }
            assembling = false
            guard let t = attackTarget else { attacking = false; return }
            // Second prong leaves for its own objective.
            if let pt = prongTarget {
                let prong = force.filter { prongGroup.contains($0.id) }
                if !prong.isEmpty { w.commandMove(prong.map { $0.id }, x: pt.0, y: pt.1, attack: true, formation: .assault) }
            }
            let body = force.filter { !prongGroup.contains($0.id) }
            // Main body advances in doctrine formation; fast raiders swing around a flank.
            let fast = body.filter { w.udef($0).role == "fast" }
            let main = body.filter { w.udef($0).role != "fast" }.map { $0.id }
            w.commandMove(main, x: t.0, y: t.1, attack: true, formation: doctrine(w, p))
            if !fast.isEmpty {
                let dx = t.0 - st.0, dy = t.1 - st.1
                let l = max(1, (dx * dx + dy * dy).squareRoot())
                let side: Double = rng.chance(0.5) ? 1 : -1
                let fx = t.0 - dx / l * 4 + (-dy / l) * 9 * side, fy = t.1 - dy / l * 4 + (dx / l) * 9 * side
                w.commandMove(fast.map { $0.id }, x: clamp(fx, 2, Double(w.map.size) - 2), y: clamp(fy, 2, Double(w.map.size) - 2), attack: true, formation: .assault)
            }
            lastPlan = "Attacking"
            return
        }
        if attacking {
            if armyValue(w, force) < attackStartValue * (1 - retreatAt) && !capped {
                attacking = false
                assembling = false
                lastAttackEnd = clock(w)
                // Brood fall back into Bloom (owned site or base) to regenerate; others to the staging point.
                var st = stagingPoint(w)
                if p.faction == .aliens, let s = w.sites.filter({ $0.owner == player && $0.control >= 1 }).min(by: { dist2($0.x, $0.y, force[0].x, force[0].y) < dist2($1.x, $1.y, force[0].x, force[0].y) }) {
                    st = (s.x, s.y)
                }
                w.commandMove(force.map { $0.id }, x: st.0, y: st.1, attack: false, formation: .defensive)
                lastPlan = "Retreating"
                return
            }
            // Re-target when the current objective is gone.
            if let t = attackTarget, !targetStillValid(w, t) { attackTarget = chooseAttackTarget(w) }
            guard let t = attackTarget else { attacking = false; return }
            func straggling(_ u: Entity, _ goal: (Double, Double)) -> Bool {
                (u.order == .idle && u.target < 0) || (u.order == .attackMove && dist2(u.ox, u.oy, goal.0, goal.1) > 9) || u.order == .move
            }
            // The second prong keeps its own objective while it stands; once it falls the prong rejoins the main body.
            if let pt = prongTarget {
                if !targetStillValid(w, pt) { prongTarget = chooseProngTarget(w, avoiding: t); if prongTarget == nil { prongGroup = [] } }
                if let pt2 = prongTarget {
                    let lag = force.filter { prongGroup.contains($0.id) && straggling($0, pt2) }
                    if !lag.isEmpty { w.commandMove(lag.map { $0.id }, x: pt2.0, y: pt2.1, attack: true, formation: .assault) }
                }
            }
            let laggards = force.filter { !prongGroup.contains($0.id) && straggling($0, t) }
            if !laggards.isEmpty { w.commandMove(laggards.map { $0.id }, x: t.0, y: t.1, attack: true, formation: doctrine(w, p)) }
            return
        }

        // 3. Expansion: send squads to capture neutral or weakly held sites.
        let (bx, by) = baseCenter(w)
        let maxSquads = difficulty == .hard ? (strategy == .territorial ? 4 : 3) : (difficulty == .easy && clock(w) < 480 ? 0 : 1)
        siteSquads = siteSquads.filter { (k, v) in w.sites[k].owner != player && v.contains { w.entity($0) != nil } }
        let candidates = w.sites.enumerated().filter { $0.element.owner != player }
            .sorted { dist2($0.element.x, $0.element.y, bx, by) < dist2($1.element.x, $1.element.y, bx, by) }
        var assigned = Set(siteSquads.values.flatMap { $0 })
        let (ex0, ey0) = enemyBase(w)
        for (i, s) in candidates.prefix(maxSquads) where siteSquads[i] == nil {
            // Leave a site an ally is already taking to them.
            if s.capturer >= 0 && w.isAlly(player, s.capturer) { continue }
            if w.entities.contains(where: { $0.isUnit && $0.onMap && w.isAlly(player, $0.owner) && w.traits[$0.type].canCapture && dist2($0.x, $0.y, s.x, s.y) < 16 }) { continue }
            let ours = dist2(s.x, s.y, bx, by) < dist2(s.x, s.y, ex0, ey0)
            let squadSize = s.owner >= 0 ? 8 : (ours ? 2 : (difficulty == .hard ? 4 : 5))
            let fragile: Set<String> = ["siege", "support", "scout", "transport"]
            let free = army.filter { !assigned.contains($0.id) && w.traits[$0.type].canCapture && !fragile.contains(w.udef($0).role) && ($0.order == .idle || $0.order == .hold) }
            guard free.count >= squadSize else { break }
            let squad = free.sorted { dist2($0.x, $0.y, s.x, s.y) < dist2($1.x, $1.y, s.x, s.y) }.prefix(squadSize).map { $0.id }
            w.commandMove(squad, x: s.x, y: s.y, attack: true)
            siteSquads[i] = squad
            assigned.formUnion(squad)
            lastPlan = "Capturing site \(i)"
        }
        // Squads at their site hold on it until captured.
        for (i, squad) in siteSquads {
            let s = w.sites[i]
            for id in squad { if let u = w.entity(id), u.order == .idle, dist2(u.x, u.y, s.x, s.y) > 4 { w.commandMove([id], x: s.x, y: s.y, attack: true) } }
        }
        // Remaining idle army gathers at the staging point.
        let st = stagingPoint(w)
        let loose = army.filter { !assigned.contains($0.id) && $0.order == .idle && $0.target < 0 && dist2($0.x, $0.y, st.0, st.1) > 64 }
        if !loose.isEmpty { w.commandMove(loose.map { $0.id }, x: st.0, y: st.1, attack: true) }
    }

    /// Hard AI: focus fire on the weakest enemy in range.
    /// (Badly damaged units used to walk home alone to heal; on broken ground like Highlands they were picked off on
    /// the way and their damage left the fight. Ladder, 81 games: Hard vs Normal 59-22 with the retreat, 66-15 without.)
    func micro(_ w: World, _ army: [Entity]) {
        for u in army {
            guard let wpn = w.weapon(u), u.target >= 0 else { continue }
            var best: Entity? = nil
            var bestHP = Double.infinity
            for e in w.entities where e.isUnit && e.onMap && !e.isMine && w.isEnemy(player, e.owner) {
                guard abs(e.x - u.x) < wpn.range + 1.5, abs(e.y - u.y) < wpn.range + 1.5 else { continue }
                guard (e.isAir ? wpn.air : wpn.ground), w.edgeDist(u, e) <= wpn.range, w.canSee(player, e) else { continue }
                if e.hp < bestHP { bestHP = e.hp; best = e }
            }
            if let b = best, b.id != u.target { u.target = b.id }
        }
    }

    /// Faction doctrine for group orders. Concord adapts to what it has seen; Lattice holds lines; Brood assaults.
    func doctrine(_ w: World, _ p: Player) -> Formation {
        if strategy == .aggressive && p.faction != .humans { return .assault }
        var melee = 0, siege = 0, total = 0
        for (k, v) in enemySeen where v > 0 {
            let u = w.data.units[k]
            guard u.role != "worker" else { continue }
            total += v
            if let wp = u.weapon, wp.range <= 1.6, u.domain == .ground { melee += v }
            if u.role == "siege" { siege += v }
        }
        switch p.faction {
        case .humans:
            if total > 0 && Double(melee) / Double(total) > 0.4 { return .defensive }
            if total > 0 && Double(siege) / Double(total) > 0.15 { return .assault }
            return .balanced
        case .machines: return strategy == .tech ? .defensive : .balanced
        case .aliens: return .assault
        }
    }

    func targetStillValid(_ w: World, _ t: (Double, Double)) -> Bool {
        // Valid while enemy structures or an enemy-held site remain near the point.
        if w.sites.contains(where: { w.isEnemy(player, $0.owner) && dist2($0.x, $0.y, t.0, t.1) < 9 }) { return true }
        return w.entities.contains { $0.isBuilding && $0.alive && w.isEnemy(player, $0.owner) && dist2($0.x, $0.y, t.0, t.1) < 100 }
    }

    func chooseAttackTarget(_ w: World) -> (Double, Double)? {
        let (bx, by) = baseCenter(w)
        // Team play: join an ally's push when a few of their soldiers are already at an enemy structure.
        if w.players.contains(where: { w.isAlly(player, $0.index) && !$0.defeated }) {
            let allied = w.entities.filter { $0.isUnit && $0.onMap && !$0.isMine && w.isAlly(player, $0.owner) && !w.traits[$0.type].worker }
            let pushed = w.entities.filter { b in b.isBuilding && b.alive && w.isEnemy(player, b.owner) && allied.filter { dist2($0.x, $0.y, b.x, b.y) < 14 * 14 }.count >= 5 }
            if let b = pushed.min(by: { dist2($0.x, $0.y, bx, by) < dist2($1.x, $1.y, bx, by) }) { return (b.x, b.y) }
        }
        // Enemy sites first (cheap wins, and they deny dominance), then known buildings, then the enemy start.
        if let s = w.sites.filter({ w.isEnemy(player, $0.owner) }).min(by: { dist2($0.x, $0.y, bx, by) < dist2($1.x, $1.y, bx, by) }),
           strategy != .aggressive || rng.chance(0.5) {
            return (s.x, s.y)
        }
        let known = w.entities.filter { $0.isBuilding && $0.alive && w.isEnemy(player, $0.owner) && w.players[player].explored[w.tileIndex($0.x, $0.y)] }
        if let b = known.min(by: { dist2($0.x, $0.y, bx, by) < dist2($1.x, $1.y, bx, by) }) { return (b.x, b.y) }
        // Fall back to the nearest enemy building (the AI assumes a scout would have found it by now).
        if let b = w.entities.filter({ $0.isBuilding && $0.alive && w.isEnemy(player, $0.owner) })
            .min(by: { dist2($0.x, $0.y, bx, by) < dist2($1.x, $1.y, bx, by) }) { return (b.x, b.y) }
        return nil
    }

    /// A second objective for a two-pronged attack: an enemy site or known structure far enough from the main
    /// target that one defence cannot cover both, nearest to our base.
    func chooseProngTarget(_ w: World, avoiding main: (Double, Double)) -> (Double, Double)? {
        let (bx, by) = baseCenter(w)
        let apart = 18.0
        var options: [(Double, Double)] = w.sites.filter { w.isEnemy(player, $0.owner) }.map { ($0.x, $0.y) }
        options += w.entities.filter { $0.isBuilding && $0.alive && w.isEnemy(player, $0.owner) && w.players[player].explored[w.tileIndex($0.x, $0.y)] }.map { ($0.x, $0.y) }
        return options.filter { dist2($0.0, $0.1, main.0, main.1) > apart * apart }
            .min { dist2($0.0, $0.1, bx, by) < dist2($1.0, $1.1, bx, by) }
    }

    // MARK: Raids (Hard)

    /// Between attacks, three or four fast units slip out to kill enemy workers at a mineral line or an unguarded
    /// site, and run the moment a real defence shows up. Cheap pressure that keeps the enemy's army at home.
    func manageRaid(_ w: World, _ p: Player, _ army: [Entity]) {
        raidGroup = raidGroup.filter { w.entity($0) != nil }
        let t = clock(w)
        if raidGroup.isEmpty {
            guard !attacking, t > 300, t - lastRaidEnd > 75 else { return }
            let fast = army.filter { w.udef($0).role == "fast" && !$0.isAir && [.idle, .hold, .attackMove].contains($0.order) }
            guard fast.count >= 3, let target = chooseRaidTarget(w, not: nil) else { return }
            let party = Array(fast.prefix(4))
            raidGroup = Set(party.map { $0.id })
            raidTarget = target
            raidStart = t
            raidStartValue = armyValue(w, party)
            raidsLaunched += 1
            w.commandMove(party.map { $0.id }, x: target.0, y: target.1, attack: false, formation: .assault)
            lastPlan = "Raiding"
            return
        }
        let raiders = army.filter { raidGroup.contains($0.id) }
        guard let target = raidTarget, !raiders.isEmpty else { endRaid(w, raiders); return }
        // A defence worth more than half the party, within striking distance, ends the raid.
        var defence = 0.0
        for e in w.entities where e.isUnit && e.onMap && !e.isMine && w.isEnemy(player, e.owner) && w.udef(e).weapon != nil && w.udef(e).role != "worker" && w.canSee(player, e) {
            if raiders.contains(where: { dist2($0.x, $0.y, e.x, e.y) < 9 * 9 }) { defence += w.udef(e).cost.value(w.data.rules.economy) }
        }
        let value = armyValue(w, raiders)
        if value < raidStartValue * 0.55 || defence > value * 0.6 || t - raidStart > 100 { endRaid(w, raiders); return }
        var busy = false
        for r in raiders {
            if let wk = nearestEnemyWorker(w, r, within: 10) {
                busy = true
                if r.target != wk.id { w.commandAttack([r.id], target: wk.id) }
            } else if r.order == .idle || (r.order == .move && dist2(r.ox, r.oy, target.0, target.1) > 4) {
                w.commandMove([r.id], x: target.0, y: target.1, attack: false)
            }
        }
        // Arrived and nothing to hunt: try the next spot, or go home.
        if !busy && t - raidStart > 20 && raiders.allSatisfy({ dist2($0.x, $0.y, target.0, target.1) < 36 }) {
            if let next = chooseRaidTarget(w, not: target) { raidTarget = next; raidStart = t } else { endRaid(w, raiders) }
        }
    }

    func endRaid(_ w: World, _ raiders: [Entity]) {
        let st = stagingPoint(w)
        if !raiders.isEmpty { w.commandMove(raiders.map { $0.id }, x: st.0, y: st.1, attack: false, formation: .defensive) }
        raidGroup = []; raidTarget = nil
        lastRaidEnd = clock(w)
    }

    /// Somewhere enemy workers are likely and soldiers are not: an enemy site with no visible defence, or an
    /// enemy mineral line (their iron faces away from the map centre, like ours).
    func chooseRaidTarget(_ w: World, not skip: (Double, Double)?) -> (Double, Double)? {
        let (bx, by) = baseCenter(w)
        let mid = Double(w.map.size) / 2
        var options: [(Double, Double)] = []
        for s in w.sites where w.isEnemy(player, s.owner) {
            let guardedSite = w.entities.contains { $0.isUnit && $0.onMap && !$0.isMine && w.isEnemy(player, $0.owner) && w.udef($0).weapon != nil && w.udef($0).role != "worker" && w.canSee(player, $0) && dist2($0.x, $0.y, s.x, s.y) < 64 }
            if !guardedSite { options.append((s.x, s.y)) }
        }
        for e in w.players where w.isEnemy(player, e.index) && !e.defeated {
            let s = w.map.starts[e.index % w.map.starts.count]
            let hx = Double(s.x) + 2, hy = Double(s.y) + 2
            let dx = hx - mid, dy = hy - mid, l = max(1, (dx * dx + dy * dy).squareRoot())
            options.append((hx + dx / l * 8, hy + dy / l * 8))
        }
        if let sk = skip { options.removeAll { dist2($0.0, $0.1, sk.0, sk.1) < 36 } }
        return options.min { dist2($0.0, $0.1, bx, by) < dist2($1.0, $1.1, bx, by) }
    }

    func nearestEnemyWorker(_ w: World, _ r: Entity, within d: Double) -> Entity? {
        var best: Entity? = nil
        var bd = d * d
        for e in w.entities where e.isUnit && e.onMap && !e.isMine && w.isEnemy(player, e.owner) && w.traits[e.type].worker && w.canSee(player, e) {
            let dd = dist2(e.x, e.y, r.x, r.y)
            if dd < bd { bd = dd; best = e }
        }
        return best
    }

    func manageScout(_ w: World, _ units: [Entity]) {
        if w.entity(scoutID) == nil {
            scoutID = -1
            if let s = units.first(where: { w.udef($0).role == "scout" }) { scoutID = s.id }
        }
        guard let s = w.entity(scoutID) else { return }
        if s.order == .idle {
            // Tour sites then the enemy base.
            let pts = w.sites.map { ($0.x, $0.y) } + [enemyBase(w)]
            let p = pts[rng.int(pts.count)]
            w.commandMove([s.id], x: p.0, y: p.1, attack: false)
        }
    }

    func manageModes(_ w: World, _ army: [Entity]) {
        let comp = enemyComposition(w)
        for u in army where w.traits[u.type].modes > 0 {
            let p = w.udef(u).params ?? [:]
            if p["altDamage"] != nil {
                // Skyguard: ground mode if the enemy has no air.
                let wantGround = comp.air < 0.05 && comp.total > 6
                if (u.mode == 1) != wantGround { w.commandToggleMode([u.id]) }
            }
        }
    }
}
