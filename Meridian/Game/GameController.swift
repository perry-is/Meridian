import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif
import MeridianCore

/// Isometric projection shared by the renderer and input. World tiles are 64x32 points.
enum Iso {
    static let hw: CGFloat = 32, hh: CGFloat = 16
    @inline(__always) static func scene(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: hw * CGFloat(x + y), y: hh * CGFloat(y - x))
    }
    @inline(__always) static func world(_ p: CGPoint) -> (Double, Double) {
        let a = Double(p.x / hw), b = Double(p.y / hh)
        return ((a - b) / 2, (a + b) / 2)
    }
    /// Depth: larger = closer to the viewer.
    @inline(__always) static func depth(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x - y) }
}

/// One commander in the battle setup: slot 0 is the player (or the first AI when watching), the rest are computer opponents.
struct PlayerSlot: Equatable, Hashable {
    var faction: Faction
    /// Commanders with the same team number are allies.
    var team: Int
}

struct GameSettings {
    /// Two to four commanders. Defaults to the classic 1v1.
    var slots: [PlayerSlot] = [PlayerSlot(faction: .humans, team: 0), PlayerSlot(faction: .machines, team: 1)]
    var victory: VictoryMode = .annihilation
    var difficulty: Difficulty = .normal
    var strategy: AIStrategy = .balanced
    var layout: MapLayout = .crossroads
    /// Quick Match: smaller map and a faster clock (about ten minutes).
    var quick = false
    var seed: UInt64 = UInt64(Date().timeIntervalSince1970) % 100_000
    /// The player chose or re-rolled this seed (or it came from `-seed`): keep it instead of drawing a fresh one.
    var seedLocked = false

    /// The player's faction (slot 0) and the first opponent's — kept for the 1v1 code paths, tests and tools.
    var playerFaction: Faction {
        get { slots[0].faction }
        set { slots[0].faction = newValue }
    }
    var aiFaction: Faction {
        get { slots.count > 1 ? slots[1].faction : .machines }
        set { if slots.count > 1 { slots[1].faction = newValue } else { slots.append(PlayerSlot(faction: newValue, team: 1)) } }
    }
    var factions: [Faction] { slots.map { $0.faction } }
    var teams: [Int] { slots.map { $0.team } }
    /// A battle needs at least two teams.
    var hasOpposingTeams: Bool { Set(teams).count >= 2 }
    var mapSize: Int { MatchConfig.mapSize(players: slots.count, quick: quick) }

    mutating func addSlot() {
        guard slots.count < MatchConfig.maxPlayers else { return }
        let used = Set(teams)
        let team = (0..<MatchConfig.maxPlayers).first { !used.contains($0) } ?? slots.count
        slots.append(PlayerSlot(faction: Faction.allCases[slots.count % Faction.allCases.count], team: team))
    }

    mutating func removeSlot(_ i: Int) {
        guard slots.count > 2, i > 0, i < slots.count else { return }
        slots.remove(at: i)
    }

    /// Allies of slot 0 and everyone else, by slot index.
    var allyIndices: [Int] { slots.indices.filter { $0 != 0 && slots[$0].team == slots[0].team } }
    var enemyIndices: [Int] { slots.indices.filter { slots[$0].team != slots[0].team } }
}

enum InputMode: Equatable {
    case normal, attackMove, patrol, place(Int), unload, emp, rally
}

struct CommandButton: Identifiable {
    let id: String
    var title: String
    var symbol: String
    var cost: Cost? = nil
    var enabled = true
    var reason: String? = nil
    var highlighted = false
    /// Tutorial: this is the button to press next.
    var glow = false
    var badge: String? = nil
    var progress: Double? = nil
    var queued = 0
    var hotkey: Character? = nil
    /// One line shown above the card when the button is tapped or held (role, strengths, what it does).
    var detail: String? = nil
    var action: () -> Void
}

struct QueueEntry: Identifiable {
    let id: Int
    var title: String
    var progress: Double
    var isUpgrade: Bool
}

struct Toast: Identifiable {
    let id = UUID()
    var text: String
    var time: Date
    var warning: Bool
    /// Where it happened: tapping the toast jumps the camera there.
    var at: (Double, Double)? = nil
}

/// Light haptic feedback for key moments (iPhone only).
enum Haptics {
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Snapshot published to SwiftUI a few times per second (cheap to diff, never touches the sim directly).
struct HUDState {
    var res = [0, 0, 0]
    var income = [0.0, 0.0, 0.0]
    var units = 0
    var cap = 200
    var time = 0.0
    var sitesOwned = 0
    var sitesEnemy = 0
    var sitesTotal = 7
    var dominanceNeed = 5
    var myDominance = 0.0
    var enemyDominance = 0.0
    var dominanceSeconds = 180.0
    var dominanceActive = false
    /// Dominance mode is on for this match (the site countdown matters).
    var dominanceMode = false
    var sitesAllied = 0
    var selectionTitle = ""
    var selectionSubtitle = ""
    var selectionDetail = ""
    var selectionHP: (Double, Double)? = nil
    var selectionCount = 0
    var selectionIcons: [(type: Int, count: Int, building: Bool)] = []
    var queue: [QueueEntry] = []
    var buttons: [CommandButton] = []
    var menuTitle: String? = nil
    var placing: String? = nil
    var placementValid = false
    var placementReason: String? = nil
    // Presentation extras.
    var faction: Faction = .humans
    var portrait: (type: Int, building: Bool, owner: Int, unit: Bool)? = nil
    var stats: [(symbol: String, value: String)] = []
    var tags: [String] = []
    /// Commander's guide: the suggested next step for new players (nil when there is nothing to suggest).
    var guide: String? = nil
    /// Tutorial: side-rail button to glow.
    var tutorialRail: String? = nil
    var siteOwners: [Int] = []
    var siteProgress: [Double] = []
    var tileHP: [Int: Double] = [:]
    var idleWorkers = 0
    var armyCount = 0
    var sides: [(faction: Faction, units: Int, value: Double, kills: Int, team: Int, defeated: Bool, name: String)] = []
}

@MainActor
final class GameController: ObservableObject {
    let settings: GameSettings
    let match: Match
    var world: World { match.world }
    let me = 0
    var data: GameData { world.data }

    @Published var hud = HUDState()
    @Published var toasts: [Toast] = []
    @Published var paused = false
    @Published var speed: Double = 1.0
    @Published var gameOver: (won: Bool, reason: String)? = nil
    @Published var showTech = false
    @Published var minimapVersion = 0
    /// Formation used for the player's group orders (cycled from the command card).
    var formation: Formation = .balanced

    var spectating = false
    var selection: [Int] = []
    var selectedSite: Int? = nil
    var mode: InputMode = .normal { didSet { if mode != .patrol { patrolFirst = nil }; refreshHUD() } }
    /// First point of a two-point patrol (set by the first tap in Patrol mode).
    var patrolFirst: (Double, Double)? = nil
    /// A worker's harvest / build / repair target, flashed with a ring as confirmation.
    /// Targets to flash with a ring: what workers were just sent to, or are busy with when selected.
    var targetPings: [Int] = []
    var buildMenu = false { didSet { refreshHUD() } }
    var ghostTile: (Int, Int)? = nil
    var controlGroups: [Int: [Int]] = [:]
    var accumulator = 0.0
    var lastHUD = 0.0
    var lastAttackAlert = -100.0
    var lastRes = [0, 0, 0]
    var incomeWindow: [(Double, [Int])] = []
    /// Camera hooks provided by the scene.
    var focusCamera: ((Double, Double) -> Void)?
    var cameraWorldRect: (() -> [(Double, Double)])?
    var attackPings: [(x: Double, y: Double, t: Double)] = []

