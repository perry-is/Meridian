import Foundation

// MARK: Codable conformances for saved state

extension OrderKind: Codable {}
extension EntityKind: Codable {}
extension Installation: Codable {}
extension Difficulty: Codable {}
extension AIStrategy: Codable {}
extension MapLayout: Codable {}

/// A player's evolving state.
public struct PlayerSnapshot: Codable {
    var name: String
    var res: [Int]
    var incomeAcc: [Double]
    var completedUpgrades: Set<Int>
    var researching: Set<Int>
    var mods: PlayerMods
    var unitCount: Int
    var defeated: Bool
    var completeBuildings: [BuildingKind: Int]
    var completeBuildingIDs: Set<Int>
    var towerCount: Int
    var stats: PlayerStats
    var dominanceTimer: Double
    var visible: [UInt8]
    var explored: [Bool]
    var detected: [Bool]
    var zones: [UInt8]
}

extension Player {
    func snapshot() -> PlayerSnapshot {
        PlayerSnapshot(name: name, res: res, incomeAcc: incomeAcc, completedUpgrades: completedUpgrades, researching: researching, mods: mods,
                       unitCount: unitCount, defeated: defeated, completeBuildings: completeBuildings, completeBuildingIDs: completeBuildingIDs,
                       towerCount: towerCount, stats: stats, dominanceTimer: dominanceTimer, visible: visible, explored: explored, detected: detected, zones: zones)
    }
    func restore(_ s: PlayerSnapshot) {
        name = s.name; res = s.res; incomeAcc = s.incomeAcc; completedUpgrades = s.completedUpgrades; researching = s.researching; mods = s.mods
        unitCount = s.unitCount; defeated = s.defeated; completeBuildings = s.completeBuildings; completeBuildingIDs = s.completeBuildingIDs
        towerCount = s.towerCount; stats = s.stats; dominanceTimer = s.dominanceTimer; visible = s.visible; explored = s.explored; detected = s.detected; zones = s.zones
    }
}

/// The computer opponent's memory and plans.
public struct AISnapshot: Codable {
    var player: Int
    var difficulty: Difficulty
    var strategy: AIStrategy
    var rng: RNG
    var nextThink: Double
    var thinkInterval: Double
    var workerTarget: Int
    var attackThreshold: Double
    var maxQueue: Int
    var firstAttack: Double
    var attackGap: Double
    var waveCap: Int
    var retreatAt: Double
    var attackGroup: Set<Int>
    var attacking: Bool
    var attackTarget: [Double]?
    var attackStartValue: Double
    var lastAttackEnd: Double
    var scoutID: Int
    var scouted: Bool
    var enemySeen: [Int: Int]
    var enemyTowersSeen: Int
    var enemyCloakSeen: Bool
    var siteSquads: [Int: [Int]]
    var lastPlan: String
    var armyCount: Int
    var raided: Bool
    var assembling: Bool
    var assembleSince: Double
    /// Hard AI raids and two-pronged attacks (optional so earlier saves still load).
    var raidGroup: Set<Int>?
    var raidTarget: [Double]?
    var raidStart: Double?
    var raidStartValue: Double?
    var lastRaidEnd: Double?
    var prongGroup: Set<Int>?
    var prongTarget: [Double]?
}

extension AIController {
    func snapshot() -> AISnapshot {
        AISnapshot(player: player, difficulty: difficulty, strategy: strategy, rng: rng, nextThink: nextThink, thinkInterval: thinkInterval,
                   workerTarget: workerTarget, attackThreshold: attackThreshold, maxQueue: maxQueue, firstAttack: firstAttack, attackGap: attackGap,
                   waveCap: waveCap, retreatAt: retreatAt, attackGroup: attackGroup, attacking: attacking, attackTarget: attackTarget.map { [$0.0, $0.1] },
                   attackStartValue: attackStartValue, lastAttackEnd: lastAttackEnd, scoutID: scoutID, scouted: scouted, enemySeen: enemySeen,
                   enemyTowersSeen: enemyTowersSeen, enemyCloakSeen: enemyCloakSeen, siteSquads: siteSquads, lastPlan: lastPlan, armyCount: armyCount,
                   raided: raided, assembling: assembling, assembleSince: assembleSince,
                   raidGroup: raidGroup, raidTarget: raidTarget.map { [$0.0, $0.1] }, raidStart: raidStart, raidStartValue: raidStartValue,
                   lastRaidEnd: lastRaidEnd, prongGroup: prongGroup, prongTarget: prongTarget.map { [$0.0, $0.1] })
    }
    static func restore(_ s: AISnapshot) -> AIController {
        let a = AIController(player: s.player, difficulty: s.difficulty, strategy: s.strategy)
        a.rng = s.rng; a.nextThink = s.nextThink; a.thinkInterval = s.thinkInterval; a.workerTarget = s.workerTarget
        a.attackThreshold = s.attackThreshold; a.maxQueue = s.maxQueue; a.firstAttack = s.firstAttack; a.attackGap = s.attackGap
        a.waveCap = s.waveCap; a.retreatAt = s.retreatAt; a.attackGroup = s.attackGroup; a.attacking = s.attacking
        a.attackTarget = s.attackTarget.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        a.attackStartValue = s.attackStartValue; a.lastAttackEnd = s.lastAttackEnd; a.scoutID = s.scoutID; a.scouted = s.scouted
        a.enemySeen = s.enemySeen; a.enemyTowersSeen = s.enemyTowersSeen; a.enemyCloakSeen = s.enemyCloakSeen; a.siteSquads = s.siteSquads
        a.setPlan(s.lastPlan); a.armyCount = s.armyCount; a.raided = s.raided; a.assembling = s.assembling; a.assembleSince = s.assembleSince
        a.raidGroup = s.raidGroup ?? []; a.raidTarget = s.raidTarget.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        a.raidStart = s.raidStart ?? 0; a.raidStartValue = s.raidStartValue ?? 0; a.lastRaidEnd = s.lastRaidEnd ?? -1000
        a.prongGroup = s.prongGroup ?? []; a.prongTarget = s.prongTarget.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        return a
    }
}

