import Foundation
import MeridianCore

// Headless harness: AI-vs-AI matches, tournaments, equal-cost combat simulations and stress tests.
// Usage: meridian-sim <match|tournament|combat|comps|stress|validate> [options]

var args = Array(CommandLine.arguments.dropFirst())
let cmd = args.isEmpty ? "match" : args.removeFirst()
func opt(_ name: String, _ def: String) -> String {
    if let i = args.firstIndex(of: "--" + name), i + 1 < args.count { return args[i + 1] }
    return def
}
func flag(_ name: String) -> Bool { args.contains("--" + name) }

let data = GameData.shared
func fmt(_ v: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", v) }
func mmss(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

// MARK: - Match

struct MatchResult {
    var winner: Int
    var reason: String
    var time: Double
    var factions: [Faction]
    var peak: [Int]
    var ms: Double
}

func runMatch(_ f0: Faction, _ f1: Faction, layout: MapLayout, seed: UInt64, diff: [Difficulty], strat: [AIStrategy],
              swap: Bool, limit: Double, verbose: Bool) -> MatchResult {
    runMatch(factions: [f0, f1], teams: nil, victory: VictoryMode(rawValue: opt("victory", "dominance")) ?? .dominance,
             layout: layout, seed: seed, diff: diff, strat: strat, swap: swap, limit: limit, verbose: verbose)
}

/// Any number of commanders (2–4), optionally in teams.
func runMatch(factions: [Faction], teams: [Int]?, victory: VictoryMode, layout: MapLayout, seed: UInt64, diff: [Difficulty], strat: [AIStrategy],
              swap: Bool, limit: Double, verbose: Bool) -> MatchResult {
    let quick = flag("quick")
    let cfg = MatchConfig(factions: factions, teams: teams, victory: victory, layout: layout, seed: seed,
                          mapSize: MatchConfig.mapSize(players: factions.count, quick: quick), swapStarts: swap)
    let ai = factions.indices.map { (player: $0, difficulty: diff[$0 % diff.count], strategy: strat[$0 % strat.count]) }
    let m = Match(config: cfg, ai: ai, data: quick ? .quick : .shared)
    m.world.tactics = TacticsFlags(disabling: opt("disable", "").split(separator: ",").map(String.init))
    m.timeLimit = limit
    m.world.collectEvents = false
    let t0 = Date()
    var nextReport = 60.0
    while m.world.winner == nil {
        m.step()
        if verbose && m.world.time >= nextReport {
            nextReport += 60
            var line = "[\(mmss(m.world.time))]"
            for p in m.world.players {
                let u = m.world.units(of: p.index)
                let workers = u.filter { m.world.traits[$0.type].worker }.count
                let sites = m.world.sites.filter { $0.owner == p.index }.count
                let blds = m.world.buildings(of: p.index).count
                let fac = m.world.buildings(of: p.index).filter { $0.complete && [.infantry, .heavy, .air].contains(m.world.bdef($0).kind) }
                let fq = "f\(fac.count)q\(fac.reduce(0) { $0 + $1.queue.count })"
                line += " | \(p.faction.rawValue.prefix(3)) \(fq) I\(p.res[0]) G\(p.res[1]) W\(p.res[2]) wk\(workers) army\(u.count - workers) b\(blds) s\(sites) up\(p.completedUpgrades.count) k\(p.stats.kills) \(m.ais[p.index].lastPlan)"
            }
            print(line)
        }
    }
    let ms = Date().timeIntervalSince(t0) * 1000
    if verbose {
        for p in m.world.players {
            let s = p.stats
            let prod = s.producedByType.sorted { $0.value > $1.value }.map { "\(data.units[$0.key].name) \($0.value)/\(s.lostByType[$0.key] ?? 0)" }.joined(separator: ", ")
            print("P\(p.index) \(p.faction.rawValue): valueKilled \(Int(s.valueKilled)) valueLost \(Int(s.valueLost)) gathered \(s.gathered) territory \(s.territoryIncome.map { Int($0) })\n   produced/lost: \(prod)")
        }
    }
    return MatchResult(winner: m.world.winner!, reason: m.world.victoryReason, time: m.world.time,
                       factions: factions, peak: m.world.players.map { $0.stats.peakUnits }, ms: ms)
}

func parseFaction(_ s: String) -> Faction { Faction(rawValue: s) ?? .humans }
func parseDiff(_ s: String) -> Difficulty { Difficulty(rawValue: s) ?? .normal }

switch cmd {
case "validate":
    let problems = data.validate()
    print(problems.isEmpty ? "Data OK: \(data.units.count) units, \(data.buildings.count) buildings, \(data.upgrades.count) upgrades" : problems.joined(separator: "\n"))

case "match":
    // --p0..--p3 factions (players beyond p1 are optional), --teams 0,0,1,1, --victory annihilation|dominance.
    var factions: [Faction] = [parseFaction(opt("p0", "humans")), parseFaction(opt("p1", "machines"))]
    for k in 2..<MatchConfig.maxPlayers { let f = opt("p\(k)", ""); if !f.isEmpty { factions.append(parseFaction(f)) } }
    let teams = opt("teams", "").split(separator: ",").compactMap { Int($0) }
    let r = runMatch(factions: factions, teams: teams.count == factions.count ? teams : nil,
                     victory: VictoryMode(rawValue: opt("victory", factions.count > 2 ? "annihilation" : "dominance")) ?? .annihilation,
                     layout: MapLayout(rawValue: opt("map", "crossroads")) ?? .crossroads, seed: UInt64(opt("seed", "1"))!,
                     diff: factions.indices.map { parseDiff(opt("d\($0)", opt("diff", "normal"))) },
                     strat: factions.indices.map { AIStrategy(rawValue: opt("s\($0)", "balanced")) ?? .balanced },
                     swap: flag("swap"), limit: Double(opt("limit", "2700"))!, verbose: true)
    let name = r.winner >= 0 ? r.factions[r.winner].rawValue : "none"
    print("Winner: P\(r.winner) \(name) — \(r.reason) at \(mmss(r.time)); peak units \(r.peak); wall \(fmt(r.ms / 1000, 1))s")

case "tournament":
    // Every ordered faction pair on every playable map, several seeds, both start positions.
    let seeds = Int(opt("seeds", "2"))!
    let limit = Double(opt("limit", "2700"))!
    let diff = parseDiff(opt("diff", "normal"))
    let stratMix = flag("strategies")
    var wins: [Faction: Int] = [:], games: [Faction: Int] = [:]
    var pairWins: [String: (Int, Int)] = [:]
    var reasons: [String: Int] = [:]
    var durations: [Double] = []
    var n = 0
    let strats = AIStrategy.allCases
    for (i, a) in Faction.allCases.enumerated() {
        for b in Faction.allCases[(i + 1)...] {
            let pair = opt("pair", "")
            if !pair.isEmpty && !(pair.contains(a.rawValue) && pair.contains(b.rawValue)) { continue }
            for layout in MapLayout.playable {
                for s in 0..<seeds {
                    for swap in [false, true] {
                        let st0 = stratMix ? strats[(s + (swap ? 1 : 0)) % strats.count] : .balanced
                        let st1 = stratMix ? strats[(s + 2) % strats.count] : .balanced
                        let r = runMatch(a, b, layout: layout, seed: UInt64(100 + s * 7), diff: [diff, diff], strat: [st0, st1],
                                         swap: swap, limit: limit, verbose: false)
                        n += 1
                        games[a, default: 0] += 1; games[b, default: 0] += 1
                        let key = "\(a.rawValue) vs \(b.rawValue)"
                        var pw = pairWins[key] ?? (0, 0)
                        if r.winner == 0 { wins[a, default: 0] += 1; pw.0 += 1 } else if r.winner == 1 { wins[b, default: 0] += 1; pw.1 += 1 }
                        pairWins[key] = pw
                        reasons[r.reason, default: 0] += 1
                        durations.append(r.time)
                        let wn = r.winner >= 0 ? r.factions[r.winner].rawValue : "-"
                        print("#\(n) \(a.rawValue)(\(st0.rawValue)) v \(b.rawValue)(\(st1.rawValue)) \(layout.rawValue) seed\(s) swap=\(swap): \(wn) by \(r.reason) at \(mmss(r.time)) peak \(r.peak) [\(fmt(r.ms / 1000))s]")
                        fflush(stdout)
                    }
                }
            }
        }
    }
    print("\n=== Tournament summary (\(n) games, difficulty \(diff.rawValue)) ===")
    for f in Faction.allCases {
        let g = games[f] ?? 0, wv = wins[f] ?? 0
        print("\(f.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(wv)/\(g) = \(fmt(100 * Double(wv) / Double(max(1, g))))%")
    }
    for (k, v) in pairWins.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v.0)-\(v.1)") }
    print("Victory types: \(reasons)")
    let sorted = durations.sorted()
    print("Duration: median \(mmss(sorted[sorted.count / 2])), min \(mmss(sorted.first!)), max \(mmss(sorted.last!))")

case "ladder":
    // Difficulty check: player 0 at --d0 against player 1 at --d1, every faction pairing (mirrors included),
    // every playable map, both start positions.
    let seeds = Int(opt("seeds", "1"))!
    let limit = Double(opt("limit", "2700"))!
    let d0 = parseDiff(opt("d0", "easy")), d1 = parseDiff(opt("d1", "normal"))
    var w0 = 0, w1 = 0, draws = 0, n = 0
    var durations: [Double] = []
    var reasons: [String: Int] = [:]
    for a in Faction.allCases {
        for b in Faction.allCases {
            for layout in MapLayout.playable {
                for s in 0..<seeds {
                    let swap = (n % 2) == 1
                    let r = runMatch(a, b, layout: layout, seed: UInt64(300 + s * 11), diff: [d0, d1], strat: [.balanced, .balanced], swap: swap, limit: limit, verbose: false)
                    n += 1
                    if r.winner == 0 { w0 += 1 } else if r.winner == 1 { w1 += 1 } else { draws += 1 }
                    durations.append(r.time); reasons[r.reason, default: 0] += 1
                    print("#\(n) \(a.rawValue)[\(d0.rawValue)] v \(b.rawValue)[\(d1.rawValue)] \(layout.rawValue): winner \(r.winner) by \(r.reason) at \(mmss(r.time))")
                    fflush(stdout)
                }
            }
        }
    }
    let sorted = durations.sorted()
    print("\n=== Ladder \(d0.rawValue) vs \(d1.rawValue): \(n) games ===")
    print("\(d0.rawValue) wins \(w0), \(d1.rawValue) wins \(w1), unresolved \(draws)")
    print("Victory types: \(reasons)")
    print("Duration: median \(mmss(sorted[sorted.count / 2])), min \(mmss(sorted.first!)), max \(mmss(sorted.last!))")

case "combat":
    // Equal-cost 1-unit-type vs 1-unit-type duels on an open arena, every cross-faction pairing.
    let budget = Double(opt("budget", "1500"))!
    let filterRole = opt("role", "")
    let e = data.rules.economy
    func duel(_ a: Int, _ b: Int, seed: UInt64) -> (Int, Double) {
        let w = World(config: MatchConfig(factions: [data.units[a].faction, data.units[b].faction], layout: .arena, seed: seed, mapSize: 64))
        w.sandbox = true; w.collectEvents = false
        w.clearAll()
        for p in 0..<2 { w.unlockAll(p) }
        let na = max(1, Int(budget / data.units[a].cost.value(e))), nb = max(1, Int(budget / data.units[b].cost.value(e)))
        var ia: [Int] = [], ib: [Int] = []
        for k in 0..<na { ia.append(w.spawnUnit(a, owner: 0, x: 20 + Double(k % 6) * 0.9, y: 28 + Double(k / 6) * 0.9).id) }
        for k in 0..<nb { ib.append(w.spawnUnit(b, owner: 1, x: 44 - Double(k % 6) * 0.9, y: 28 + Double(k / 6) * 0.9).id) }
        w.commandMove(ia, x: 44, y: 30, attack: true)
        w.commandMove(ib, x: 20, y: 30, attack: true)
        let va0 = Double(na) * data.units[a].cost.value(e), vb0 = Double(nb) * data.units[b].cost.value(e)
        for _ in 0..<(20 * 120) {
            w.step()
            let la = ia.filter { w.entity($0) != nil }.count, lb = ib.filter { w.entity($0) != nil }.count
            if la == 0 || lb == 0 { break }
            // Re-issue attack-move so idle survivors keep hunting.
            if w.tick % 100 == 0 {
                w.commandMove(ia.filter { w.entity($0)?.order == .idle }, x: 32, y: 30, attack: true)
                w.commandMove(ib.filter { w.entity($0)?.order == .idle }, x: 32, y: 30, attack: true)
            }
        }
        func remaining(_ ids: [Int]) -> Double { ids.compactMap { w.entity($0) }.reduce(0) { $0 + data.units[$1.type].cost.value(e) * $1.hp / $1.maxHp } }
        let ra = remaining(ia) / va0, rb = remaining(ib) / vb0
        if ra > rb + 0.05 { return (0, ra) }
        if rb > ra + 0.05 { return (1, rb) }
        return (-1, 0)
    }
    // Role-for-role comparison across factions.
    let roles = ["infantry", "assault", "antiarmor", "antiair", "fast", "heavy", "siege", "interceptor", "bomber", "scout", "infiltration", "denial"]
    print("Equal-cost (\(Int(budget)) value) mirror-role duels. Score = wins over the 2 other factions' same-role units.")
    for role in roles where filterRole.isEmpty || role == filterRole {
        let ids = Faction.allCases.compactMap { f in data.units.indices.first { data.units[$0].faction == f && data.units[$0].role == role } }
        var line = role.padding(toLength: 12, withPad: " ", startingAt: 0)
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                let (wn, rem) = duel(a, b, seed: 5)
                let res = wn == 0 ? "\(data.units[a].name) (\(fmt(rem * 100, 0))%)" : wn == 1 ? "\(data.units[b].name) (\(fmt(rem * 100, 0))%)" : "draw"
                line += " | \(data.units[a].name) v \(data.units[b].name): \(res)"
            }
        }
        print(line)
    }
    if flag("counters") {
        // Counter matrix: does each unit beat what its description says it beats?
        print("\nCounter checks (equal cost):")
        let checks: [(String, String)] = [
            ("h_lancer", "m_bulwark"), ("h_lancer", "a_colossus"), ("m_piercer", "h_bastion"), ("a_spinecaster", "h_bastion"),
            ("h_skyguard", "a_blightwing"), ("m_flak", "h_harrier"), ("a_needleback", "m_quake"), ("h_kestrel", "a_sporewing"),
            ("m_arc", "a_skitter"), ("m_shockframe", "a_mantis"), ("a_mantis", "h_mortar"), ("h_breacher", "a_mantis"),
            ("a_skitter", "m_coil"), ("h_buggy", "a_weaver"), ("m_runner", "h_engineer"), ("a_ravager", "h_bastion"),
            ("h_bastion", "a_ravager"), ("m_bulwark", "a_wisp"), ("a_wisp", "m_quake"), ("m_vector", "h_harrier"),
            ("h_ranger", "a_mantis"), ("a_mantis", "h_ranger"), ("m_arc", "h_ranger"), ("a_colossus", "h_ranger"),
        ]
        for (a, b) in checks {
            let ia = data.unitIndex[a]!, ib = data.unitIndex[b]!
            let (wn, rem) = duel(ia, ib, seed: 9)
            let res = wn == 0 ? "WIN (\(fmt(rem * 100, 0))% left)" : wn == 1 ? "loss" : "draw"
            print("  \(data.units[ia].name) vs \(data.units[ib].name): \(res)")
        }
    }

