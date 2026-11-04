import SwiftUI
import SpriteKit
import MeridianCore

@main
struct MeridianApp: App {
    init() {
        #if os(macOS)
        // Headless helpers for development: render an art contact sheet.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            IconArt.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--music"), i + 1 < args.count {
            MusicScore.writeWAVs(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--buildings"), i + 2 < args.count, let f = Faction(rawValue: args[i + 1]) {
            ArtSheet.writeBuildings(f, to: URL(fileURLWithPath: args[i + 2]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--poses"), i + 2 < args.count, let f = Faction(rawValue: args[i + 1]) {
            ArtSheet.writePoses(f, to: URL(fileURLWithPath: args[i + 2]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-tech"), i + 1 < args.count {
            let f = i + 2 < args.count ? Faction(rawValue: args[i + 2]) ?? .humans : .humans
            MainActor.assumeIsolated { TechSheet.write(to: URL(fileURLWithPath: args[i + 1]), faction: f) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--portrait-template"), i + 1 < args.count {
            PortraitPipeline.writeTemplate(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--portrait-fixtures"), i + 1 < args.count {
            PortraitPipeline.writeFixtures(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--validate-portraits"), i + 1 < args.count {
            let folder = i + 2 < args.count && !args[i + 2].hasPrefix("-") ? URL(fileURLWithPath: args[i + 2]) : nil
            PortraitPipeline.validate(out: URL(fileURLWithPath: args[i + 1]), folder: folder)
            exit(0)
        }
        if let i = args.firstIndex(of: "--radio"), i + 1 < args.count {
            RadioVoice.writeSamples(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--closeups"), i + 1 < args.count {
            ArtSheet.writeCloseups(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--portraits"), i + 1 < args.count {
            ArtSheet.writePortraits(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--art-sheet"), i + 1 < args.count {
            ArtSheet.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--building-art"), i + 1 < args.count {
            ArtSheet.writeBuildings(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
            #if os(macOS)
                .frame(minWidth: 900, minHeight: 620)
            #endif
        }
    }
}

enum Screen { case boot, title, setup, loading, game }

struct RootView: View {
    @State private var settings = GameSettings()
    @State private var controller: GameController? = nil
    @State private var screen: Screen = .boot
    @State private var watch = false
    @State private var progress = 0.0
    @State private var step = ""
    @State private var tip = Tips.all.randomElement()!
    @State private var loadArt: LoadArt = .threeFronts
    @StateObject private var backdrop = MenuBackdrop()

    func startBattle(_ n: Int, _ f0: Faction, _ f1: Faction) {
        var s = settings
        s.layout = .arena
        s.playerFaction = f0; s.aiFaction = f1
        let c = GameController(settings: s, spectate: true)
        c.setupBattle(n)
        controller = c
        screen = .game
    }

    /// Boot: load data, synthesize audio and raise the menu's live battlefield behind a branded loader.
    func boot() {
        let t0 = Date()
        step = "Charting the frontier…"; progress = 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            _ = GameData.shared
            _ = SoundEngine.shared
            step = "Tuning the orchestra…"; progress = 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                step = "Raising the battlefield…"; progress = 0.55
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    backdrop.start()
                    step = "Ready"; progress = 1
                    let wait = max(0.25, 1.8 - Date().timeIntervalSince(t0))
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { screen = .title }
                }
            }
        }
    }

    /// Match loading: generate the map and world, build the faction art, then drop into the game.
    func startMatch() {
        loadArt = watch ? .threeFronts : .faction(settings.playerFaction)
        tip = Tips.all.randomElement()!
        step = "Surveying the battlefield…"; progress = 0.06
        screen = .loading
        let t0 = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            backdrop.stop()
            // A real match always uses a playable battlefield (the test arena has no resources).
            if !MapLayout.playable.contains(settings.layout) { settings.layout = .crossroads }
            let c = GameController(settings: settings, spectate: watch)
            step = "Assembling the armies…"; progress = 0.45
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = TextureBank.make(data: GameData.shared, factions: c.world.players.map { $0.faction })
                step = "Final preparations…"; progress = 0.85
                let wait = max(0.15, 1.6 - Date().timeIntervalSince(t0))
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    progress = 1
                    controller = c
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { screen = .game }
                }
            }
        }
    }

    /// Continue the saved match: read and rebuild it off the main thread behind the loading screen.
    func resumeMatch() {
        loadArt = SaveStore.info.map { .faction($0.playerFaction) } ?? .threeFronts
        tip = Tips.all.randomElement()!
        step = "Recovering your battlefield…"; progress = 0.08
        screen = .loading
        let t0 = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { backdrop.stop() }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let save = SaveStore.read() else { DispatchQueue.main.async { screen = .title }; return }
            let m = Match.load(save, data: save.extras["quick"] == "1" ? .quick : .shared)
            DispatchQueue.main.async {
                step = "Assembling the armies…"; progress = 0.55
                let c = GameController(resume: m, save: save)
                settings.playerFaction = c.settings.playerFaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    _ = TextureBank.make(data: GameData.shared, factions: c.world.players.map { $0.faction })
                    step = "Final preparations…"; progress = 0.9
                    let wait = max(0.15, 1.4 - Date().timeIntervalSince(t0))
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                        progress = 1; watch = false; controller = c
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { screen = .game }
                    }
                }
            }
        }
    }

    func startTutorial() {
        loadArt = .faction(.humans)
        tip = "Boot Camp: follow the gold markers. You can skip at any time."
        step = "Preparing Boot Camp…"; progress = 0.1
        screen = .loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            backdrop.stop()
            let c = GameController(tutorial: true)
            c.exitTutorial = { backToMenu() }
            step = "Assembling the armies…"; progress = 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = TextureBank.make(data: GameData.shared, factions: c.world.players.map { $0.faction })
                progress = 1; watch = false; controller = c
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { screen = .game }
            }
        }
    }

