import SwiftUI
import MeridianCore

enum Theme {
    static let panel = Color(red: 0.06, green: 0.08, blue: 0.11).opacity(0.86)
    static let panelStroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.35, green: 0.8, blue: 1.0)
    static let iron = Color(red: 0.72, green: 0.78, blue: 0.86)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.3)
    static let wood = Color(red: 0.72, green: 0.52, blue: 0.3)
    static func faction(_ f: Faction) -> Color {
        switch f {
        case .humans: return Color(red: 0.95, green: 0.72, blue: 0.3)
        case .machines: return Color(red: 0.35, green: 0.9, blue: 1.0)
        case .aliens: return Color(red: 0.6, green: 1.0, blue: 0.4)
        }
    }
    static func team(_ p: Int) -> Color { let c = TeamColor.swiftUI(p); return Color(red: c.0, green: c.1, blue: c.2) }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
    }
}

struct Wordmark: View {
    let wide: Bool
    @State private var glow = false
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Text("MERIDIAN").font(.system(size: wide ? 64 : 46, weight: .black, design: .rounded)).tracking(wide ? 12 : 8)
                    .foregroundColor(Theme.accent.opacity(0.45)).blur(radius: glow ? 14 : 8)
                Text("MERIDIAN").font(.system(size: wide ? 64 : 46, weight: .black, design: .rounded)).tracking(wide ? 12 : 8)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.75, green: 0.92, blue: 1), Theme.accent], startPoint: .top, endPoint: .bottom))
            }
            HStack(spacing: 10) {
                Rectangle().fill(Theme.faction(.humans)).frame(width: 26, height: 2)
                Text("THREE FRONTS").font(.system(size: 12, weight: .heavy)).tracking(8).foregroundColor(.white.opacity(0.75))
                Rectangle().fill(Theme.faction(.aliens)).frame(width: 26, height: 2)
            }
            Text("Hold the line. Take the meridian.").font(.system(size: 12, weight: .medium, design: .serif)).italic().foregroundColor(.white.opacity(0.55))
        }
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever()) { glow = true } }
    }
}

/// Live AI-vs-AI skirmish rendered silently behind the main menu.
@MainActor
final class MenuBackdrop: ObservableObject {
    @Published var scene: GameScene? = nil
    private var controller: GameController? = nil

    func start() {
        guard scene == nil, !ProcessInfo.processInfo.arguments.contains("-autostart") else { return }
        var s = GameSettings()
        let all = Faction.allCases
        s.playerFaction = all[Int.random(in: 0..<3)]
        s.aiFaction = all[Int.random(in: 0..<3)]
        s.layout = MapLayout.playable.randomElement()!
        s.seed = UInt64.random(in: 1...10_000)
        let c = GameController(settings: s, spectate: true)
        c.warp(seconds: 300)
        let sc = GameScene(controller: c, size: CGSize(width: 800, height: 1200))
        sc.silent = true
        sc.backdrop = true
        controller = c
        scene = sc
    }

