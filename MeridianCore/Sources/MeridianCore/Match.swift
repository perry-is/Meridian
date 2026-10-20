import Foundation

/// A world plus its computer opponents. The app and the headless harness both drive matches through this.
public final class Match {
    public let world: World
    public var ais: [AIController]
    /// Hard time limit for headless runs (seconds of game time); nil = unlimited.
    public var timeLimit: Double?

    public init(config: MatchConfig, ai: [(player: Int, difficulty: Difficulty, strategy: AIStrategy)], data: GameData = .shared) {
        world = World(config: config, data: data)
        ais = ai.map { AIController(player: $0.player, difficulty: $0.difficulty, strategy: $0.strategy, seed: config.seed) }
    }

    public func step() {
        for a in ais { a.update(world) }
        world.step()
        if let lim = timeLimit, world.time >= lim, world.winner == nil {
            world.winner = scoreLeader()
            world.victoryReason = "Time limit (score)"
        }
    }

    /// Score used to adjudicate time-limited headless matches: destroyed value + territory + economy.
    public func score(_ p: Int) -> Double {
        let s = world.players[p].stats
        let sites = Double(world.sites.filter { $0.owner == p }.count)
        let army = world.entities.filter { $0.isUnit && $0.alive && $0.owner == p && !$0.isMine }
            .reduce(0.0) { $0 + world.data.units[$1.type].cost.value(world.data.rules.economy) }
        return s.valueKilled + army * 0.5 + sites * 400
    }

    func scoreLeader() -> Int {
        var best = -1, bs = -Double.infinity
        for p in world.players.indices { let s = score(p); if s > bs { bs = s; best = p } }
        return best
    }
}