    /// Resume a saved match exactly where it was left.
    init(resume m: Match, save: MatchSave) {
        var st = GameSettings()
        st.slots = save.factions.enumerated().map { PlayerSlot(faction: $0.element, team: m.world.teamOf[$0.offset]) }
        st.victory = m.world.config.victory
        st.layout = save.layout; st.seed = save.seed
        st.difficulty = save.extras["difficulty"].flatMap { Difficulty(rawValue: $0) } ?? .normal
        st.strategy = save.extras["strategy"].flatMap { AIStrategy(rawValue: $0) } ?? .balanced
        st.quick = save.extras["quick"] == "1"
        settings = st
        spectating = false
        match = m
        if let x = save.extras["camX"].flatMap(Double.init), let y = save.extras["camY"].flatMap(Double.init) {
            resumeCamera = (x, y, save.extras["zoom"].flatMap(Double.init) ?? 1.35)
        }
        if let g = save.extras["groups"]?.data(using: .utf8), let groups = try? JSONDecoder().decode([Int: [Int]].self, from: g) { controlGroups = groups }
        if let f = save.extras["formation"].flatMap({ Formation(rawValue: $0) }) { formation = f }
        guideDismissed = save.extras["guideDismissed"] == "1"
        lastAutosave = world.time
        refreshHUD()
        toast("Welcome back, commander")
    }

    // MARK: Save / resume

    var resumeCamera: (Double, Double, Double)? = nil
    /// The scene reports the camera (world x, y, zoom) for saves.
    var cameraState: (() -> (Double, Double, Double))? = nil
    var lastAutosave = 0.0
    var canSave: Bool { !spectating && !stressMode && !battleMode && !world.sandbox && gameOver == nil && tutorial == nil }

    func saveNow() {
        guard canSave else { return }
        var s = match.save()
        s.extras["difficulty"] = settings.difficulty.rawValue
        s.extras["strategy"] = settings.strategy.rawValue
        s.extras["quick"] = settings.quick ? "1" : "0"
        if let c = cameraState?() { s.extras["camX"] = String(c.0); s.extras["camY"] = String(c.1); s.extras["zoom"] = String(c.2) }
        if let g = try? JSONEncoder().encode(controlGroups), let gs = String(data: g, encoding: .utf8) { s.extras["groups"] = gs }
        s.extras["formation"] = formation.rawValue
        s.extras["guideDismissed"] = guideDismissed ? "1" : "0"
        SaveStore.write(s, info: SaveStore.Info(playerFaction: settings.playerFaction, aiFaction: settings.aiFaction, layout: settings.layout,
                                                difficulty: settings.difficulty.title + (settings.quick ? " · Quick" : ""), gameTime: world.time, savedAt: Date(),
                                                factions: settings.factions, teams: settings.teams))
        lastAutosave = world.time
    }

    var tutorial: TutorialState? = nil
    static let tutorialAuto = ProcessInfo.processInfo.arguments.contains("-tutorialauto")
    var autopilotTime = -10.0
    /// Leaves the tutorial (set by the app).
    var exitTutorial: (() -> Void)? = nil

    /// Boot Camp: Concord against a Lattice opponent that never attacks, with a little extra to spend.
    convenience init(tutorial: Bool) {
        var st = GameSettings()
        st.playerFaction = .humans; st.aiFaction = .machines; st.layout = .crossroads; st.seed = 42; st.difficulty = .easy
        self.init(settings: st, aiPlayers: false)
        self.tutorial = TutorialState()
        world.players[me].res[0] += 400; world.players[me].res[2] += 300
        refreshHUD()
    }

    convenience init(settings: GameSettings, spectate: Bool = false) { self.init(settings: settings, spectate: spectate, aiPlayers: true) }

    init(settings: GameSettings, spectate: Bool = false, aiPlayers: Bool) {
        self.settings = settings
        let cfg = MatchConfig(factions: settings.factions, teams: settings.teams, victory: settings.victory, layout: settings.layout,
                              seed: settings.seed, mapSize: settings.mapSize)
        var ai: [(player: Int, difficulty: Difficulty, strategy: AIStrategy)] = settings.slots.indices.dropFirst().map { (player: $0, difficulty: settings.difficulty, strategy: settings.strategy) }
        if spectate { ai.insert((0, settings.difficulty, .balanced), at: 0) }
        if !aiPlayers { ai = [] }
        spectating = spectate
        match = Match(config: cfg, ai: ai, data: settings.quick ? .quick : .shared)
        refreshHUD()
    }

    /// Renderer stress scenario: N units per side fighting mid-map with towers (development).
    func setupStress(_ perSide: Int) {
        world.sandbox = true
        world.unlockAll(0); world.unlockAll(1)
        var r = RNG(seed: 7)
        let mid = Double(world.map.size) / 2
        for p in 0..<2 {
            let pool = data.unitIDs(world.players[p].faction).filter { data.units[$0].role != "worker" && data.units[$0].role != "transport" }
            for _ in 0..<perSide {
                var x = mid + (p == 0 ? -12 : 12) + r.range(-8, 8), y = mid + r.range(-8, 8)
                if world.nav.isBlocked(Int(x), Int(y)) { let o = world.nav.nearestOpen(Int(x), Int(y)); x = Double(o.0) + 0.5; y = Double(o.1) + 0.5 }
                world.spawnUnit(pool[r.int(pool.count)], owner: p, x: x, y: y)
            }
        }
        for p in 0..<2 {
            world.commandMove(world.units(of: p).filter { !world.traits[$0.type].worker }.map { $0.id }, x: mid + (p == 0 ? 20 : -20), y: mid, attack: true)
        }
        stressMode = true
    }
    var stressMode = false
    var battleMode = false

    /// Staged combined-arms battle: N units per side in formation, attack-moving into each other.
    /// Composition per 50: front infantry/assault, anti-armor + AA second line, armor, siege at the rear, aircraft above.
    static let battleRoster: [Faction: [(String, Int)]] = [
        .humans: [("h_ranger", 13), ("h_breacher", 6), ("h_lancer", 6), ("h_skyguard", 4), ("h_medic", 3), ("h_buggy", 3), ("h_bastion", 4), ("h_mortar", 4), ("h_minelayer", 1), ("h_kestrel", 3), ("h_harrier", 3)],
        .machines: [("m_arc", 13), ("m_shockframe", 6), ("m_piercer", 6), ("m_flak", 4), ("m_repair", 3), ("m_runner", 3), ("m_bulwark", 4), ("m_coil", 4), ("m_suppress", 1), ("m_vector", 3), ("m_quake", 3)],
        .aliens: [("a_mantis", 13), ("a_ravager", 6), ("a_spinecaster", 6), ("a_needleback", 4), ("a_lifebinder", 3), ("a_skitter", 3), ("a_colossus", 4), ("a_rupturer", 4), ("a_seeder", 1), ("a_wisp", 3), ("a_blightwing", 3)],
    ]

    var battleSize = 50

