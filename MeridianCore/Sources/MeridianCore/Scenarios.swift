import Foundation

/// Reproducible tactical test scenarios shared by the headless harness and the app (`-scenario <name>`).
public enum TacticalScenario: String, CaseIterable, Sendable {
    case skirmish20, battle50, battle100, battle200, kite, wall, siege, corridor, airstrike

    public var factions: [Faction] {
        switch self {
        case .skirmish20: return [.humans, .aliens]
        case .kite: return [.humans, .aliens]
        case .siege: return [.humans, .aliens]
        case .airstrike: return [.humans, .machines]
        default: return [.humans, .machines]
        }
    }

    /// Seconds of simulated time before the harness stops.
    public var timeLimit: Double {
        switch self {
        case .wall, .corridor: return 75
        case .battle200: return 90
        default: return 90
        }
    }

    public var isMovementOnly: Bool { self == .wall || self == .corridor }

    /// Combined-arms rosters per 50 units (front line → rear).
    public static let roster: [Faction: [(String, Int)]] = [
        .humans: [("h_ranger", 13), ("h_breacher", 6), ("h_lancer", 6), ("h_skyguard", 4), ("h_medic", 3), ("h_buggy", 3), ("h_bastion", 4), ("h_mortar", 4), ("h_minelayer", 1), ("h_kestrel", 3), ("h_harrier", 3)],
        .machines: [("m_arc", 13), ("m_shockframe", 6), ("m_piercer", 6), ("m_flak", 4), ("m_repair", 3), ("m_runner", 3), ("m_bulwark", 4), ("m_coil", 4), ("m_suppress", 1), ("m_vector", 3), ("m_quake", 3)],
        .aliens: [("a_mantis", 13), ("a_ravager", 6), ("a_spinecaster", 6), ("a_needleback", 4), ("a_lifebinder", 3), ("a_skitter", 3), ("a_colossus", 4), ("a_rupturer", 4), ("a_seeder", 1), ("a_wisp", 3), ("a_blightwing", 3)],
    ]

    public static func rosterUnits(_ f: Faction, _ n: Int, data: GameData) -> [Int] {
        let roster = TacticalScenario.roster[f]!
        var list: [Int] = []
        for (id, k) in roster { list += Array(repeating: data.unitIndex[id]!, count: max(1, k * n / 50)) }
        while list.count > n { list.removeLast() }
        var k = 0
        while list.count < n { list.append(data.unitIndex[roster[k % 2].0]!); k += 1 }
        return list
    }

    /// Goal of the scenario for each side (where its army is ordered).
    public struct Setup { public var groups: [(owner: Int, ids: [Int], goal: (Double, Double), attack: Bool)] }