case "comps":
    // Mixed-army equal-cost battles: representative tier-2/3 compositions per faction.
    let budget = Double(opt("budget", "6000"))!
    let comps: [Faction: [(String, Double)]] = [
        .humans: [("h_ranger", 0.3), ("h_breacher", 0.15), ("h_lancer", 0.15), ("h_skyguard", 0.08), ("h_medic", 0.07), ("h_bastion", 0.15), ("h_mortar", 0.1)],
        .machines: [("m_arc", 0.3), ("m_shockframe", 0.15), ("m_piercer", 0.15), ("m_flak", 0.08), ("m_repair", 0.07), ("m_bulwark", 0.15), ("m_coil", 0.1)],
        .aliens: [("a_mantis", 0.25), ("a_ravager", 0.15), ("a_spinecaster", 0.15), ("a_needleback", 0.08), ("a_lifebinder", 0.07), ("a_colossus", 0.15), ("a_skitter", 0.15)],
    ]
    let e = data.rules.economy
    var tally: [String: (Int, Int)] = [:]
    for (i, fa) in Faction.allCases.enumerated() {
        for fb in Faction.allCases[(i + 1)...] {
            for seed in 1...UInt64(opt("seeds", "6"))! {
                let w = World(config: MatchConfig(factions: [fa, fb], layout: .arena, seed: seed, mapSize: 64))
                w.sandbox = true; w.collectEvents = false
                w.clearAll(); w.unlockAll(0); w.unlockAll(1)
                var r = RNG(seed: seed)
                var groups: [[Int]] = [[], []]
                for (side, f) in [fa, fb].enumerated() {
                    var k = 0
                    for (id, frac) in comps[f]! {
                        let t = data.unitIndex[id]!
                        let n = max(1, Int(budget * frac / data.units[t].cost.value(e)))
                        for _ in 0..<n {
                            let x = side == 0 ? 14 + r.range(0, 7) : 50 - r.range(0, 7)
                            let y = 22 + r.range(0, 20)
                            groups[side].append(w.spawnUnit(t, owner: side, x: x, y: y).id); k += 1
                        }
                    }
                }
                w.commandMove(groups[0], x: 46, y: 32, attack: true)
                w.commandMove(groups[1], x: 18, y: 32, attack: true)
                for _ in 0..<(20 * 180) {
                    w.step()
                    if groups[0].allSatisfy({ w.entity($0) == nil }) || groups[1].allSatisfy({ w.entity($0) == nil }) { break }
                    if w.tick % 100 == 0 {
                        w.commandMove(groups[0].filter { w.entity($0)?.order == .idle }, x: 32, y: 32, attack: true)
                        w.commandMove(groups[1].filter { w.entity($0)?.order == .idle }, x: 32, y: 32, attack: true)
                    }
                }
                let la = groups[0].compactMap { w.entity($0) }.reduce(0.0) { $0 + data.units[$1.type].cost.value(e) * $1.hp / $1.maxHp }
                let lb = groups[1].compactMap { w.entity($0) }.reduce(0.0) { $0 + data.units[$1.type].cost.value(e) * $1.hp / $1.maxHp }
                let key = "\(fa.rawValue) vs \(fb.rawValue)"
                var t = tally[key] ?? (0, 0)
                if la > lb { t.0 += 1 } else { t.1 += 1 }
                tally[key] = t
                print("\(key) seed \(seed): remaining value \(Int(la)) vs \(Int(lb))  (units \(groups[0].count) v \(groups[1].count))")
            }
        }
    }
    for (k, v) in tally.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v.0)-\(v.1)") }