    /// Development "unit lab" (`-lab`): the player's whole roster beside the HQ facing a held enemy line,
    /// with workers chopping, mining and repairing — for reviewing unit animation up close.
    var labFocus: (Double, Double)? = nil
    /// Building review (development): every building of the player's faction placed complete around the HQ,
    /// producers kept busy, and the camera on building number `focus` (the HQ is 0).
    func setupBuildLab(_ focus: Int) {
        world.sandbox = true
        world.unlockAll(me)
        guard let hq = world.buildings(of: me).first else { return }
        let f = world.players[me].faction
        var placed: [Entity] = [hq]
        let hx = Int(hq.x), hy = Int(hq.y)
        // Just the building under review (the HQ is always there), placed clear of the base.
        let ids = data.buildingIDs(f)
        let pick = ids[min(max(0, focus), ids.count - 1)]
        for t in [pick] where data.buildings[t].kind != .hq {
            search: for r in 8...24 {
                for k in 0..<(r * 6) {
                    let a = Double(k) / Double(r * 6) * 2 * .pi
                    let tx = hx + Int((cos(a) * Double(r)).rounded()), ty = hy + Int((sin(a) * Double(r)).rounded())
                    if world.placementError(me, t, tileX: tx, tileY: ty) == nil {
                        placed.append(world.spawnBuilding(t, owner: me, tileX: tx, tileY: ty, complete: true))
                        break search
                    }
                }
            }
        }
        for b in placed {
            for u in data.unitIDs(f) where world.commandTrain(b.id, unitType: u) == nil { break }
        }
        let target = placed.last!
        labFocus = (target.x, target.y)
    }

    func setupLab() {
        world.sandbox = true
        world.unlockAll(0); world.unlockAll(1)
        guard let hq = world.buildings(of: me).first else { return }
        let roster = data.unitIDs(world.players[me].faction).filter { data.units[$0].domain == .ground && data.units[$0].role != "worker" }
        // Open ground toward the map centre: our line, then the enemy line facing it across ~7 tiles.
        let mid = Double(world.map.size) / 2
        let dx = mid - hq.x, dy = mid - hq.y, dl = max(1, (dx * dx + dy * dy).squareRoot())
        let fx = dx / dl, fy = dy / dl, lx = -fy, ly = fx
        func spot(_ along: Double, _ side: Double) -> (Double, Double) {
            var (x, y) = (hq.x + fx * along + lx * side, hq.y + fy * along + ly * side)
            if world.nav.isBlocked(Int(x), Int(y)) { let o = world.nav.nearestOpen(Int(x), Int(y)); x = Double(o.0) + 0.5; y = Double(o.1) + 0.5 }
            return (x, y)
        }
        for (k, u) in roster.enumerated() {
            let (x, y) = spot(9 + Double(k / 6) * 1.8, (Double(k % 6) - 2.5) * 1.7)
            world.commandHold([world.spawnUnit(u, owner: me, x: x, y: y).id])
        }
        let foes = data.unitIDs(world.players[enemyPlayer].faction).filter { data.units[$0].domain == .ground && ["heavy", "assault", "infantry"].contains(data.units[$0].role) }
        for k in 0..<6 {
            let (x, y) = spot(17, (Double(k) - 2.5) * 1.7)
            world.commandHold([world.spawnUnit(foes[k % foes.count], owner: enemyPlayer, x: x, y: y).id])
        }
        labFocus = spot(12, 0)
        let workers = world.units(of: me).filter { world.traits[$0.type].worker }
        func nearest(_ k: ResourceKind) -> Entity? {
            world.entities.filter { $0.alive && $0.isResource && $0.type == k.rawValue }.min { dist2($0.x, $0.y, hq.x, hq.y) < dist2($1.x, $1.y, hq.x, hq.y) }
        }
        for (i, w) in workers.enumerated() {
            if i < 2, let n = nearest(.wood) { world.commandGather([w.id], node: n.id) }
            else if i < 4, let n = nearest(.iron) { world.commandGather([w.id], node: n.id) }
            else { hq.hp = hq.maxHp * 0.5; world.commandSmart([w.id], x: hq.x, y: hq.y, targetID: hq.id, player: me) }
        }
    }

    func setupBattle(_ perSide: Int) {
        battleSize = perSide
        world.sandbox = true
        world.clearAll()
        world.unlockAll(0); world.unlockAll(1)
        let mid = Double(world.map.size) / 2
        for p in 0..<2 {
            let f = world.players[p].faction
            let dir: Double = p == 0 ? -1 : 1
            var list: [Int] = []
            let roster = GameController.battleRoster[f]!
            for (id, n) in roster { list += Array(repeating: data.unitIndex[id]!, count: max(1, n * perSide / 50)) }
            while list.count > perSide { list.removeLast() }
            var k = 0
            while list.count < perSide { list.append(data.unitIndex[roster[k % 2].0]!); k += 1 }
            // Rank by role: front line closest to the enemy.
            func rank(_ u: Int) -> Int {
                switch data.units[u].role {
                case "assault", "fast": return 0
                case "infantry": return 1
                case "antiarmor", "antiair", "support", "denial": return 2
                case "heavy": return 3
                case "siege": return 5
                default: return 4
                }
            }
            let groups = Dictionary(grouping: list, by: rank)
            for (r, units) in groups {
                let cols = max(1, Int(Double(units.count).squareRoot() * 2.2))
                for (i, u) in units.enumerated() {
                    let row = i / cols, col = i % cols
                    let depth = 10 + Double(r) * 2.4 + Double(row) * 1.1
                    let x = mid + dir * depth
                    let y = mid + (Double(col) - Double(cols - 1) / 2) * 1.05
                    let e = world.spawnUnit(u, owner: p, x: x, y: y)
                    e.facing = p == 0 ? 0 : .pi
                }
            }
        }
        for p in 0..<2 {
            world.commandMove(world.units(of: p).map { $0.id }, x: mid + (p == 0 ? 14 : -14), y: mid, attack: true)
        }
        battleMode = true
    }

    /// Fast-forward the simulation (development / demo).
    func warp(seconds: Double) {
        world.collectEvents = false
        while world.time < seconds && world.winner == nil { match.step() }
        world.collectEvents = true
        world.events.removeAll()
    }

    // MARK: Simulation clock

    func advance(_ realDt: Double) {
        guard !paused, gameOver == nil else { return }
        accumulator += min(realDt, 0.25) * speed
        var steps = 0
        while accumulator >= world.dt && steps < 8 {
            match.step()
            accumulator -= world.dt
            steps += 1
        }
        processEvents()
        if world.time - lastHUD > 0.2 { lastHUD = world.time; refreshHUD() }
        if canSave && world.time - lastAutosave >= 60 { saveNow() }
        if world.winner != nil, gameOver == nil {
            let won = world.won(by: me) ?? false
            gameOver = (won, world.victoryReason)
            if !spectating { SaveStore.delete() }
            if won { Haptics.success() } else { Haptics.error() }
            SoundEngine.shared?.play(won ? "victory" : "defeat", at: nil, minGap: 0)
        }
    }

    var interpolation: Double { accumulator / world.dt }