    @discardableResult
    public func setup(_ w: World, formation: Formation = .balanced) -> Setup {
        w.sandbox = true
        w.clearAll()
        w.unlockAll(0); w.unlockAll(1)
        let d = w.data
        let mid = Double(w.map.size) / 2
        var out = Setup(groups: [])
        func spawnBlock(_ owner: Int, _ types: [Int], cx: Double, cy: Double, facingRight: Bool) -> [Int] {
            // A loose deployment block (not a formation): the order decides how the army arranges itself.
            let cols = max(1, Int(Double(types.count).squareRoot() * 1.3))
            var ids: [Int] = []
            for (i, t) in types.enumerated() {
                let r = i / cols, c = i % cols
                let x = cx + (facingRight ? -1 : 1) * Double(r) * 1.1, y = cy + (Double(c) - Double(cols - 1) / 2) * 1.1
                let e = w.spawnUnit(t, owner: owner, x: x, y: y)
                e.facing = facingRight ? 0 : .pi
                ids.append(e.id)
            }
            return ids
        }
        func army(_ owner: Int, _ n: Int, cx: Double, right: Bool) -> [Int] {
            // Shuffle deterministically so formations have real sorting work to do.
            var types = TacticalScenario.rosterUnits(w.players[owner].faction, n, data: d)
            var r = RNG(seed: UInt64(owner * 31 + n))
            for i in stride(from: types.count - 1, to: 0, by: -1) { types.swapAt(i, r.int(i + 1)) }
            return spawnBlock(owner, types, cx: cx, cy: mid, facingRight: right)
        }
        func ids(_ owner: Int, _ list: [(String, Int)], cx: Double, cy: Double, right: Bool) -> [Int] {
            var types: [Int] = []
            for (id, k) in list { types += Array(repeating: d.unitIndex[id]!, count: k) }
            return spawnBlock(owner, types, cx: cx, cy: cy, facingRight: right)
        }
        switch self {
        case .skirmish20, .battle50, .battle100, .battle200:
            let n = self == .skirmish20 ? 20 : (self == .battle50 ? 50 : (self == .battle100 ? 100 : 200))
            let gap = n >= 100 ? 20.0 : 15.0
            let a = army(0, n, cx: mid - gap, right: true), b = army(1, n, cx: mid + gap, right: false)
            out.groups = [(0, a, (mid + 12, mid), true), (1, b, (mid - 12, mid), true)]
        case .kite:
            let a = ids(0, [("h_ranger", 12)], cx: mid - 6, cy: mid, right: true)
            let b = ids(1, [("a_mantis", 12)], cx: mid + 10, cy: mid, right: false)
            out.groups = [(0, a, (mid + 8, mid), true), (1, b, (mid - 12, mid), true)]
        case .siege:
            let a = ids(0, [("h_mortar", 8), ("h_bastion", 4), ("h_ranger", 12), ("h_lancer", 4), ("h_breacher", 4)], cx: mid - 14, cy: mid, right: true)
            let b = ids(1, [("a_mantis", 22), ("a_skitter", 10), ("a_ravager", 6)], cx: mid + 14, cy: mid, right: false)
            out.groups = [(0, a, (mid + 6, mid), true), (1, b, (mid - 18, mid), true)]
        case .airstrike:
            let a = ids(0, [("h_harrier", 8), ("h_kestrel", 6)], cx: mid - 20, cy: mid, right: true)
            let b = ids(1, [("m_flak", 6), ("m_arc", 8), ("m_bulwark", 2)], cx: mid + 6, cy: mid, right: false)
            let tower = d.building(.machines, .tower)
            w.spawnBuilding(tower, owner: 1, tileX: Int(mid) + 4, tileY: Int(mid) - 4, complete: true)
            w.spawnBuilding(tower, owner: 1, tileX: Int(mid) + 4, tileY: Int(mid) + 3, complete: true)
            out.groups = [(0, a, (mid + 8, mid), true), (1, b, (mid + 6, mid), false)]
        case .wall:
            // A wall with two gaps between the army and its destination.
            w.sandboxRock(x0: Int(mid) - 1, y0: Int(mid) - 26, x1: Int(mid) + 1, y1: Int(mid) - 13)
            w.sandboxRock(x0: Int(mid) - 1, y0: Int(mid) - 9, x1: Int(mid) + 1, y1: Int(mid) + 9)
            w.sandboxRock(x0: Int(mid) - 1, y0: Int(mid) + 13, x1: Int(mid) + 1, y1: Int(mid) + 26)
            let types = TacticalScenario.rosterUnits(.humans, 40, data: d).filter { d.units[$0].domain == .ground }
            let a = spawnBlock(0, types, cx: mid - 16, cy: mid, facingRight: true)
            out.groups = [(0, a, (mid + 18, mid), false)]
        case .corridor:
            // A 3-tile corridor; two groups enter from opposite ends at the same time.
            w.sandboxRock(x0: Int(mid) - 12, y0: Int(mid) - 20, x1: Int(mid) + 12, y1: Int(mid) - 2)
            w.sandboxRock(x0: Int(mid) - 12, y0: Int(mid) + 2, x1: Int(mid) + 12, y1: Int(mid) + 20)
            let ta = TacticalScenario.rosterUnits(.humans, 30, data: d).filter { d.units[$0].domain == .ground }
            let tb = TacticalScenario.rosterUnits(.machines, 30, data: d).filter { d.units[$0].domain == .ground }
            let a = spawnBlock(0, ta, cx: mid - 20, cy: mid, facingRight: true)
            let b = spawnBlock(0, tb, cx: mid + 20, cy: mid, facingRight: false)
            out.groups = [(0, a, (mid + 20, mid), false), (0, b, (mid - 20, mid), false)]
        }
        for g in out.groups { w.commandMove(g.ids, x: g.goal.0, y: g.goal.1, attack: g.attack, formation: formation) }
        return out
    }
}
