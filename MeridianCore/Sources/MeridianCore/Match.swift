import Foundation

/// A world plus its computer opponents. The app and the headless harness both drive matches through this.
public final class Match {
    public let world: World
    public var ais: [AIController]
    /// Hard time limit for headless runs (seconds of game time); nil = unlimited.
    public var timeLimit: Double?
    /// The human's orders being recorded (see `record(human:quick:)`), and a recording being played back.
    public var recording: Replay? = nil
    public internal(set) var replay: Replay? = nil
    var replayCursor = 0
    public var isReplay: Bool { replay != nil }
    /// Replay playback: how far through the recorded orders we are (0...1).
    public var replayProgress: Double { replay.map { r in r.duration > 0 ? min(1, world.time / r.duration) : 1 } ?? 0 }

    public init(config: MatchConfig, ai: [(player: Int, difficulty: Difficulty, strategy: AIStrategy)], data: GameData = .shared) {
        world = World(config: config, data: data)
        ais = ai.map { AIController(player: $0.player, difficulty: $0.difficulty, strategy: $0.strategy, seed: config.seed) }
    }

    public func step() {
        applyReplayCommands()
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

    /// The best-scoring team's leading player (teams pool their score).
    func scoreLeader() -> Int {
        var teamScore: [Int: Double] = [:]
        for p in world.players where !p.defeated { teamScore[p.team, default: 0] += score(p.index) }
        guard let team = teamScore.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) })?.key else { return -1 }
        return world.players.filter { $0.team == team && !$0.defeated }.max { score($0.index) < score($1.index) }?.index ?? -1
    }
}