    /// Events the renderer does not consume (toasts, alerts) are handled here; the scene reads the rest first.
    func processEvents() {
        for ev in world.events {
            switch ev {
            case .captured(let site, let owner):
                if owner == me { toast("Site captured") }
                else if world.isAlly(me, owner) { toast("\(world.players[owner].name) captured a site") }
                else { toast("Enemy captured a site", warning: true) }
                _ = site
            case .researched(let owner, let u):
                if owner == me { toast("Research complete: \(data.upgrades[u].name)"); Haptics.success() }
            case .built(let id):
                if let e = world.entity(id), e.owner == me { Haptics.tap() }
            case .message(let owner, let text):
                if owner == me { toast(text, warning: true) }
            default: break
            }
        }
        // Under-attack alerts.
        for e in world.entities where e.alive && e.owner == me && world.time - e.lastDamagedTime < 0.06 && !e.isMine {
            if world.time - lastAttackAlert > 12 {
                lastAttackAlert = world.time
                toasts.append(Toast(text: e.isBuilding ? "Your base is under attack — tap to view" : "Your forces are under attack — tap to view", time: Date(), warning: true, at: (e.x, e.y)))
                if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
                Haptics.warning()
                attackPings.append((e.x, e.y, world.time))
            }
            break
        }
        attackPings.removeAll { world.time - $0.t > 6 }
    }

    /// Commander's guide: on for Easy matches (and whenever enabled in settings) until dismissed.
    var guideDismissed = false
    var guideOn: Bool {
        guard !guideDismissed else { return false }
        return settings.difficulty == .easy || (UserDefaults.standard.object(forKey: "guide.on") as? Bool ?? false)
    }

    /// The next useful thing for a new player to do, in plain words.
    func guideStep() -> String? {
        let f = world.players[me].faction
        let units = world.units(of: me).filter { !$0.isMine }
        let workers = units.filter { world.traits[$0.type].worker }.count
        let army = units.count - workers
        let blds = world.buildings(of: me)
        let barracksID = data.buildingIDs(f).first { data.buildings[$0].kind == .infantry }
        let barracks = barracksID.map { data.buildings[$0].name } ?? "barracks"
        let hasBarracks = blds.contains { world.bdef($0).kind == .infantry }
        let workerName = data.unitIDs(f).first { data.units[$0].role == "worker" }.map { data.units[$0].name } ?? "worker"
        let sites = world.sites.filter { $0.owner == me && $0.control >= 1 }.count
        if workers < 8 { return "Train more \(workerName)s: tap your HQ, then the \(workerName) button. More workers means more resources." }
        if !hasBarracks { return "Build a \(barracks): select a worker, tap Build, choose the \(barracks), place it, then Confirm." }
        if army < 4 { return "Train soldiers at your \(barracks) so you can defend your base." }
        if sites == 0 { return "Capture a site: tap Army, then tap one of the glowing platforms on the map." }
        if army < 12 { return "Keep growing your army. Tap Army any time to select every soldier." }
        if world.time > 360 { return "Attack! Tap Army, then Attack-Move, then tap toward the enemy base." }
        return nil
    }

    func toast(_ s: String, warning: Bool = false) {
        toasts.append(Toast(text: s, time: Date(), warning: warning))
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
    }

    func pruneToasts() {
        let now = Date()
        let kept = toasts.filter { now.timeIntervalSince($0.time) < 4 }
        if kept.count != toasts.count { toasts = kept }
    }

    // MARK: Selection

    var selectedEntities: [Entity] { selection.compactMap { world.entity($0) } }

    func select(_ ids: [Int]) {
        selection = ids.filter { world.entity($0) != nil }
        // Selecting workers shows what they're busy with: a ring flashes on each job (a few at most).
        var jobs: [Int] = []
        for e in selectedEntities where e.isUnit && world.traits[e.type].worker {
            let job = e.order == .gather || e.order == .returnCargo ? e.gatherNode : (e.order == .build || e.order == .repair ? e.orderTarget : -1)
            if job >= 0, !jobs.contains(job) { jobs.append(job) }
            if jobs.count >= 3 { break }
        }
        targetPings += jobs
        selectedSite = nil
        buildMenu = false
        if case .place = mode { mode = .normal }
        mode = .normal
        refreshHUD()
        if !ids.isEmpty { chatter(.select) }
    }

    // MARK: Radio chatter

    let radio = Radio()

    /// The unit that speaks for a selection (and whose face is shown): the most expensive one.
    func leadUnit(_ ents: [Entity]) -> Entity? {
        ents.filter { $0.isUnit }.max { a, b in
            let ca = data.units[a.type].cost, cb = data.units[b.type].cost
            return (ca.iron + ca.wood + ca.gold * 2, b.id) < (cb.iron + cb.wood + cb.gold * 2, a.id)
        }
    }

    func chatter(_ kind: Radio.Kind) {
        guard !spectating, !battleMode, !stressMode, let lead = leadUnit(selectedEntities), lead.owner == me else { return }
        var k = kind
        if kind == .select && selection.count == 1 && lead.hp < lead.maxHp * 0.35 { k = .hurt }
        radio.chatter(k, unit: data.units[lead.type], type: lead.type, faction: world.players[me].faction)
    }

    func selectSite(_ i: Int) {
        selection = []; selectedSite = i; buildMenu = false; mode = .normal; refreshHUD()
    }

    func clearSelection() { select([]) }

    /// Pick the best entity at a world point (units over buildings over resources), honoring fog.
    func pick(_ x: Double, _ y: Double, radius: Double) -> Entity? {
        var best: Entity? = nil
        var bd = Double.infinity
        for e in world.entities where e.alive && e.onMap && !e.isMine {
            if e.owner != me && e.owner >= 0 && !isShown(e) { continue }
            var d: Double
            if e.isBuilding {
                let s = Double(e.size)
                if x >= Double(e.tileX) - 0.3 && x <= Double(e.tileX) + s + 0.3 && y >= Double(e.tileY) - 0.3 && y <= Double(e.tileY) + s + 0.3 { d = 0.5 } else { continue }
            } else if e.isResource {
                if !world.players[me].explored[world.tileIndex(e.x, e.y)] { continue }
                // Hit-test the drawn sprite (trees and ore stand up from their base), in screen points.
                let dx = x - e.x, dy = y - e.y
                let sx = 32 * (dx + dy), sy = 16 * (dy - dx)
                let pad = 10 + (radius - 0.7) * 24
                let half = (e.type == ResourceKind.wood.rawValue ? 20.0 : 26.0) + pad
                let top = (e.type == ResourceKind.wood.rawValue ? 66.0 : (e.type == ResourceKind.iron.rawValue ? 40.0 : 50.0)) + pad
                guard abs(sx) <= half, sy >= -12 - pad, sy <= top else { continue }
                d = hypot(sx, sy - top * 0.35) / 200   // always within the pick radius once inside the sprite
            } else {
                // Sprites stand up-screen from their feet (air units much higher); test against the drawn body.
                let lift = e.isAir ? 0.75 : 0.25
                d = dist2(x, y, e.x - lift, e.y + lift).squareRoot() - e.radius * 0.5 - (e.owner == me ? 0.2 : 0)
            }
            if d < radius && d < bd { bd = d; best = e }
        }
        return best
    }

    /// Nearest explored resource node to a point (by its sprite, so taps on tree tops count).
    func pickResource(_ x: Double, _ y: Double, within r: Double) -> Entity? {
        var best: Entity? = nil, bd = r * r
        for e in world.entities where e.alive && e.isResource && world.players[me].explored[world.tileIndex(e.x, e.y)] {
            let lift = e.type == ResourceKind.wood.rawValue ? 0.8 : 0.5   // visual centre sits up-screen from the base
            let d = dist2(x, y, e.x - lift, e.y + lift)
            if d < bd { bd = d; best = e }
        }
        return best
    }

    /// Nearest of the player's own units to a point (by the drawn body, which stands up-screen of the feet).
    func pickOwnUnit(_ x: Double, _ y: Double, within r: Double) -> Entity? {
        var best: Entity? = nil, bd = r * r
        for e in world.entities where e.alive && e.onMap && e.isUnit && !e.isMine && e.owner == me {
            let lift = e.isAir ? 0.75 : 0.3
            let d = dist2(x, y, e.x - lift, e.y + lift)
            if d < bd { bd = d; best = e }
        }
        return best
    }