    func backToMenu() {
        let wasTutorial = controller?.tutorial != nil
        controller = nil
        screen = SaveStore.info != nil || wasTutorial ? .title : .setup
        DispatchQueue.main.async { backdrop.start() }
    }

    var body: some View {
        ZStack {
            switch screen {
            case .game:
                if let c = controller {
                    GameView(controller: c, onQuit: backToMenu, onRestart: c.battleMode ? {
                        let n = c.battleSize, f0 = c.settings.playerFaction, f1 = c.settings.aiFaction
                        controller = nil
                        DispatchQueue.main.async { startBattle(n, f0, f1) }
                    } : nil)
                    .transition(.opacity)
                }
            case .boot:
                LoadingView(title: "Preparing the frontier", step: step, progress: progress, art: .threeFronts).transition(.opacity)
            case .title:
                TitleView(backdrop: backdrop, onPlay: { screen = .setup }, onContinue: resumeMatch, onTutorial: startTutorial).transition(.opacity)
            case .setup:
                SetupView(settings: $settings, watch: $watch, backdrop: backdrop, onBack: { screen = .title }, onDeploy: startMatch).transition(.opacity)
            case .loading:
                LoadingView(title: watch ? "Preparing the battle" : "Deploying", step: step, progress: progress, tip: tip,
                            accent: Theme.faction(settings.playerFaction), art: loadArt).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: screen)
        .onAppear {
            // Development switches: -autostart, -spectate (AI plays both sides), -warp <seconds>, -faction/-enemy <name>, -map <layout>.
            let a = ProcessInfo.processInfo.arguments
            func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
            if let f = arg("-faction"), let v = Faction(rawValue: f) { settings.playerFaction = v }
            if let f = arg("-enemy"), let v = Faction(rawValue: f) { settings.aiFaction = v }
            if let m = arg("-map"), let v = MapLayout(rawValue: m) { settings.layout = v }
            if let d = arg("-difficulty"), let v = Difficulty(rawValue: d) { settings.difficulty = v }
            // -players 3|4 adds computer commanders; -teams 0,0,1,1 puts them in teams; -victory annihilation|dominance.
            if let n = arg("-players").flatMap(Int.init) { while settings.slots.count < min(MatchConfig.maxPlayers, n) { settings.addSlot() } }
            if let t = arg("-teams") {
                let teams = t.split(separator: ",").compactMap { Int($0) }
                for (i, team) in teams.enumerated() where i < settings.slots.count { settings.slots[i].team = team }
            }
            if let v = arg("-victory").flatMap({ VictoryMode(rawValue: $0) }) { settings.victory = v }
            if a.contains("-quick") { settings.quick = true }
            if a.contains("-uitest") || a.contains("-nosave") { SaveStore.delete() }
            if a.contains("-tutorial") && controller == nil {
                let c = GameController(tutorial: true); c.exitTutorial = { backToMenu() }
                controller = c; screen = .game; return
            }
            if let sd = arg("-seed"), let v = UInt64(sd) { settings.seed = v; settings.seedLocked = true }
            if let h = arg("-holdload") {
                // Development: hold a loading screen for review (boot, humans, machines, aliens).
                loadArt = Faction(rawValue: h).map { .faction($0) } ?? .threeFronts
                tip = Tips.all[0]; step = "Assembling the armies…"; progress = 0.45
                screen = .loading
                return
            }
            if let sc = arg("-scenario").flatMap({ TacticalScenario(rawValue: $0) }), controller == nil {
                var st = settings
                st.layout = .arena
                st.playerFaction = sc.factions[0]; st.aiFaction = sc.factions[1]
                let c = GameController(settings: st, spectate: true)
                sc.setup(c.world, formation: arg("-formation").flatMap { Formation(rawValue: $0) } ?? .balanced)
                c.battleMode = true
                controller = c
                screen = .game
                return
            }
            if let b = arg("-battle"), let n = Int(b), controller == nil {
                // Observer launch: never alter the menu's own match settings.
                let f0 = arg("-faction").flatMap { Faction(rawValue: $0) } ?? .humans
                let f1 = arg("-enemy").flatMap { Faction(rawValue: $0) } ?? .machines
                startBattle(n, f0, f1)
                return
            }
            if a.contains("-autostart") && controller == nil {
                let c = GameController(settings: settings, spectate: a.contains("-spectate"))
                if let w = arg("-warp"), let secs = Double(w) { c.warp(seconds: secs) }
                if let st = arg("-stress"), let n = Int(st) { c.setupStress(n) }
                if a.contains("-lab") { c.setupLab() }
                if let k = arg("-buildlab").flatMap(Int.init) { c.setupBuildLab(k) }
                if a.contains("-showtech") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { c.showTech = true } }
                if let u = arg("-portraitdemo") {
                    // Development: spawn a unit by id next to the base, select it and have it talk every few seconds.
                    let hq = c.world.buildings(of: c.me)[0]
                    if let t = c.data.units.firstIndex(where: { $0.id == u }) {
                        let e = c.world.spawnUnit(t, owner: c.me, x: hq.x + 3, y: hq.y + 3)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.select([e.id]); c.focusCamera?(e.x, e.y) }
                        Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                            MainActor.assumeIsolated { c.radio.chatter(.poke, unit: c.data.units[t], type: t, faction: c.data.units[t].faction) }
                        }
                    }
                }
                controller = c
                screen = .game
            }
            if controller == nil && screen == .boot { boot() }
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

// MARK: - SpriteKit host

#if os(iOS)
struct SpriteHost: UIViewRepresentable {
    let scene: GameScene
    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.ignoresSiblingOrder = true
        v.isMultipleTouchEnabled = true
        v.preferredFramesPerSecond = 60
        v.presentScene(scene)
        return v
    }
    func updateUIView(_ v: SKView, context: Context) {}
}
#else
final class KeySKView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
}

