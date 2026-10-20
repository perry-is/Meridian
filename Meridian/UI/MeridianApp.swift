import SwiftUI
import SpriteKit
import MeridianCore

@main
struct MeridianApp: App {
    init() {
        #if os(macOS)
        // Headless helpers for development: render an art contact sheet.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--art-sheet"), i + 1 < args.count {
            ArtSheet.write(to: URL(fileURLWithPath: args[i + 1]))
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

struct RootView: View {
    @State private var settings = GameSettings()

    func startBattle(_ n: Int, _ f0: Faction, _ f1: Faction) {
        var s = settings
        s.layout = .arena
        s.playerFaction = f0; s.aiFaction = f1
        let c = GameController(settings: s, spectate: true)
        c.setupBattle(n)
        controller = c
    }
    @State private var controller: GameController? = nil
    @State private var loading = false
    @State private var fixedSeed = false

    var body: some View {
        ZStack {
            if let c = controller {
                GameView(controller: c, onQuit: { controller = nil }, onRestart: c.battleMode ? {
                    let n = c.battleSize, f0 = c.settings.playerFaction, f1 = c.settings.aiFaction
                    controller = nil
                    DispatchQueue.main.async { startBattle(n, f0, f1) }
                } : nil)
                    .transition(.opacity)
            } else {
                MainMenuView(settings: $settings, loading: loading, onSpectate: {
                    var s = settings
                    s.seed = UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000
                    controller = GameController(settings: s, spectate: true)
                }, onBattle: { n in startBattle(n, settings.playerFaction, settings.aiFaction) }) {
                    loading = true
                    // Give the menu a frame to show the loading state before generating textures.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if !fixedSeed { settings.seed = UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000 }
                        controller = GameController(settings: settings)
                        loading = false
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller == nil)
        .onAppear {
            // Development switches: -autostart, -spectate (AI plays both sides), -warp <seconds>, -faction/-enemy <name>, -map <layout>.
            let a = ProcessInfo.processInfo.arguments
            func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
            if let f = arg("-faction"), let v = Faction(rawValue: f) { settings.playerFaction = v }
            if let f = arg("-enemy"), let v = Faction(rawValue: f) { settings.aiFaction = v }
            if let m = arg("-map"), let v = MapLayout(rawValue: m) { settings.layout = v }
            if let sd = arg("-seed"), let v = UInt64(sd) { settings.seed = v; fixedSeed = true }
            if let b = arg("-battle"), let n = Int(b), controller == nil {
                settings.layout = .arena
                if arg("-faction") == nil { settings.playerFaction = .humans }
                if arg("-enemy") == nil { settings.aiFaction = .machines }
                startBattle(n, settings.playerFaction, settings.aiFaction)
                return
            }
            if a.contains("-autostart") && controller == nil {
                let c = GameController(settings: settings, spectate: a.contains("-spectate"))
                if let w = arg("-warp"), let secs = Double(w) { c.warp(seconds: secs) }
                if let st = arg("-stress"), let n = Int(st) { c.setupStress(n) }
                controller = c
            }
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
            .sheet(isPresented: $controller.showTech) {
                TechTreeView(controller: controller)
            }
        }
    }
}