    /// Nearest visible enemy unit or structure to a point (sprite centre, so taps on the body count).
    func pickEnemy(_ x: Double, _ y: Double, within r: Double) -> Entity? {
        var best: Entity? = nil, bd = r * r
        for e in world.entities where e.alive && e.onMap && !e.isMine && !e.isResource && world.isEnemyPublic(me, e.owner) && isShown(e) && !world.isCloaked(e) {
            let lift = e.isAir ? 0.75 : (e.isBuilding ? Double(e.size) * 0.3 : 0.25)
            let d = dist2(x, y, e.x - lift, e.y + lift) - (e.isBuilding ? Double(e.size * e.size) * 0.25 : 0)
            if d < bd { bd = d; best = e }
        }
        return best
    }

    func pickSite(_ x: Double, _ y: Double) -> Int? {
        for (i, s) in world.sites.enumerated() where dist2(s.x, s.y, x, y) < 2.2 * 2.2 { return i }
        return nil
    }

    /// Fog check used for drawing and picking enemy objects.
    var seenBuildings = Set<Int>()
    func isShown(_ e: Entity) -> Bool {
        if e.owner == me || e.owner < 0 || spectating { return true }
        if world.canSee(me, e) {
            if e.isBuilding { seenBuildings.insert(e.id) }
            return true
        }
        return e.isBuilding && seenBuildings.contains(e.id)
    }

    func selectBox(_ a: (Double, Double), _ b: (Double, Double), screenRect: Bool = true, corners: [(Double, Double)]? = nil) {
        // corners: world-space quad of the screen-space rectangle.
        guard let c = corners else { return }
        func inside(_ x: Double, _ y: Double) -> Bool {
            var sign = 0.0
            for i in 0..<4 {
                let (x1, y1) = c[i], (x2, y2) = c[(i + 1) % 4]
                let cr = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
                if cr != 0 { if sign == 0 { sign = cr } else if (cr > 0) != (sign > 0) { return false } }
            }
            return true
        }
        var units = world.entities.filter { $0.isUnit && $0.onMap && !$0.isMine && $0.owner == me && inside($0.x, $0.y) }
        // Prefer army over workers when both are boxed.
        if units.contains(where: { !world.traits[$0.type].worker }) { units.removeAll { world.traits[$0.type].worker } }
        if !units.isEmpty { select(units.map { $0.id }) }
    }

    func selectSameType(as e: Entity, visibleOnly corners: [(Double, Double)]?) {
        guard e.owner == me else { return }
        let all = world.entities.filter { $0.alive && $0.onMap && !$0.isMine && $0.owner == me && $0.kind == e.kind && $0.type == e.type }
        select(all.map { $0.id })
    }

    func selectArmy() {
        select(world.units(of: me).filter { !world.traits[$0.type].worker && !$0.isMine }.map { $0.id })
    }

    func selectWorkers() {
        select(world.units(of: me).filter { world.traits[$0.type].worker }.map { $0.id })
    }

    func selectIdleWorker() {
        let idle = world.units(of: me).filter { world.traits[$0.type].worker && $0.order == .idle }
        if let w = idle.first { select([w.id]); focusCamera?(w.x, w.y) } else { toast("No idle workers") }
    }

    func groupAssign(_ n: Int) { controlGroups[n] = selection; toast("Group \(n) assigned") }
    func groupRecall(_ n: Int) {
        guard let g = controlGroups[n] else { return }
        let alive = g.filter { world.entity($0) != nil }
        if selection == alive, let f = alive.compactMap({ world.entity($0) }).first { focusCamera?(f.x, f.y) }
        select(alive)
    }

    // MARK: Map interaction

    /// Tap / left click on the map.
    func tap(worldX x: Double, y: Double, zoom: Double) {
        let r = 0.7 * max(1, zoom * 0.8)
        switch mode {
        case .place(let type):
            let s = data.buildings[type].size
            ghostTile = (Int(x - Double(s) / 2 + 0.5), Int(y - Double(s) / 2 + 0.5))
            refreshHUD()
            return
        case .patrol:
            // Two taps: the first and second patrol points.
            let ids = myUnitSelection()
            guard let a = patrolFirst else {
                patrolFirst = (x, y)
                commandPing = (x, y, false, world.time)
                refreshHUD()
                return
            }
            world.commandPatrol(ids, from: a, to: (x, y), formation: formation)
            commandPing = (x, y, false, world.time)
            mode = .normal
            return
        case .attackMove:
            let ids = myUnitSelection()
            if let t = pick(x, y, radius: r), world.isEnemyPublic(me, t.owner) { world.commandAttack(ids, target: t.id) }
            else { world.commandMove(ids, x: x, y: y, attack: true, formation: formation) }
            mode = .normal
            return
        case .unload:
            for e in selectedEntities where world.traits[e.type].capacity > 0 { world.commandUnload(e.id, x: x, y: y) }
            mode = .normal; return
        case .emp:
            world.commandEMP(selection, x: x, y: y); mode = .normal; return
        case .rally:
            for e in selectedEntities where e.isBuilding { world.setRally(e.id, x: x, y: y) }
            mode = .normal; toast("Rally point set"); return
        case .normal: break
        }
        var hit = pick(x, y, radius: r)
        // Workers selected: a tap on (or right next to) a resource node means "harvest", even if another unit is closer.
        let workersSelected = !selection.isEmpty && selectedEntities.allSatisfy { $0.isUnit && world.traits[$0.type].worker }
        if workersSelected, hit == nil {
            if let node = pickResource(x, y, within: max(1.4, r * 1.6)) { hit = node }
        }
        // Combat units selected: a tap on (or close to) a visible enemy means "attack it".
        let fighters = selectedEntities.contains { $0.isUnit && $0.owner == me && !world.traits[$0.type].worker }
        if fighters, hit == nil || (hit!.owner != me && !world.isEnemyPublic(me, hit!.owner)) {
            if let foe = pickEnemy(x, y, within: max(1.3, r * 1.7)) { hit = foe }
        }
        // A near miss on one of your own units selects it rather than ordering a move.
        if hit == nil, let own = pickOwnUnit(x, y, within: 0.6 * max(1, zoom * 0.8)) { hit = own }
        if let h = hit, h.owner == me {
            // Tapping own stuff: select it (transport + selected units => load handled via smart command).
            if !selection.isEmpty && !h.isBuilding && world.traits[h.type].capacity > 0 && selectedEntities.contains(where: { $0.isUnit && !$0.isAir && $0.id != h.id }) {
                command(at: x, y: y, target: h); return
            }
            if !selection.isEmpty && selectedEntities.allSatisfy({ $0.isUnit && world.traits[$0.type].worker }) && h.isBuilding && (!h.complete || h.hp < h.maxHp) {
                command(at: x, y: y, target: h); return
            }
            select([h.id]); return
        }
        if selection.isEmpty || !selectedEntities.contains(where: { $0.owner == me }) {
            if let h = hit { select([h.id]); return }
            if let s = pickSite(x, y) { selectSite(s); return }
            clearSelection(); return
        }
        command(at: x, y: y, target: hit)
    }