    func stop() { scene?.isPaused = true; scene = nil; controller = nil }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var onTutorial: (() -> Void)? = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let start = onTutorial {
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { start() } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "graduationcap.fill").font(.system(size: 20))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Play the Boot Camp tutorial").font(.headline)
                                    Text("A guided 5-minute match that teaches the basics by doing.").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.18)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gold.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start tutorial")
                    }
                    group("Goal", [
                        "Destroy every enemy structure, or",
                        "Hold \(Int((7 * GameData.shared.rules.territory.dominanceFraction).rounded(.up))) of 7 strategic sites for \(Int(GameData.shared.rules.territory.dominanceSeconds / 60)) min \(Int(GameData.shared.rules.territory.dominanceSeconds) % 60) s once the dominance protocol activates at \(Int(GameData.shared.rules.territory.dominanceStart / 60)):00.",
                    ])
                    group("Touch controls", [
                        "Tap a unit or building to select it. Double-tap a unit to select all of that type.",
                        "Drag one finger to move around the map.",
                        "Drag two fingers together to draw a selection box; pinch to zoom.",
                        "With units selected, tap the ground to move, tap an enemy to attack, tap a resource with workers to gather.",
                        "Tap or drag the minimap to jump the camera.",
                        "Attack-Move: tap the button, then the destination; units fight everything on the way.",
                        "Build: select workers → Build → choose a structure → drag the ghost → Confirm.",
                        "Tap a site's platform to inspect it; owned sites can be configured as Extractor, Watchpost or Bulwark.",
                    ])
                    group("Desktop controls", [
                        "Left-click select, drag to box-select, right-click to command.",
                        "Scroll/trackpad to pan, pinch or ⌘-scroll to zoom, arrow keys pan.",
                        "A attack-move · S stop · H hold · P patrol · B build · M mode · E EMP · X select army · I idle worker · ⌘1-9 assign group · 1-9 recall · Space pause · T tech tree.",
                    ])
                    group("Economy", [
                        "Workers gather Iron, Gold and Wood and return them to your HQ, depots or forward structures.",
                        "Captured sites produce a steady trickle of all three resources.",
                        "Unit limit: 200 actual units — no supply buildings.",
                    ])
                    group("Factions", [
                        "Concord (Humans): configurable units and towers; forward posts and captured sites repair units and accept resources; units near staging positions deal +10% damage.",
                        "Lattice (Machines): 35% tougher, 40% slower to build. Units linked to two allies or a network structure take 15% less and deal 10% more damage. EMP and Jammers break links.",
                        "Brood (Aliens): 25% faster to build, 20% frailer. Regenerate and move 15% faster inside Bloom (own territory). Adaptation research forces tradeoffs.",
                    ])
                }
                .padding()
            }
            .navigationTitle("How to play")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
        }
    }

    func group(_ t: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.headline)
            ForEach(items, id: \.self) { Text("• " + $0).font(.callout).foregroundColor(.secondary) }
        }
    }
}

struct PauseView: View {
    @ObservedObject var controller: GameController
    var onResume: () -> Void
    var onQuit: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            GlassPanel(accent: Theme.faction(controller.hud.faction), padding: 22, cut: 16) {
                VStack(spacing: 14) {
                    Text("PAUSED").font(.system(size: 26, weight: .black)).tracking(8)
                    Text(String(format: "%d:%02d  ·  %@", Int(controller.world.time) / 60, Int(controller.world.time) % 60, controller.world.map.name))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GAME SPEED").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
                        Picker("Speed", selection: $controller.speed) {
                            Text("0.75×").tag(0.75); Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0)
                        }.pickerStyle(.segmented)
                    }.frame(width: 260)
                    AudioSettings()
                    HStack(spacing: 10) {
                        Button("Tech tree") { controller.showTech = true }.buttonStyle(.bordered)
                        Button("Resume", action: onResume).buttonStyle(.borderedProminent).tint(Theme.faction(controller.hud.faction)).foregroundColor(.black)
                    }
                    HStack(spacing: 10) {
                        if controller.canSave {
                            Button("Save & quit") { controller.saveNow(); onQuit() }.buttonStyle(.bordered).tint(.white)
                        }
                        Button("Surrender", role: .destructive) { if !controller.spectating { SaveStore.delete() }; onQuit() }.buttonStyle(.bordered)
                    }
                }
                .foregroundColor(.white)
            }
            .frame(maxWidth: 340)
        }
    }
}