case "stress":
    // N units per player in a sustained battle with projectiles, pathing and structures.
    let perPlayer = Int(opt("units", "200"))!
    let seconds = Double(opt("seconds", "60"))!
    let f0 = parseFaction(opt("p0", "humans")), f1 = parseFaction(opt("p1", "aliens"))
    let w = World(config: MatchConfig(factions: [f0, f1], layout: .crossroads, seed: 4))
    w.sandbox = true
    w.unlockAll(0); w.unlockAll(1)
    var r = RNG(seed: 99)
    let mid = Double(w.map.size) / 2
    for p in 0..<2 {
        let f = w.players[p].faction
        let pool = data.unitIDs(f).filter { data.units[$0].role != "worker" && data.units[$0].role != "transport" }
        var spawned = w.units(of: p).count
        let cx = p == 0 ? mid - 18 : mid + 18
        while spawned < perPlayer {
            let t = pool[r.int(pool.count)]
            var x = cx + r.range(-9, 9), y = mid + r.range(-9, 9)
            if w.nav.isBlocked(Int(x), Int(y)) { let o = w.nav.nearestOpen(Int(x), Int(y)); x = Double(o.0) + 0.5; y = Double(o.1) + 0.5 }
            w.spawnUnit(t, owner: p, x: x, y: y); spawned += 1
        }
        // Defensive structures in the battle zone too.
        let tower = data.building(f, .tower)
        for k in 0..<3 {
            let tx = Int(cx) + (p == 0 ? -10 : 8), ty = Int(mid) - 6 + k * 5
            if w.placementError(p, tower, tileX: tx, tileY: ty) == nil || true {
                if !(tx..<(tx + 2)).contains(where: { x in (ty..<(ty + 2)).contains { w.nav.isBlocked(x, $0) } }) {
                    w.spawnBuilding(tower, owner: p, tileX: tx, tileY: ty, complete: true)
                }
            }
        }
    }
    for p in 0..<2 { w.commandMove(w.units(of: p).filter { !w.traits[$0.type].worker }.map { $0.id }, x: p == 0 ? mid + 25 : mid - 25, y: mid, attack: true) }
    print("Spawned \(w.units(of: 0).count) vs \(w.units(of: 1).count) units (incl. starting workers)")
    var tickTimes: [Double] = []
    var heavy: [Double] = []
    var maxProj = 0
    let ticks = Int(seconds / w.dt)
    for k in 0..<ticks {
        let t0 = DispatchTime.now().uptimeNanoseconds
        w.step()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        tickTimes.append(ms)
        if w.units(of: 0).count > perPlayer / 2 && w.units(of: 1).count > perPlayer / 2 { heavy.append(ms) }
        maxProj = max(maxProj, w.projectiles.count)
        w.events.removeAll(keepingCapacity: true)
        if k % 200 == 0 {
            for p in 0..<2 { w.commandMove(w.units(of: p).filter { $0.order == .idle && !w.traits[$0.type].worker }.map { $0.id }, x: p == 0 ? mid + 25 : mid - 25, y: mid, attack: true) }
        }
    }
    let s = tickTimes.sorted()
    let avg = tickTimes.reduce(0, +) / Double(tickTimes.count)
    print("Sim tick (20 Hz) over \(ticks) ticks: avg \(fmt(avg, 2)) ms, p50 \(fmt(s[s.count / 2], 2)), p95 \(fmt(s[Int(Double(s.count) * 0.95)], 2)), max \(fmt(s.last!, 2)) ms")
    if !heavy.isEmpty {
        let hs = heavy.sorted()
        print("While both sides > 50% strength (\(heavy.count) ticks): avg \(fmt(heavy.reduce(0, +) / Double(heavy.count), 2)) ms, p95 \(fmt(hs[Int(Double(hs.count) * 0.95)], 2)), max \(fmt(hs.last!, 2)) ms")
    }
    print("Peak projectiles \(maxProj); survivors \(w.units(of: 0).count) vs \(w.units(of: 1).count); flow fields built \(w.nav.totalFieldsBuilt)")

