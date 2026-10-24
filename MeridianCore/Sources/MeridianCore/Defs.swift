import Foundation

// MARK: - Basic enums

public enum Faction: String, Codable, CaseIterable, Sendable {
    case humans, machines, aliens
}

public enum ResourceKind: Int, Codable, CaseIterable, Sendable {
    case iron = 0, gold = 1, wood = 2
    public var name: String { ["Iron", "Gold", "Wood"][rawValue] }
}

public enum Domain: String, Codable, Sendable { case ground, air }

public enum BuildingKind: String, Codable, CaseIterable, Sendable {
    case hq, depot, infantry, heavy, air, research, tower, forward
}

public struct Cost: Codable, Equatable, Sendable {
    public var iron: Int
    public var gold: Int
    public var wood: Int
    public init(iron: Int = 0, gold: Int = 0, wood: Int = 0) { self.iron = iron; self.gold = gold; self.wood = wood }
    public subscript(k: ResourceKind) -> Int {
        switch k { case .iron: return iron; case .gold: return gold; case .wood: return wood }
    }
    /// Economic value used by balance tools. Gold is scarcer so it is weighted higher.
    public func value(_ r: EconomyRules) -> Double {
        Double(iron) * r.valueIron + Double(gold) * r.valueGold + Double(wood) * r.valueWood
    }
    public func scaled(_ m: Double) -> Cost {
        Cost(iron: Int((Double(iron) * m).rounded()), gold: Int((Double(gold) * m).rounded()), wood: Int((Double(wood) * m).rounded()))
    }
    public var isZero: Bool { iron == 0 && gold == 0 && wood == 0 }
}

// MARK: - Definitions loaded from JSON

public struct WeaponDef: Codable, Sendable {
    public var damage: Double
    public var interval: Double
    public var range: Double
    public var targetsGround: Bool
    public var targetsAir: Bool
    public var splash: Double?
    public var projectileSpeed: Double?
    public var minRange: Double?
    /// Multiplier against targets carrying the tag (light, armored, bio, mech, air, structure, massive).
    public var bonus: [String: Double]?
    /// Visual style key for the renderer (bullet, beam, arc, shell, acid, spine, flak, bomb, rail, pulse).
    public var projectile: String?
}

public struct UnitDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var faction: Faction
    public var role: String
    public var hp: Double
    public var armor: Double
    public var speed: Double
    public var sight: Double
    public var domain: Domain
    public var tags: [String]
    public var radius: Double
    public var cost: Cost
    public var buildTime: Double
    public var producedAt: BuildingKind
    public var requires: [String]
    public var weapon: WeaponDef?
    public var abilities: [String]?
    public var params: [String: Double]?
    public var description: String
    public var strongVs: String
    public var weakVs: String
    /// Units spawned per production cycle (Skitter clutches).
    public var batch: Int?
}

public struct BuildingDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var faction: Faction
    public var kind: BuildingKind
    public var hp: Double
    public var armor: Double
    public var size: Int
    public var sight: Double
    public var cost: Cost
    public var buildTime: Double
    public var requires: [String]
    public var weapon: WeaponDef?
    public var abilities: [String]?
    public var params: [String: Double]?
    public var description: String
}

public struct EffectDef: Codable, Sendable {
    /// damage(mul) armor(add) hp(mul) speed(mul) range(add) sight(add) gather(mul) buildTime(mul) interval(mul) regen(add) linkBonus(add) ...
    public var stat: String
    /// "all", "ground", "air", "bio", "mech", "towers", "buildings", "workers", a tag, or a unit/building id.
    public var target: String
    public var add: Double?
    public var mul: Double?
}

public struct UpgradeDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var faction: Faction
    public var cost: Cost
    public var time: Double
    public var researchedAt: BuildingKind
    public var requires: [String]
    public var tier: Int
    public var effects: [EffectDef]
    public var exclusiveWith: String?
    public var description: String
}

public struct FactionDef: Codable, Sendable {
    public var faction: Faction
    public var name: String
    public var tagline: String
    public var hpMult: Double
    public var buildTimeMult: Double
    public var description: String
}