    /// Right click / tap with a selection: contextual order.
    func command(at x: Double, y: Double, target: Entity?) {
        guard !selection.isEmpty else { return }
        if selectedEntities.allSatisfy({ $0.isBuilding }) {
            // Rally on a resource (or right beside one): new workers go straight to gathering it.
            let node = target.flatMap { $0.isResource ? $0 : nil } ?? pickResource(x, y, within: 1.2)
            if let n = node {
                for e in selectedEntities { world.setRally(e.id, x: n.x, y: n.y) }
                targetPings.append(n.id)
                let kind = ["Iron", "Gold", "Wood"][n.type]
                toast("Rally set: new workers will gather \(kind)")
            } else {
                for e in selectedEntities { world.setRally(e.id, x: x, y: y) }
                toast("Rally point set")
            }
            return
        }
        world.commandSmart(selection, x: x, y: y, targetID: target?.id, player: me, formation: formation)
        if let t = target, selectedEntities.contains(where: { $0.isUnit && world.traits[$0.type].worker }),
           t.isResource || (t.owner == me && t.isBuilding && (!t.complete || t.hp < t.maxHp)) {
            targetPings.append(t.id)
        } else if let t = target, world.isEnemyPublic(me, t.owner) {
            targetPings.append(t.id)
        }
        commandPing = (x, y, target.map { world.isEnemyPublic(me, $0.owner) } ?? false, world.time)
    }
    var commandPing: (Double, Double, Bool, Double)? = nil {
        didSet { if let c = commandPing { chatter(c.2 ? .attack : .move) } }
    }

    func myUnitSelection() -> [Int] { selectedEntities.filter { $0.isUnit && $0.owner == me }.map { $0.id } }

    // Building placement.
    func moveGhost(worldX x: Double, y: Double) {
        guard case .place(let type) = mode else { return }
        let s = data.buildings[type].size
        ghostTile = (Int(x - Double(s) / 2 + 0.5), Int(y - Double(s) / 2 + 0.5))
        refreshHUD()
    }

    func confirmPlacement() {
        guard case .place(let type) = mode, let g = ghostTile else { return }
        // Every selected worker goes to help build it.
        let workers = selectedEntities.filter { $0.isUnit && $0.owner == me && world.traits[$0.type].worker }
        if let err = world.commandBuild(workers.map { $0.id }, type: type, tileX: g.0, tileY: g.1) {
            toast(err, warning: true)
        } else {
            mode = .normal
            ghostTile = nil
            buildMenu = false
        }
    }

    func cancelMode() { mode = .normal; ghostTile = nil; buildMenu = false }

    // MARK: HUD

    func refreshHUD() {
        var h = HUDState()
        let p = world.players[me]
        h.guide = guideOn && !spectating && tutorial == nil ? guideStep() : nil
        if tutorial != nil {
            tutorialTick(); h.tutorialRail = tutorialStep?.rail
            if GameController.tutorialAuto && world.time - autopilotTime >= 1 { autopilotTime = world.time; tutorialAutopilot() }
        }
        h.res = p.res
        h.units = p.unitCount
        h.cap = data.rules.combat.unitCap
        h.time = world.time
        h.sitesTotal = world.sites.count
        h.sitesOwned = world.sites.filter { $0.owner == me && $0.control >= 1 }.count
        h.sitesAllied = world.sitesHeld(team: p.team) - h.sitesOwned
        h.sitesEnemy = world.sites.filter { $0.owner >= 0 && world.isEnemy(me, $0.owner) && $0.control >= 1 }.count
        h.dominanceNeed = world.dominanceRequirement
        h.dominanceMode = world.config.victory == .dominance
        h.myDominance = p.dominanceTimer
        h.enemyDominance = world.players.filter { world.isEnemy(me, $0.index) }.map { $0.dominanceTimer }.max() ?? 0
        h.dominanceSeconds = data.rules.territory.dominanceSeconds
        h.dominanceActive = h.dominanceMode && world.time >= data.rules.territory.dominanceStart
        // Income per minute from a sliding window.
        incomeWindow.append((world.time, p.stats.gathered.enumerated().map { $0.element + Int(p.stats.territoryIncome[$0.offset]) }))
        incomeWindow.removeAll { world.time - $0.0 > 60 }
        if let first = incomeWindow.first, let last = incomeWindow.last, last.0 - first.0 > 5 {
            let span = last.0 - first.0
            h.income = (0..<3).map { Double(last.1[$0] - first.1[$0]) / span * 60 }
        }
        h.faction = p.faction
        h.sides = world.players.map { pl in
            var n = 0, v = 0.0
            for e in world.entities where e.isUnit && e.alive && !e.isMine && e.owner == pl.index && !world.traits[e.type].worker {
                n += 1; v += data.units[e.type].cost.value(data.rules.economy) * e.hp / max(1, e.maxHp)
            }
            return (pl.faction, n, v, pl.stats.kills, pl.team, pl.defeated, pl.name)
        }
        h.siteOwners = world.sites.map { $0.control >= 1 ? $0.owner : -1 }
        h.siteProgress = world.sites.map { $0.owner >= 0 ? $0.control : ($0.capturer >= 0 ? -$0.control : 0) }
        let mine = world.units(of: me)
        h.idleWorkers = mine.filter { world.traits[$0.type].worker && $0.order == .idle }.count
        h.armyCount = mine.filter { !world.traits[$0.type].worker && !$0.isMine }.count
        describeSelection(&h)
        h.buttons = buildButtons(&h)
        if let want = tutorialStep?.button(self) { for i in h.buttons.indices where h.buttons[i].id == want { h.buttons[i].glow = true } }
        if case .place(let t) = mode {
            h.placing = data.buildings[t].name
            if let g = ghostTile {
                h.placementReason = world.placementError(me, t, tileX: g.0, tileY: g.1)
                if h.placementReason == nil { h.placementReason = shortfall(world.buildingCost(me, t)) }
                h.placementValid = h.placementReason == nil
            } else { h.placementReason = "Tap the map to position" }
        }
        hud = h
        pruneToasts()
    }

