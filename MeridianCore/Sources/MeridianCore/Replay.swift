import Foundation

extension Formation: Codable {}

/// Every order a player can give, as data. The UI issues orders through `Match.issue`, which applies the
/// command and records it; a replay feeds the same commands back at the same ticks. The simulation is
/// deterministic, so the computer commanders (seeded from the match) do exactly what they did the first time.
public enum Command: Codable, Sendable, Equatable {
    case move(ids: [Int], x: Double, y: Double, attack: Bool, formation: Formation)
    case patrol(ids: [Int], ax: Double, ay: Double, bx: Double, by: Double, formation: Formation)
    case attack(ids: [Int], target: Int)
    case stop(ids: [Int])
    case hold(ids: [Int])
    case smart(ids: [Int], x: Double, y: Double, target: Int?, player: Int, formation: Formation)
    case gather(ids: [Int], node: Int)
    case rally(building: Int, x: Double, y: Double)
    case toggleMode(ids: [Int])
    case unload(transport: Int, x: Double, y: Double)
    case emp(ids: [Int], x: Double, y: Double)
    case train(building: Int, unit: Int)
    case research(building: Int, upgrade: Int)
    case cancel(building: Int, index: Int)
    case build(workers: [Int], type: Int, tileX: Int, tileY: Int)
    case cancelConstruction(building: Int)
    case configureSite(site: Int, player: Int, installation: Installation)
}

extension World {
    /// Applies a command. Returns the command's error text, if it had one.
    @discardableResult
    public func apply(_ c: Command) -> String? {
        switch c {
        case .move(let ids, let x, let y, let attack, let f): commandMove(ids, x: x, y: y, attack: attack, formation: f); return nil
        case .patrol(let ids, let ax, let ay, let bx, let by, let f): commandPatrol(ids, from: (ax, ay), to: (bx, by), formation: f); return nil
        case .attack(let ids, let t): commandAttack(ids, target: t); return nil
        case .stop(let ids): commandStop(ids); return nil
        case .hold(let ids): commandHold(ids); return nil
        case .smart(let ids, let x, let y, let t, let p, let f): commandSmart(ids, x: x, y: y, targetID: t, player: p, formation: f); return nil
        case .gather(let ids, let n): commandGather(ids, node: n); return nil
        case .rally(let b, let x, let y): setRally(b, x: x, y: y); return nil
        case .toggleMode(let ids): commandToggleMode(ids); return nil
        case .unload(let t, let x, let y): commandUnload(t, x: x, y: y); return nil
        case .emp(let ids, let x, let y): commandEMP(ids, x: x, y: y); return nil
        case .train(let b, let u): return commandTrain(b, unitType: u)
        case .research(let b, let g): return commandResearch(b, upgrade: g)
        case .cancel(let b, let i): commandCancel(b, index: i); return nil
        case .build(let w, let t, let x, let y): return commandBuild(w, type: t, tileX: x, tileY: y)
        case .cancelConstruction(let b): commandCancelConstruction(b); return nil
        case .configureSite(let s, let p, let inst): return configureSite(s, player: p, installation: inst)
        }
    }
}

/// A recorded match: how it was set up and every order the human gave, with the tick it was given on.
public struct Replay: Codable {
    public static let formatVersion = 1
    public var version = Replay.formatVersion
    public var factions: [Faction]
    public var teams: [Int]
    public var victory: VictoryMode
    public var layout: MapLayout
    public var seed: UInt64
    public var mapSize: Int
    public var quick: Bool
    public var human: Int
    public var ais: [AISetup]
    public var commands: [Entry] = []
    /// Filled in when the match ends.
    public var winner: Int? = nil
    public var victoryReason = ""
    public var duration = 0.0
    public var recordedAt = Date()

    public struct AISetup: Codable { public var player: Int; public var difficulty: Difficulty; public var strategy: AIStrategy }
    public struct Entry: Codable { public var tick: Int; public var command: Command }

    init(config: MatchConfig, quick: Bool, human: Int, ais: [AIController]) {
        factions = config.factions; teams = config.teams; victory = config.victory; layout = config.layout
        seed = config.seed; mapSize = config.mapSize; self.quick = quick; self.human = human
        self.ais = ais.map { AISetup(player: $0.player, difficulty: $0.difficulty, strategy: $0.strategy) }
    }

    public var config: MatchConfig {
        MatchConfig(factions: factions, teams: teams, victory: victory, layout: layout, seed: seed, mapSize: mapSize)
    }

    /// One line for a list: "Concord vs Lattice · Crossroads · 14:02 · Victory".
    public func summary(_ data: GameData) -> String {
        let mine = factions.indices.filter { teams[$0] == teams[human] }.map { data.faction(factions[$0]).name }.joined(separator: " + ")
        let theirs = factions.indices.filter { teams[$0] != teams[human] }.map { data.faction(factions[$0]).name }.joined(separator: " + ")
        let time = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
        let result: String
        if let w = winner { result = w < 0 ? "Draw" : (teams[w] == teams[human] ? "Victory" : "Defeat") } else { result = "Unfinished" }
        return "\(mine) vs \(theirs) · \(layout.title) · \(time) · \(result)"
    }
}

extension Match {
    /// Starts recording the human player's orders for this match.
    public func record(human: Int, quick: Bool) {
        recording = Replay(config: world.config, quick: quick, human: human, ais: ais)
    }

    /// Applies an order now and, when recording, writes it down with the current tick.
    @discardableResult
    public func issue(_ c: Command) -> String? {
        recording?.commands.append(Replay.Entry(tick: world.tick, command: c))
        return world.apply(c)
    }

    /// A match that plays a recording back: the same settings and computer commanders, with the recorded orders
    /// re-issued on their ticks by `step()`.
    public static func load(replay r: Replay, data: GameData? = nil) -> Match {
        let m = Match(config: r.config, ai: r.ais.map { (player: $0.player, difficulty: $0.difficulty, strategy: $0.strategy) },
                      data: data ?? (r.quick ? .quick : .shared))
        m.replay = r
        return m
    }

    /// Orders due this tick, applied before the simulation steps (called from `step`).
    func applyReplayCommands() {
        guard let r = replay else { return }
        while replayCursor < r.commands.count, r.commands[replayCursor].tick <= world.tick {
            world.apply(r.commands[replayCursor].command)
            replayCursor += 1
        }
    }

    /// The recording with the result filled in (nil when this match was not recorded).
    public func finishedRecording() -> Replay? {
        guard var r = recording else { return nil }
        r.winner = world.winner; r.victoryReason = world.victoryReason; r.duration = world.time
        return r
    }
}