public struct EconomyRules: Codable, Sendable {
    public var startIron: Int
    public var startGold: Int
    public var startWood: Int
    public var startWorkers: Int
    public var carry: [Int]          // per ResourceKind
    public var gatherTime: [Double]  // seconds per load
    public var valueIron: Double
    public var valueGold: Double
    public var valueWood: Double
    public var ironNodeAmount: Int
    public var goldNodeAmount: Int
    public var treeAmount: Int
}

public struct TerritoryRules: Codable, Sendable {
    public var captureRadius: Double
    public var captureTime: Double
    public var maxCaptureMult: Double
    public var income: [Double]           // per second, per ResourceKind
    public var vision: Double
    public var dominanceFraction: Double
    public var dominanceSeconds: Double
    /// Game time (s) after which the dominance countdown can run.
    public var dominanceStart: Double
    public var humanRepairRate: Double
    public var humanStagingRadius: Double
    public var machineNodeRadius: Double
    public var alienBloomRadius: Double
    public var alienSpeedBonus: Double
    public var installCost: Cost
    public var extractorIncomeMult: Double
    public var watchVision: Double
    public var bulwarkHp: Double
    public var bulwarkWeapon: WeaponDef
}

public struct CombatRules: Codable, Sendable {
    public var minDamageFraction: Double
    public var unitCap: Int
    public var networkLinkRadius: Double
    public var networkLinkMinNeighbors: Int
    public var networkDamageReduction: Double
    public var networkDamageBonus: Double
    public var alienRegenFlat: Double
    public var alienRegenPercent: Double
    public var outOfCombatSeconds: Double
    public var towerCostGrowth: Double
    public var towerBuildRadius: Double
    public var buildingRegenAliens: Double
}

public struct GameRules: Codable, Sendable {
    public var economy: EconomyRules
    public var territory: TerritoryRules
    public var combat: CombatRules
    /// Pace of the match relative to standard (Quick Match < 1). The AI reads time on this clock.
    public var tempo: Double?
}

// MARK: - Database

public final class GameData: @unchecked Sendable {
    public let units: [UnitDef]
    public let buildings: [BuildingDef]
    public let upgrades: [UpgradeDef]
    public let factions: [FactionDef]
    public let rules: GameRules

    public let unitIndex: [String: Int]
    public let buildingIndex: [String: Int]
    public let upgradeIndex: [String: Int]

    public init(units: [UnitDef], buildings: [BuildingDef], upgrades: [UpgradeDef], factions: [FactionDef], rules: GameRules, applyFactionMultipliers: Bool = true) {
        var us = units
        var bs = buildings
        if applyFactionMultipliers {
            // Faction identity: durability and production speed multipliers are applied on top of
            // the per-unit baseline numbers in the JSON, which are then individually tuned.
            for i in us.indices {
                guard let f = factions.first(where: { $0.faction == us[i].faction }) else { continue }
                us[i].hp = (us[i].hp * f.hpMult).rounded()
                us[i].buildTime = (us[i].buildTime * f.buildTimeMult * 10).rounded() / 10
            }
            for i in bs.indices {
                guard let f = factions.first(where: { $0.faction == bs[i].faction }) else { continue }
                bs[i].hp = (bs[i].hp * f.hpMult).rounded()
                bs[i].buildTime = (bs[i].buildTime * f.buildTimeMult * 10).rounded() / 10
            }
        }
        self.units = us
        self.buildings = bs
        self.upgrades = upgrades
        self.factions = factions
        self.rules = rules
        var ui: [String: Int] = [:]; for (i, u) in us.enumerated() { ui[u.id] = i }
        var bi: [String: Int] = [:]; for (i, b) in bs.enumerated() { bi[b.id] = i }
        var gi: [String: Int] = [:]; for (i, g) in upgrades.enumerated() { gi[g.id] = i }
        unitIndex = ui; buildingIndex = bi; upgradeIndex = gi
    }

