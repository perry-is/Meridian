import Foundation

public struct StatMods: Sendable, Codable {
    public var damage = 1.0
    public var armor = 0.0
    public var hp = 1.0
    public var speed = 1.0
    public var range = 0.0
    public var interval = 1.0
    public var sight = 0.0
    public var buildTime = 1.0
}

/// Aggregated upgrade effects for one player. Recomputed whenever research completes.
public struct PlayerMods: Sendable, Codable {
    public var unit: [StatMods]
    public var building: [StatMods]
    public var gather = 1.0
    public var linkRadius = 0.0
    public var linkBonus = 0.0
    public var empResist = 0.0
    public var stagingAdd = 0.0
    public var bloomAdd = 0.0
    public var regen = 1.0
    public var forwardRepair = 1.0

    init(data: GameData) {
        unit = Array(repeating: StatMods(), count: data.units.count)
        building = Array(repeating: StatMods(), count: data.buildings.count)
    }

    static func unitMatches(_ u: UnitDef, _ target: String) -> Bool {
        switch target {
        case "all", "units": return true
        case "ground": return u.domain == .ground
        case "air": return u.domain == .air
        case "workers": return u.role == "worker"
        default: return u.id == target || u.tags.contains(target)
        }
    }

    static func buildingMatches(_ b: BuildingDef, _ target: String) -> Bool {
        switch target {
        case "buildings": return true
        case "towers": return b.kind == .tower
        default: return b.id == target
        }
    }

    mutating func apply(_ e: EffectDef, data: GameData, faction: Faction) {
        let mul = e.mul ?? 1, add = e.add ?? 0
        switch e.stat {
        case "gather": gather *= mul
        case "linkRadius": linkRadius += add
        case "linkBonus": linkBonus += add
        case "empResist": empResist += add
        case "stagingRadius": stagingAdd += add
        case "bloomRadius": bloomAdd += add
        case "regen": regen *= mul
        case "repairRate": forwardRepair *= mul
        default:
            for (i, u) in data.units.enumerated() where u.faction == faction && PlayerMods.unitMatches(u, e.target) {
                Self.modify(&unit[i], e.stat, mul, add)
            }
            for (i, b) in data.buildings.enumerated() where b.faction == faction && PlayerMods.buildingMatches(b, e.target) {
                Self.modify(&building[i], e.stat, mul, add)
            }
        }
    }

    static func modify(_ m: inout StatMods, _ stat: String, _ mul: Double, _ add: Double) {
        switch stat {
        case "damage": m.damage *= mul
        case "armor": m.armor += add
        case "hp": m.hp *= mul
        case "speed": m.speed *= mul
        case "range": m.range += add
        case "interval": m.interval *= mul
        case "sight": m.sight += add
        case "buildTime": m.buildTime *= mul
        default: break
        }
    }
}

public struct PlayerStats: Sendable, Codable {
    public var gathered: [Int] = [0, 0, 0]
    public var territoryIncome: [Double] = [0, 0, 0]
    public var unitsProduced = 0
    public var unitsLost = 0
    public var kills = 0
    public var buildingsBuilt = 0
    public var buildingsLost = 0
    public var valueKilled = 0.0
    public var valueLost = 0.0
    public var peakUnits = 0
    public var producedByType: [Int: Int] = [:]
    public var lostByType: [Int: Int] = [:]
    /// Analytics: damage dealt per unit type (after armour).
    public var damageByType: [Int: Double] = [:]
}

public final class Player {
    public let index: Int
    public let faction: Faction
    public var name: String
    public var res: [Int]
    public var incomeAcc: [Double] = [0, 0, 0]
    public var completedUpgrades = Set<Int>()
    public var researching = Set<Int>()
    public var mods: PlayerMods
    public var unitCount = 0
    public var defeated = false
    public var completeBuildings: [BuildingKind: Int] = [:]
    public var completeBuildingIDs = Set<Int>()
    public var towerCount = 0
    public var stats = PlayerStats()
    public var dominanceTimer = 0.0

    // Per-tile grids (size*size)
    public var visible: [UInt8]
    public var explored: [Bool]
    public var detected: [Bool]
    /// Zone grids: bit 0 = bloom (aliens), bit 1 = staging (humans), bit 2 = network (machines), bit 3 = build zone
    public var zones: [UInt8]

    init(index: Int, faction: Faction, data: GameData, mapSize: Int) {
        self.index = index
        self.faction = faction
        self.name = data.faction(faction).name
        let e = data.rules.economy
        res = [e.startIron, e.startGold, e.startWood]
        mods = PlayerMods(data: data)
        let n = mapSize * mapSize
        visible = Array(repeating: 0, count: n)
        explored = Array(repeating: false, count: n)
        detected = Array(repeating: false, count: n)
        zones = Array(repeating: 0, count: n)
    }

    public func canAfford(_ c: Cost) -> Bool { res[0] >= c.iron && res[1] >= c.gold && res[2] >= c.wood }
    func pay(_ c: Cost) { res[0] -= c.iron; res[1] -= c.gold; res[2] -= c.wood }
    func refund(_ c: Cost) { res[0] += c.iron; res[1] += c.gold; res[2] += c.wood }

    func recomputeMods(_ data: GameData) {
        var m = PlayerMods(data: data)
        for u in completedUpgrades.sorted() {
            for e in data.upgrades[u].effects { m.apply(e, data: data, faction: faction) }
        }
        mods = m
    }

    /// Whether every id in `reqs` (building ids or upgrade ids) is satisfied.
    public func meets(_ reqs: [String], _ data: GameData) -> Bool {
        for r in reqs {
            if let b = data.buildingIndex[r] { if !completeBuildingIDs.contains(b) { return false } }
            else if let g = data.upgradeIndex[r] { if !completedUpgrades.contains(g) { return false } }
            else { return false }
        }
        return true
    }

    public func missing(_ reqs: [String], _ data: GameData) -> [String] {
        reqs.filter { r in
            if let b = data.buildingIndex[r] { return !completeBuildingIDs.contains(b) }
            if let g = data.upgradeIndex[r] { return !completedUpgrades.contains(g) }
            return true
        }.map { r in
            if let b = data.buildingIndex[r] { return data.buildings[b].name }
            if let g = data.upgradeIndex[r] { return data.upgrades[g].name }
            return r
        }
    }
}