case "tactics":
    // Reproducible tactical scenarios with movement/combat quality metrics.
    let only = opt("only", "")
    let formation = Formation(rawValue: opt("formation", "balanced")) ?? .balanced
    var rows: [String] = []
    rows.append("| Scenario | Result | Time | Overlap % | Peak density | Mean density | Weapon uptime % | Stuck unit·s | Arrived % (t90) | Response t90 | Special | Sim ms avg/max |")
    rows.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for sc in TacticalScenario.allCases where only.isEmpty || only.split(separator: ",").contains(Substring(sc.rawValue)) {
        let w = World(config: MatchConfig(factions: sc.factions, layout: .arena, seed: 21, mapSize: 112))
        w.collectEvents = false
        w.tactics = TacticsFlags(disabling: opt("disable", "").split(separator: ",").map(String.init))
        let setup = sc.setup(w, formation: formation)
        let e = data.rules.economy
        let all = setup.groups.flatMap { $0.ids }
        let slotOf = Dictionary(uniqueKeysWithValues: all.compactMap { id in w.entity(id).map { (id, ($0.formationDX, $0.formationDY)) } })
        let movers = setup.groups.filter { !(sc == .airstrike && $0.owner == 1) }.flatMap { $0.ids }
        let start = Dictionary(uniqueKeysWithValues: all.compactMap { id in w.entity(id).map { (id, ($0.x, $0.y)) } })
        let initialValue = (0..<2).map { p in Double(w.units(of: p).reduce(0.0) { $0 + data.units[$1.type].cost.value(e) }) }
        let siegeIDs = all.filter { w.entity($0).map { data.units[$0.type].role == "siege" } ?? false }
        let airIDs = setup.groups.first.map { g in g.ids.filter { w.entity($0)?.isAir ?? false } } ?? []
        var overlapSum = 0.0, densSum = 0.0, samples = 0, peak = 0
        var upIn = 0, upAll = 0
        var stuck = 0.0
        var lastPos: [Int: (Double, Double)] = start
        var responseT: Double? = nil, arriveT: Double? = nil
        var contact = 0, contactAll = 0
        var simTimes: [Double] = []
        var roleStats: [String: (Int, Int)] = [:]
        var intrSum = 0.0
        var linkedShare = (0, 0)
        var ticks = 0
        // Arrived = settled at its own formation slot (or stopped by crowding right next to it).
        func arrivedAt(_ u: Entity, _ goal: (Double, Double)) -> Bool {
            let off = slotOf[u.id] ?? (0, 0)
            let slot = (goal.0 + off.0, goal.1 + off.1)
            let d2 = dist2(u.x, u.y, slot.0, slot.1)
            return d2 < 1.5 * 1.5 || (u.order == .idle && d2 < 4 * 4 && dist2(u.x, u.y, goal.0, goal.1) < 12 * 12)
        }
        while w.time < sc.timeLimit {
            let t0 = DispatchTime.now().uptimeNanoseconds
            w.step()
            simTimes.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            ticks += 1
            if responseT == nil && ticks % 2 == 0 {
                let moved = movers.filter { id in guard let u = w.entity(id), let p0 = start[id] else { return true }; return dist2(u.x, u.y, p0.0, p0.1) > 0.09 }.count
                if Double(moved) >= Double(movers.count) * 0.9 { responseT = w.time }
            }
            if ticks % 10 == 0 {
                let s = w.tacticalSample()
                let ground = max(1, w.entities.filter { $0.isUnit && $0.onMap && !$0.isAir && !$0.isMine }.count)
                overlapSum += Double(s.deepOverlaps) / Double(ground); densSum += s.meanDensity; samples += 1
                intrSum += Double(s.enemyIntrusions) / Double(ground)
                peak = max(peak, s.maxDensity)
                if s.inRange + s.outOfRange > 0 { upIn += s.inRange; upAll += s.inRange + s.outOfRange }
                if flag("debug") {
                    for u in w.entities where u.isUnit && u.onMap && !u.isMine && w.players[u.owner].faction == .machines { linkedShare.1 += 1; if u.linked { linkedShare.0 += 1 } }
                    for u in w.entities where u.isUnit && u.onMap && !u.isMine {
                        guard let wp = w.weapon(u), let t = w.entity(u.target), t.onMap else { continue }
                        let role = data.units[u.type].role
                        var r = roleStats[role] ?? (0, 0)
                        r.1 += 1; if w.edgeDist(u, t) > wp.range { r.0 += 1 }
                        roleStats[role] = r
                    }
                }
                if sc == .kite {
                    for r in setup.groups[0].ids { guard let u = w.entity(r) else { continue }
                        contactAll += 1
                        var near = false
                        for m in setup.groups[1].ids { if let o = w.entity(m), dist2(o.x, o.y, u.x, u.y) < 1.3 * 1.3 { near = true; break } }
                        if near { contact += 1 }
                    }
                }
            }
            if ticks % 40 == 0 {
                for id in all {
                    guard let u = w.entity(id) else { continue }
                    let p0 = lastPos[id] ?? (u.x, u.y)
                    let moving = [.move, .attackMove, .patrol].contains(u.order)
                    let fighting = w.entity(u.target).map { t in w.weapon(u).map { w.edgeDist(u, t) <= $0.range + 0.5 } ?? false } ?? false
                    let gx = u.ox + u.formationDX, gy = u.oy + u.formationDY
                    if moving && !fighting && dist2(u.x, u.y, p0.0, p0.1) < 0.09 && dist2(u.x, u.y, gx, gy) > 4 { stuck += 2 }
                    lastPos[id] = (u.x, u.y)
                }
            }
            if sc.isMovementOnly {
                var arrived = 0
                for g in setup.groups { for id in g.ids { if let u = w.entity(id), arrivedAt(u, g.goal) { arrived += 1 } } }
                if arriveT == nil && Double(arrived) >= Double(all.count) * 0.9 { arriveT = w.time }
                if arrived == all.count { break }
            } else if !w.units(of: 0).contains(where: { !$0.isMine }) || !w.units(of: 1).contains(where: { !$0.isMine }) { break }
        }
        var result = "-"
        var special = ""
        if !sc.isMovementOnly {
            let rem = (0..<2).map { p in w.units(of: p).filter { !$0.isMine }.reduce(0.0) { $0 + data.units[$1.type].cost.value(e) * $1.hp / $1.maxHp } }
            result = "P0 \(Int(100 * rem[0] / max(1, initialValue[0])))% / P1 \(Int(100 * rem[1] / max(1, initialValue[1])))%"
        }
        if flag("debug") && sc.isMovementOnly {
            for g in setup.groups { for id in g.ids { if let u = w.entity(id), !arrivedAt(u, g.goal) {
                let off = slotOf[u.id] ?? (0, 0)
                let slot = (g.goal.0 + off.0, g.goal.1 + off.1)
                print("  not arrived: \(data.units[u.type].name) at (\(fmt(u.x)),\(fmt(u.y))) slot (\(fmt(slot.0)),\(fmt(slot.1))) d=\(fmt(dist2(u.x, u.y, slot.0, slot.1).squareRoot())) order=\(u.order) stuck=\(u.stuckTimer) blockedSlot=\(w.nav.isBlocked(Int(slot.0), Int(slot.1)))")
            } } }
        }
        if flag("debug") && !sc.isMovementOnly {
            for p in 0..<2 {
                let top = w.players[p].stats.damageByType.sorted { $0.value > $1.value }.map { "\(data.units[$0.key].name) \(Int($0.value))" }.joined(separator: ", ")
                print("  P\(p) damage by type: \(top)")
            }
        }
        if flag("debug") && linkedShare.1 > 0 { print("  machine units linked: \(100 * linkedShare.0 / linkedShare.1)%") }
        if flag("debug") && !roleStats.isEmpty {
            print("  out-of-range share by role: " + roleStats.sorted { $0.key < $1.key }.map { "\($0.key) \(Int(100 * Double($0.value.0) / Double(max(1, $0.value.1))))% (n=\($0.value.1))" }.joined(separator: ", "))
        }
        var arrivedPct = "-"
        if sc.isMovementOnly {
            var arrived = 0
            for g in setup.groups { for id in g.ids { if let u = w.entity(id), arrivedAt(u, g.goal) { arrived += 1 } } }
            arrivedPct = "\(100 * arrived / max(1, all.count))% (\(arriveT.map { fmt($0, 1) + "s" } ?? "—"))"
        }
        switch sc {
        case .battle50, .battle100, .battle200, .skirmish20: special = "enemy intrusion \(fmt(100 * intrSum / Double(max(1, samples)), 1))%"
        case .kite: special = "ranger melee-contact \(fmt(100 * Double(contact) / Double(max(1, contactAll)), 0))%"
        case .siege: special = "siege alive \(siegeIDs.filter { w.entity($0) != nil }.count)/\(siegeIDs.count)"
        case .airstrike: special = "aircraft alive \(airIDs.filter { w.entity($0) != nil }.count)/\(airIDs.count)"
        default: break
        }
        let st = simTimes.sorted()
        let row = "| \(sc.rawValue) | \(result) | \(fmt(w.time, 1))s | \(fmt(100 * overlapSum / Double(max(1, samples)), 1)) | \(peak) | \(fmt(densSum / Double(max(1, samples)), 2)) | \(upAll > 0 ? fmt(100 * Double(upIn) / Double(upAll), 0) : "-") | \(Int(stuck)) | \(arrivedPct) | \(responseT.map { fmt($0, 2) + "s" } ?? "—") | \(special) | \(fmt(simTimes.reduce(0, +) / Double(max(1, simTimes.count)), 2))/\(fmt(st.last ?? 0, 1)) |"
        rows.append(row)
        print(row); fflush(stdout)
    }
    let outPath = opt("out", "")
    if !outPath.isEmpty { try? rows.joined(separator: "\n").write(toFile: outPath, atomically: true, encoding: .utf8) }

default:
    print("unknown command \(cmd)")
}