struct AudioSettings: View {
    @State private var master: Float = SoundEngine.shared?.master ?? 0.8
    @State private var sfx: Float = SoundEngine.shared?.sfxVolume ?? 0.8
    @State private var music: Float = SoundEngine.shared?.musicVolume ?? 0.45
    @AppStorage("fx.shake") private var shake = true
    @AppStorage("fx.daynight") private var dayNight = true
    @AppStorage("guide.on") private var guide = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            slider("speaker.wave.3.fill", "Master", $master) { SoundEngine.shared?.master = $0 }
            slider("burst.fill", "Effects", $sfx) { SoundEngine.shared?.sfxVolume = $0 }
            slider("music.note", "Music", $music) { SoundEngine.shared?.musicVolume = $0 }
            Toggle("Screen shake", isOn: $shake).font(.system(size: 12, weight: .semibold))
            Toggle("Day/night cycle (cosmetic)", isOn: $dayNight).font(.system(size: 12, weight: .semibold))
            Toggle("Commander's guide (always on for Easy)", isOn: $guide).font(.system(size: 12, weight: .semibold))
        }
        .frame(width: 260)
    }
    func slider(_ sym: String, _ name: String, _ v: Binding<Float>, _ set: @escaping (Float) -> Void) -> some View {
        HStack {
            Image(systemName: sym).frame(width: 18).foregroundColor(.secondary)
            Text(name).font(.system(size: 12, weight: .semibold)).frame(width: 52, alignment: .leading)
            Slider(value: v, in: 0...1).onChange(of: v.wrappedValue) { _, n in set(n) }
        }
    }
}

struct GameOverView: View {
    @ObservedObject var controller: GameController
    let won: Bool
    let reason: String
    var onQuit: () -> Void
    @State private var appear = false
    var body: some View {
        let accent = won ? Theme.faction(controller.hud.faction) : Color(red: 1, green: 0.35, blue: 0.28)
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()
            GlassPanel(accent: accent, padding: 22, cut: 18) {
                VStack(spacing: 12) {
                    Text(won ? "VICTORY" : "DEFEAT").font(.system(size: 46, weight: .black, design: .rounded)).tracking(10)
                        .foregroundStyle(LinearGradient(colors: [.white, accent], startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.7), radius: 12)
                        .scaleEffect(appear ? 1 : 1.4).opacity(appear ? 1 : 0)
                    Text(reason.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(3).foregroundColor(accent)
                    Text(String(format: "Match time %d:%02d", Int(controller.world.time) / 60, Int(controller.world.time) % 60)).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    VStack(spacing: 6) {
                        HStack { Text("").frame(width: 110, alignment: .leading); Text("YOU").frame(maxWidth: .infinity); Text("ENEMY").frame(maxWidth: .infinity) }
                            .font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
                        row("Units produced") { $0.unitsProduced }
                        row("Units lost") { $0.unitsLost }
                        row("Kills") { $0.kills }
                        row("Buildings built") { $0.buildingsBuilt }
                        row("Iron gathered") { $0.gathered[0] }
                        row("Wood gathered") { $0.gathered[2] }
                        row("Gold gathered") { $0.gathered[1] }
                        row("Peak army") { $0.peakUnits }
                    }
                    Button(action: onQuit) {
                        Text("RETURN TO COMMAND").font(.system(size: 14, weight: .black)).tracking(3)
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(Chamfer(cut: 9).fill(accent)).foregroundColor(.black)
                    }.buttonStyle(.plain).padding(.top, 6)
                }
                .foregroundColor(.white)
            }
            .frame(maxWidth: 380)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appear = true } }
    }

    func row(_ t: String, _ f: @escaping (PlayerStats) -> Int) -> some View {
        let a = f(controller.world.players[0].stats), b = f(controller.world.players[1].stats)
        let m = Double(max(1, max(a, b)))
        return HStack(spacing: 8) {
            Text(t).font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).frame(width: 110, alignment: .leading)
            bar(a, m, Theme.team(0))
            bar(b, m, Theme.team(1))
        }
    }

    func bar(_ v: Int, _ m: Double, _ c: Color) -> some View {
        HStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(c.opacity(0.85)).frame(width: g.size.width * CGFloat(Double(v) / m))
                }
            }.frame(height: 5)
            Text("\(v)").font(.system(size: 10, weight: .semibold, design: .monospaced)).frame(width: 40, alignment: .trailing)
        }.frame(maxWidth: .infinity)
    }
}