    func describeSelection(_ h: inout HUDState) {
        if let si = selectedSite {
            let s = world.sites[si]
            h.selectionTitle = "Strategic Site"
            let owner = s.owner < 0 ? "Neutral" : (s.owner == me ? "Yours" : (world.isAlly(me, s.owner) ? "Allied" : "Enemy"))
            h.selectionSubtitle = "\(owner) · control \(Int(s.control * 100))%" + (s.contested ? " · CONTESTED" : "")
            let tr = data.rules.territory
            let f = world.players[me].faction
            let perk: String
            switch f {
            case .humans: perk = "Forward logistics: drop-off point, repairs units within \(Int(tr.humanStagingRadius)) tiles"
            case .machines: perk = "Network node: links machines within \(Int(tr.machineNodeRadius)) tiles"
            case .aliens: perk = "Bloom: regeneration and +\(Int(tr.alienSpeedBonus * 100))% speed within \(Int(tr.alienBloomRadius)) tiles"
            }
            h.selectionDetail = "Income +\(fmt(tr.income[0] * 60))/\(fmt(tr.income[1] * 60))/\(fmt(tr.income[2] * 60)) iron/gold/wood per min. Vision \(Int(tr.vision)). \(perk). Installation: \(s.installation.title)."
            return
        }
        let ents = selectedEntities
        h.selectionCount = ents.count
        guard let first = ents.first else { return }
        if ents.count == 1 {
            let e = first
            h.selectionHP = (e.hp, e.maxHp)
            h.portrait = (e.type, e.isBuilding, e.owner, e.isUnit)
            if e.isUnit {
                let d = world.udef(e)
                h.stats = [("shield.fill", fmt(world.armor(e))), ("hare.fill", fmt(world.speed(e)))]
                if let w = world.weapon(e) {
                    h.stats.insert(("burst.fill", "\(fmt(w.damage))/\(fmt(w.interval))s"), at: 0)
                    h.stats.insert(("scope", fmt(w.range) + (w.ground && w.air ? " G+A" : (w.air ? " AIR" : " GND"))), at: 1)
                }
                if e.linked { h.tags.append("LINKED") }
                if e.inBloom { h.tags.append("IN BLOOM") }
                if e.supplied { h.tags.append("SUPPLIED") }
                if world.isCloaked(e) { h.tags.append("CLOAKED") }
                if let m = world.modeName(e) { h.tags.append(m.uppercased()) }
                h.selectionTitle = d.name
                var sub = "\(world.players[e.owner].faction == .humans ? "Concord" : world.players[e.owner].faction == .machines ? "Lattice" : "Brood") · \(d.role.capitalized)"
                if let m = world.modeName(e) { sub += " · \(m)" }
                if e.linked { sub += " · LINKED" }
                if e.inBloom { sub += " · IN BLOOM" }
                if e.supplied { sub += " · SUPPLIED" }
                if !e.cargo.isEmpty { sub += " · cargo \(e.cargo.count)" }
                h.selectionSubtitle = sub
                var det = "Armor \(fmt(world.armor(e)))  Speed \(fmt(world.speed(e)))"
                if let w = world.weapon(e) {
                    det += "  Dmg \(fmt(w.damage)) / \(fmt(w.interval))s  Range \(fmt(w.range))"
                    det += w.ground && w.air ? "  [G+A]" : (w.air ? "  [Air]" : "  [Ground]")
                }
                det += "\n" + d.description + "\nStrong vs: \(d.strongVs)  Weak vs: \(d.weakVs)"
                if e.carryAmount > 0 { det = "Carrying \(e.carryAmount) \(e.carryKind.name)\n" + det }
                h.selectionDetail = det
            } else if e.isBuilding {
                let d = world.bdef(e)
                if let w = world.weapon(e) { h.stats = [("burst.fill", fmt(w.damage)), ("scope", fmt(w.range))] }
                h.stats.append(("shield.fill", fmt(world.armor(e))))
                if e.linked { h.tags.append("LINKED") }
                h.selectionTitle = d.name
                h.selectionSubtitle = e.complete ? (world.modeName(e).map { "Mode: \($0)" } ?? d.kind.rawValue.capitalized) : "Under construction \(Int(e.buildProgress * 100))%"
                var det = d.description
                if let w = world.weapon(e) { det = "Dmg \(fmt(w.damage))  Range \(fmt(w.range))" + (e.linked ? " (network linked)" : "") + "\n" + det }
                h.selectionDetail = det
                h.queue = e.queue.enumerated().map { i, q in
                    QueueEntry(id: i, title: q.isUpgrade ? data.upgrades[q.index].name : data.units[q.index].name,
                               progress: i == 0 ? 1 - q.remaining / q.total : 0, isUpgrade: q.isUpgrade)
                }
            } else {
                let k = ResourceKind(rawValue: e.type)!
                h.selectionTitle = k == .wood ? "Timber Grove" : (k == .iron ? "Iron Deposit" : "Gold Vein")
                h.selectionSubtitle = "\(e.amount) \(k.name) remaining"
                h.selectionHP = nil
            }
        } else {
            var counts: [Int: Int] = [:]
            var typeHP: [Int: (Double, Double)] = [:]
            for e in ents where e.isUnit {
                counts[e.type, default: 0] += 1
                let o = typeHP[e.type] ?? (0, 0); typeHP[e.type] = (o.0 + e.hp, o.1 + e.maxHp)
            }
            h.tileHP = typeHP.mapValues { $0.0 / max(1, $0.1) }
            if let lead = leadUnit(ents) { h.portrait = (lead.type, false, lead.owner, true) }
            h.selectionTitle = "\(ents.count) selected"
            h.selectionIcons = counts.sorted { $0.value > $1.value }.map { (type: $0.key, count: $0.value, building: false) }
            let hp = ents.reduce(0) { $0 + $1.hp }, mx = ents.reduce(0) { $0 + $1.maxHp }
            h.selectionHP = (hp, mx)
            h.selectionSubtitle = counts.sorted { $0.value > $1.value }.prefix(4).map { "\($0.value)× \(data.units[$0.key].name)" }.joined(separator: ", ")
        }
    }