struct SpriteHost: NSViewRepresentable {
    let scene: GameScene
    func makeNSView(context: Context) -> SKView {
        let v = KeySKView()
        v.ignoresSiblingOrder = true
        v.preferredFramesPerSecond = 60
        v.presentScene(scene)
        return v
    }
    func updateNSView(_ v: SKView, context: Context) {}
}
#endif

struct GameView: View {
    @ObservedObject var controller: GameController
    let onQuit: () -> Void
    var onRestart: (() -> Void)? = nil
    @State private var scene: GameScene? = nil
    @State private var showPause = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let s = scene {
                    SpriteHost(scene: s).ignoresSafeArea()
                }
                if let s = scene, !GameScene.flags.contains("nohud") {
                    if controller.spectating {
                        SpectatorHUD(controller: controller, scene: s, onQuit: onQuit, onRestart: onRestart)
                    } else {
                        HUDView(controller: controller, scene: s, showPause: $showPause)
                    }
                }
                if showPause {
                    PauseView(controller: controller, onResume: { showPause = false; controller.paused = false }, onQuit: onQuit)
                }
                if let over = controller.gameOver {
                    GameOverView(controller: controller, won: over.won, reason: over.reason, onQuit: onQuit)
                }
            }
            .onAppear {
                if scene == nil { scene = GameScene(controller: controller, size: geo.size) }
            }
            .onChange(of: phase) { _, p in
                // Leaving the app (call, notification, home) pauses the match instead of letting it run on.
                if p != .active && !controller.spectating && controller.gameOver == nil {
                    controller.paused = true; showPause = true
                    controller.saveNow()   // in case the system closes the app while it's away
                }
            }
            .sheet(isPresented: $controller.showTech) {
                TechTreeView(controller: controller)
            }
        }
    }
}