    public static func load(from dir: URL? = nil) throws -> GameData {
        let base = dir ?? Bundle.module.url(forResource: "Data", withExtension: nil)!
        let dec = JSONDecoder()
        func read<T: Decodable>(_ name: String, _ t: T.Type) throws -> T {
            let data = try Data(contentsOf: base.appendingPathComponent(name))
            do { return try dec.decode(T.self, from: data) } catch {
                throw NSError(domain: "GameData", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): \(error)"])
            }
        }
        var units: [UnitDef] = []
        for f in ["units_humans.json", "units_machines.json", "units_aliens.json"] { units += try read(f, [UnitDef].self) }
        let buildings = try read("buildings.json", [BuildingDef].self)
        let upgrades = try read("upgrades.json", [UpgradeDef].self)
        let factions = try read("factions.json", [FactionDef].self)
        let rules = try read("rules.json", GameRules.self)
        return GameData(units: units, buildings: buildings, upgrades: upgrades, factions: factions, rules: rules)
    }

    /// Quick Match: the same units and costs on a faster clock — shorter build, train and research times,
    /// richer starts, quicker gathering and capture, and an earlier, shorter dominance victory.
    /// Combat is untouched, so the factions' strengths relative to each other are unchanged.
    public static let quickTempo = 0.6
    nonisolated(unsafe) private static var _quick: GameData?
    public static var quick: GameData {
        if let q = _quick { return q }
        let s = shared, k = quickTempo
        var us = s.units, bs = s.buildings, gs = s.upgrades, r = s.rules
        for i in us.indices { us[i].buildTime = (us[i].buildTime * k * 10).rounded() / 10 }
        for i in bs.indices { bs[i].buildTime = (bs[i].buildTime * k * 10).rounded() / 10 }
        for i in gs.indices { gs[i].time = (gs[i].time * k).rounded() }
        r.economy.startIron *= 2; r.economy.startWood *= 2; r.economy.startGold += 100
        r.economy.gatherTime = r.economy.gatherTime.map { $0 * k }
        r.territory.captureTime *= k
        r.territory.income = r.territory.income.map { $0 / k }
        r.territory.dominanceStart = 420
        r.territory.dominanceSeconds = 150
        r.tempo = k
        let q = GameData(units: us, buildings: bs, upgrades: gs, factions: s.factions, rules: r, applyFactionMultipliers: false)
        _quick = q
        return q
    }
    /// Quick Match battlefields are smaller.
    public static let quickMapSize = 84

    nonisolated(unsafe) private static var _shared: GameData?
    public static var shared: GameData {
        if let s = _shared { return s }
        let s = try! load()
        _shared = s
        return s
    }

    public func faction(_ f: Faction) -> FactionDef { factions.first { $0.faction == f }! }
    public func unitIDs(_ f: Faction) -> [Int] { units.indices.filter { units[$0].faction == f } }
    public func buildingIDs(_ f: Faction) -> [Int] { buildings.indices.filter { buildings[$0].faction == f } }
    public func upgradeIDs(_ f: Faction) -> [Int] { upgrades.indices.filter { upgrades[$0].faction == f } }
    public func building(_ f: Faction, _ k: BuildingKind) -> Int {
        buildings.indices.first { buildings[$0].faction == f && buildings[$0].kind == k }!
    }
    public func worker(_ f: Faction) -> Int { units.indices.first { units[$0].faction == f && units[$0].role == "worker" }! }

    /// Basic validation used by tests and at startup in debug builds.
    public func validate() -> [String] {
        var problems: [String] = []
        for f in Faction.allCases {
            let u = units.filter { $0.faction == f }
            if u.count != 15 { problems.append("\(f): \(u.count) units (expected 15)") }
            let b = buildings.filter { $0.faction == f }
            if Set(b.map { $0.kind }).count != 8 { problems.append("\(f): building kinds \(b.count)") }
        }
        let known = Set(units.map { $0.id } + buildings.map { $0.id } + upgrades.map { $0.id })
        for u in units { for r in u.requires where !known.contains(r) { problems.append("\(u.id) requires unknown \(r)") } }
        for b in buildings { for r in b.requires where !known.contains(r) { problems.append("\(b.id) requires unknown \(r)") } }
        for g in upgrades {
            for r in g.requires where !known.contains(r) { problems.append("\(g.id) requires unknown \(r)") }
            if let x = g.exclusiveWith, upgradeIndex[x] == nil { problems.append("\(g.id) exclusive unknown \(x)") }
        }
        return problems
    }
}