    /// What's missing to afford something, e.g. "Need 30 more iron, 20 wood"; nil when affordable.
    func shortfall(_ c: Cost) -> String? {
        let r = world.players[me].res
        var parts: [String] = []
        if c.iron > r[0] { parts.append("\(c.iron - r[0]) more iron") }
        if c.wood > r[2] { parts.append("\(c.wood - r[2]) wood") }
        if c.gold > r[1] { parts.append("\(c.gold - r[1]) gold") }
        return parts.isEmpty ? nil : "Need " + parts.joined(separator: ", ")
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    func buildButtons(_ h: inout HUDState) -> [CommandButton] {
        let p = world.players[me]
        var b: [CommandButton] = []
        if case .place = mode {
            h.menuTitle = "Place building"
            b.append(CommandButton(id: "confirm", title: "Confirm", symbol: "checkmark.circle.fill", enabled: h.placementValid || ghostTile != nil, hotkey: "\r") { [weak self] in self?.confirmPlacement() })
            b.append(CommandButton(id: "cancel", title: "Cancel", symbol: "xmark.circle", hotkey: "\u{1b}") { [weak self] in self?.cancelMode() })
            return b
        }
        if mode != .normal {
            h.menuTitle = { switch mode { case .attackMove: return "Attack-move: tap target"; case .patrol: return patrolFirst == nil ? "Patrol: tap first point" : "Patrol: tap second point"; case .unload: return "Unload: tap point"; case .emp: return "EMP: tap target"; case .rally: return "Rally: tap point"; default: return "" } }()
            b.append(CommandButton(id: "cancel", title: "Cancel", symbol: "xmark.circle", hotkey: "\u{1b}") { [weak self] in self?.cancelMode() })
            return b
        }
        if let si = selectedSite {
            let s = world.sites[si]
            if s.owner == me && s.control >= 1 && s.installation == .none {
                h.menuTitle = "Configure installation"
                let c = data.rules.territory.installCost
                let items: [(Installation, String, String)] = [(.extractor, "Extractor", "shippingbox.fill"), (.watchpost, "Watchpost", "eye.fill"), (.bulwark, "Bulwark", "shield.lefthalf.filled")]
                for (inst, title, sym) in items {
                    b.append(CommandButton(id: "inst\(inst.rawValue)", title: title, symbol: sym, cost: c, enabled: p.canAfford(c), reason: shortfall(c)) { [weak self] in
                        guard let self = self else { return }
                        if let err = self.world.configureSite(si, player: self.me, installation: inst) { self.toast(err, warning: true) }
                        self.refreshHUD()
                    })
                }
            }
            return b
        }
        let ents = selectedEntities.filter { $0.owner == me }
        guard !ents.isEmpty else { return b }

        // Single own building: production + research.
        if ents.count == 1, let e = ents.first, e.isBuilding {
            let d = world.bdef(e)
            if !e.complete {
                b.append(CommandButton(id: "cancelBuild", title: "Cancel", symbol: "xmark.octagon", hotkey: "\u{1b}") { [weak self] in
                    self?.world.commandCancelConstruction(e.id); self?.clearSelection() })
                return b
            }
            for u in data.unitIDs(p.faction) where data.units[u].producedAt == d.kind {
                let ud = data.units[u]
                let reason = world.unitAvailability(me, u) ?? shortfall(ud.cost)
                let q = e.queue.filter { !$0.isUpgrade && $0.index == u }.count
                let prog: Double? = e.queue.first.flatMap { !$0.isUpgrade && $0.index == u ? 1 - $0.remaining / $0.total : nil }
                b.append(CommandButton(id: "u\(u)", title: ud.name, symbol: "unit:\(u)", cost: ud.cost, enabled: reason == nil, reason: reason,
                                       badge: ud.batch.map { "×\($0)" }, progress: prog, queued: q,
                                       detail: "\(ud.role.capitalized) · strong vs \(ud.strongVs)") { [weak self] in
                    guard let self = self else { return }
                    if let err = self.world.commandTrain(e.id, unitType: u) { self.toast(err, warning: true) }
                    self.refreshHUD()
                })
            }
            for g in data.upgradeIDs(p.faction) where data.upgrades[g].researchedAt == d.kind {
                let gd = data.upgrades[g]
                if p.completedUpgrades.contains(g) { continue }
                let reason = world.upgradeAvailability(me, g) ?? shortfall(gd.cost)
                let gp: Double? = e.queue.first.flatMap { $0.isUpgrade && $0.index == g ? 1 - $0.remaining / $0.total : nil }
                b.append(CommandButton(id: "g\(g)", title: gd.name, symbol: "upgrade:\(gd.tier)", cost: gd.cost, enabled: reason == nil, reason: reason,
                                       highlighted: p.researching.contains(g), progress: gp, detail: gd.description) { [weak self] in
                    guard let self = self else { return }
                    if let err = self.world.commandResearch(e.id, upgrade: g) { self.toast(err, warning: true) }
                    self.refreshHUD()
                })
            }
            if world.modeName(e) != nil {
                b.append(CommandButton(id: "mode", title: "Mode: \(world.modeName(e)!)", symbol: "dial.medium", hotkey: "m") { [weak self] in
                    self?.world.commandToggleMode([e.id]); self?.refreshHUD() })
            }
            if [.infantry, .heavy, .air, .hq].contains(d.kind) {
                b.append(CommandButton(id: "rally", title: "Rally", symbol: "flag.fill", hotkey: "r") { [weak self] in self?.mode = .rally })
            }
            return b
        }

        let units = ents.filter { $0.isUnit }
        let workers = units.filter { world.traits[$0.type].worker }
        if buildMenu && !workers.isEmpty {
            h.menuTitle = "Construct"
            for t in data.buildingIDs(p.faction) {
                let bd = data.buildings[t]
                let cost = world.buildingCost(me, t)
                let miss = p.missing(bd.requires, data)
                let reason = !miss.isEmpty ? "Requires " + miss.joined(separator: ", ") : shortfall(cost)
                b.append(CommandButton(id: "b\(t)", title: bd.name, symbol: "building:\(t)", cost: cost, enabled: reason == nil, reason: reason,
                                       detail: bd.description) { [weak self] in
                    guard let self = self else { return }
                    self.mode = .place(t)
                    // Start the ghost in front of the camera centre.
                    if let c = self.cameraWorldRect?() {
                        let cx = c.reduce(0) { $0 + $1.0 } / 4, cy = c.reduce(0) { $0 + $1.1 } / 4
                        self.moveGhost(worldX: cx, y: cy)
                    }
                })
            }
            b.append(CommandButton(id: "back", title: "Back", symbol: "chevron.left", hotkey: "\u{1b}") { [weak self] in self?.buildMenu = false })
            return b
        }
        guard !units.isEmpty else { return b }
        b.append(CommandButton(id: "amove", title: "Attack-Move", symbol: "scope", hotkey: "a") { [weak self] in self?.mode = .attackMove })
        b.append(CommandButton(id: "stop", title: "Stop", symbol: "stop.fill", hotkey: "s") { [weak self] in
            guard let self = self else { return }; self.world.commandStop(self.selection) })
        b.append(CommandButton(id: "hold", title: "Hold", symbol: "hand.raised.fill", hotkey: "h") { [weak self] in
            guard let self = self else { return }; self.world.commandHold(self.selection) })
        b.append(CommandButton(id: "patrol", title: "Patrol", symbol: "arrow.triangle.2.circlepath", hotkey: "p") { [weak self] in self?.mode = .patrol })
        if units.filter({ !world.traits[$0.type].worker }).count >= 4 {
            let sym: String = { switch formation { case .balanced: return "square.grid.3x2.fill"; case .assault: return "arrowtriangle.up.fill"; case .defensive: return "shield.lefthalf.filled" } }()
            b.append(CommandButton(id: "formation", title: formation.title, symbol: sym, hotkey: "f") { [weak self] in
                guard let self = self else { return }
                let all = Formation.allCases
                self.formation = all[(all.firstIndex(of: self.formation)! + 1) % all.count]
                self.toast("Formation: \(self.formation.title)")
                self.refreshHUD()
            })
        }
        if !workers.isEmpty {
            b.append(CommandButton(id: "build", title: "Build", symbol: "hammer.fill", hotkey: "b") { [weak self] in self?.buildMenu = true })
        }
        if units.contains(where: { world.traits[$0.type].modes > 0 }) {
            let names = Set(units.compactMap { world.modeName($0) })
            b.append(CommandButton(id: "mode", title: names.count == 1 ? names.first! : "Toggle Mode", symbol: "dial.medium", hotkey: "m") { [weak self] in
                guard let self = self else { return }; self.world.commandToggleMode(self.selection); self.refreshHUD() })
        }
        if units.contains(where: { world.traits[$0.type].emp }) {
            let ready = units.contains { world.traits[$0.type].emp && $0.abilityCooldown <= 0 }
            b.append(CommandButton(id: "emp", title: "EMP", symbol: "bolt.circle.fill", enabled: ready, reason: ready ? nil : "Recharging", hotkey: "e") { [weak self] in self?.mode = .emp })
        }
        if units.contains(where: { world.traits[$0.type].capacity > 0 && !$0.cargo.isEmpty }) {
            b.append(CommandButton(id: "unload", title: "Unload", symbol: "arrow.down.to.line", hotkey: "u") { [weak self] in self?.mode = .unload })
        }
        return b
    }

    // MARK: Minimap data

    func minimapDots() -> [(x: Double, y: Double, owner: Int, building: Bool)] {
        var out: [(Double, Double, Int, Bool)] = []
        for e in world.entities where e.alive && e.onMap && !e.isMine && e.kind != .resource {
            if e.owner != me && !isShown(e) { continue }
            out.append((e.x, e.y, e.owner, e.isBuilding))
        }
        return out.map { (x: $0.0, y: $0.1, owner: $0.2, building: $0.3) }
    }
}

extension World {
    /// Renderer/UI shorthand for the core's team check.
    func isEnemyPublic(_ a: Int, _ b: Int) -> Bool { isEnemy(a, b) }
}

extension GameController {
    /// The first enemy commander (tutorial, labs and other 1v1 tools spawn their practice targets for them).
    var enemyPlayer: Int { world.players.first { world.isEnemy(me, $0.index) }?.index ?? (me == 0 ? 1 : 0) }
}