/// Everything that changes during a match. The map, terrain and data are rebuilt from the match settings.
public struct WorldSnapshot: Codable {
    var tick: Int
    var time: Double
    var rng: RNG
    var nextID: Int
    var nextGroupID: Int
    var groupRemaining: [Int: Double]
    var winner: Int?
    var victoryReason: String
    var refreshZonesSoon: Bool
    var entities: [EntitySnapshot]
    var players: [PlayerSnapshot]
    var projectiles: [Projectile]
    var clouds: [Cloud]
    var sites: [Site]
}

extension World {
    func snapshot() -> WorldSnapshot {
        WorldSnapshot(tick: tick, time: time, rng: rng, nextID: nextID, nextGroupID: nextGroupID, groupRemaining: groupRemaining,
                      winner: winner, victoryReason: victoryReason, refreshZonesSoon: refreshZonesSoon,
                      entities: entities.filter { $0.alive }.map { $0.snapshot() }, players: players.map { $0.snapshot() },
                      projectiles: projectiles, clouds: clouds, sites: sites)
    }

    /// Replaces the dynamic state of a freshly generated world (same settings) with a snapshot.
    func restore(_ s: WorldSnapshot) {
        clearAll()
        byID = []
        tick = s.tick; time = s.time; rng = s.rng; nextID = s.nextID; nextGroupID = s.nextGroupID; groupRemaining = s.groupRemaining
        winner = s.winner; victoryReason = s.victoryReason; refreshZonesSoon = s.refreshZonesSoon
        for (p, ps) in zip(players, s.players) { p.restore(ps) }
        for es in s.entities { adopt(Entity.restore(es)) }
        projectiles = s.projectiles; clouds = s.clouds; sites = s.sites
        nav.invalidate()
    }
}

// MARK: Match save files

/// A complete saved match: settings, simulation state and the computer opponents.
public struct MatchSave: Codable {
    /// 2: team play. The map is regenerated from the seed on load, and the generator changed with it, so older saves cannot resume.
    public static let formatVersion = 2
    public var version = MatchSave.formatVersion
    public var factions: [Faction]
    /// Team per player and the victory mode (absent in saves from before team play, which were 1v1 dominance matches).
    public var teams: [Int]? = nil
    public var victory: VictoryMode? = nil
    public var layout: MapLayout
    public var seed: UInt64
    public var mapSize: Int
    public var swapStarts: Bool
    public var world: WorldSnapshot
    public var ais: [AISnapshot]
    /// App-side extras (camera, control groups, settings) — opaque to the core.
    public var extras: [String: String] = [:]
    public var savedAt = Date()
    public var gameTime: Double { world.time }
}

extension Match {
    public func save() -> MatchSave {
        let c = world.config
        return MatchSave(factions: c.factions, teams: c.teams, victory: c.victory, layout: c.layout, seed: c.seed, mapSize: c.mapSize,
                         swapStarts: c.swapStarts, world: world.snapshot(), ais: ais.map { $0.snapshot() })
    }

    /// Rebuilds the map from the saved settings, then restores the simulation and the AIs exactly as they were.
    public static func load(_ s: MatchSave, data: GameData = .shared) -> Match {
        let cfg = MatchConfig(factions: s.factions, teams: s.teams, victory: s.victory ?? .dominance, layout: s.layout, seed: s.seed,
                              mapSize: s.mapSize, swapStarts: s.swapStarts)
        let m = Match(config: cfg, ai: [], data: data)
        m.world.restore(s.world)
        m.ais = s.ais.map { AIController.restore($0) }
        return m
    }
}
