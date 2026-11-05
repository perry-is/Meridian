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
                        "Annihilation (the standard mode): destroy every enemy structure. A commander with no structures left is out, and the last team standing wins.",
                        "Dominance (optional): as above, or hold \(Int((7 * GameData.shared.rules.territory.dominanceFraction).rounded(.up))) of 7 strategic sites (\(Int(GameData.shared.rules.territory.dominanceFraction * 100))% of them on bigger maps) for \(Int(GameData.shared.rules.territory.dominanceSeconds / 60)) min \(Int(GameData.shared.rules.territory.dominanceSeconds) % 60) s once the dominance protocol activates at \(Int(GameData.shared.rules.territory.dominanceStart / 60)):00. Allies' sites count together.",
                        "Quick Match plays on a smaller map with everything built faster; dominance activates at \(Int(GameData.quick.rules.territory.dominanceStart / 60)):00 and needs \(Int(GameData.quick.rules.territory.dominanceSeconds / 60)) min \(Int(GameData.quick.rules.territory.dominanceSeconds) % 60) s.",
                        "Up to four commanders can fight, free-for-all or in teams. Allies share vision, never damage each other and capture sites together; bigger battlefields keep every base the same distance from its neighbours.",
                    ])
                    group("Touch controls", [
                        "Tap a unit or building to select it. Double-tap a unit to select all of that type.",
                        "Drag one finger to move around the map.",
                        "Press and hold on the map, then drag, to draw a selection box. Pinch with two fingers to zoom.",
                        "Placing a building: drag it into position and tap Confirm, or simply double-tap the spot.",
                        "With units selected, tap the ground to move, tap an enemy to attack, tap a resource with workers to gather.",
                        "Tap or drag the minimap to jump the camera.",
                        "Attack-Move: tap the button, then the destination; units fight everything on the way.",
                        "Build: select workers → Build → choose a structure → drag the ghost → Confirm.",
                        "Tap a site's platform to inspect it; owned sites can be configured as Extractor (income), Watchpost (vision), Bulwark (a tower) or Beacon (a forward base with a wide build zone).",
                    ])
                    group("Desktop controls", [
                        "Left-click select, drag to box-select, right-click to command.",
                        "Scroll/trackpad to pan, pinch or ⌘-scroll to zoom, arrow keys pan.",
                        "A attack-move · S stop · H hold · P patrol · B build · M mode · E EMP · X select army · Y idle soldiers · I idle worker · ⌘1-9 assign group · 1-9 recall · Space pause · T tech tree.",
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
    var onRestart: (() -> Void)? = nil
    @State private var confirmRestart = false

    /// "2v2 · Riverbend · Annihilation · Hard · seed 48213", then each commander with a team letter.
    var matchLine: String {
        let st = controller.settings, w = controller.world
        let sizes = Dictionary(grouping: st.slots, by: { $0.team }).values.map { $0.count }.sorted(by: >)
        let shape = sizes.count == st.slots.count && st.slots.count > 2 ? "\(st.slots.count)-way FFA" : sizes.map(String.init).joined(separator: "v")
        return [shape, w.map.name, st.victory.title, st.difficulty.title, "seed \(st.seed)"].joined(separator: "  ·  ")
    }
    var commanderLine: String {
        controller.world.players.map { "\($0.name) (\(SetupView.teamNames[min($0.team, 3)]))" }.joined(separator: "  ·  ")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            GlassPanel(accent: Theme.faction(controller.hud.faction), padding: 22, cut: 16) {
                VStack(spacing: 14) {
                    Text("PAUSED").font(.system(size: 26, weight: .black)).tracking(8)
                    VStack(spacing: 3) {
                        Text(String(format: "%d:%02d  ·  %@", Int(controller.world.time) / 60, Int(controller.world.time) % 60, matchLine))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                        Text(commanderLine).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    }
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
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
                        if let r = onRestart {
                            Button(confirmRestart ? "Restart: sure?" : "Restart") {
                                if confirmRestart { if !controller.spectating { SaveStore.delete() }; r() } else { confirmRestart = true }
                            }.buttonStyle(.bordered).tint(confirmRestart ? .orange : .white)
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
    var onRematch: (() -> Void)? = nil
    @State private var appear = false
    @State private var details = false

    var body: some View {
        let accent = won ? Theme.faction(controller.hud.faction) : Color(red: 1, green: 0.35, blue: 0.28)
        let w = controller.world
        let teamGame = w.players.count > 2
        ZStack(alignment: .bottom) {
            // The battlefield stays visible behind the panel while the camera tours it.
            LinearGradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                .allowsHitTesting(false)
            ScrollView {
                GlassPanel(accent: accent, padding: 20, cut: 18) {
                    VStack(spacing: 12) {
                        Text(controller.spectating ? "MATCH OVER" : (won ? "VICTORY" : "DEFEAT")).font(.system(size: controller.spectating ? 34 : 46, weight: .black, design: .rounded)).tracking(10)
                            .foregroundStyle(LinearGradient(colors: [.white, accent], startPoint: .top, endPoint: .bottom))
                            .shadow(color: accent.opacity(0.7), radius: 12)
                            .scaleEffect(appear ? 1 : 1.4).opacity(appear ? 1 : 0)
                        Text(reason.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(3).foregroundColor(accent)
                        if let t = w.winningTeam, teamGame {
                            Text(winnerLine(t)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
                        }
                        Text(String(format: "Match time %d:%02d", Int(w.time) / 60, Int(w.time) % 60)).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                        if teamGame && !details { teamTable } else { commanderTable }
                        if teamGame {
                            Button { withAnimation(.easeInOut(duration: 0.2)) { details.toggle() }; SoundEngine.shared?.play("click", at: nil) } label: {
                                Text(details ? "SHOW TEAMS" : "SHOW EVERY COMMANDER").font(.system(size: 10, weight: .heavy)).tracking(2)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Chamfer(cut: 6).fill(Color.white.opacity(0.08)))
                            }.buttonStyle(.plain).foregroundColor(.white.opacity(0.8))
                        }
                        HStack(spacing: 10) {
                            if let r = onRematch {
                                Button { SoundEngine.shared?.play("built", at: nil, minGap: 0); r() } label: {
                                    Text("REMATCH").font(.system(size: 14, weight: .black)).tracking(3)
                                        .padding(.horizontal, 18).padding(.vertical, 11)
                                        .background(Chamfer(cut: 9).fill(Color.black.opacity(0.5)))
                                        .overlay(Chamfer(cut: 9).stroke(accent.opacity(0.7), lineWidth: 1))
                                        .foregroundColor(.white)
                                }.buttonStyle(.plain).accessibilityLabel("Rematch")
                            }
                            Button(action: onQuit) {
                                Text("RETURN TO COMMAND").font(.system(size: 14, weight: .black)).tracking(3)
                                    .padding(.horizontal, 18).padding(.vertical, 11)
                                    .background(Chamfer(cut: 9).fill(accent)).foregroundColor(.black)
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                    .foregroundColor(.white)
                }
                .frame(maxWidth: teamGame && details ? 480 : 380)
                .padding(.horizontal, 16).padding(.vertical, 24)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appear = true } }
    }

    /// "Team B wins: The Lattice and Terran Concord 4".
    func winnerLine(_ team: Int) -> String {
        let names = controller.world.players.filter { $0.team == team }.map { $0.name }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : (names.first ?? "")
        return "Team \(SetupView.teamNames[min(team, SetupView.teamNames.count - 1)]) wins: \(list)"
    }

    /// Distinct teams, the player's first.
    var teams: [Int] {
        var out: [Int] = []
        let me = controller.world.players[controller.me].team
        for p in controller.world.players.sorted(by: { ($0.team == me ? 0 : 1, $0.team) < ($1.team == me ? 0 : 1, $1.team) }) where !out.contains(p.team) { out.append(p.team) }
        return out
    }

    /// Team totals: one column per team.
    var teamTable: some View {
        let w = controller.world
        let me = w.players[controller.me].team
        return VStack(spacing: 6) {
            HStack {
                Text("").frame(width: 110, alignment: .leading)
                ForEach(teams, id: \.self) { t in
                    let first = w.players.first { $0.team == t }?.index ?? 0
                    Text(controller.spectating ? "TEAM \(SetupView.teamNames[min(t, 3)])" : (t == me ? "YOUR TEAM" : (teams.count > 2 ? "TEAM \(SetupView.teamNames[min(t, 3)])" : "ENEMY")))
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity).foregroundColor(Theme.team(first))
                }
            }
            .font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
            teamRow("Units produced") { $0.unitsProduced }
            teamRow("Units lost") { $0.unitsLost }
            teamRow("Kills") { $0.kills }
            teamRow("Buildings built") { $0.buildingsBuilt }
            teamRow("Iron gathered") { $0.gathered[0] }
            teamRow("Wood gathered") { $0.gathered[2] }
            teamRow("Gold gathered") { $0.gathered[1] }
            teamRow("Peak army") { $0.peakUnits }
        }
    }

    func teamRow(_ t: String, _ f: @escaping (PlayerStats) -> Int) -> some View {
        let w = controller.world
        let values = teams.map { team in w.players.filter { $0.team == team }.reduce(0) { $0 + f($1.stats) } }
        let m = Double(max(1, values.max() ?? 1))
        return HStack(spacing: 8) {
            Text(t).font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).frame(width: 110, alignment: .leading)
            ForEach(values.indices, id: \.self) { i in
                let first = w.players.first { $0.team == teams[i] }?.index ?? 0
                bar(values[i], m, Theme.team(first), columns: values.count)
            }
        }
    }

    /// Per-commander columns.
    var commanderTable: some View {
        VStack(spacing: 6) {
            HStack {
                Text("").frame(width: 110, alignment: .leading)
                ForEach(controller.world.players.indices, id: \.self) { p in
                    Text(columnTitle(p)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity).foregroundColor(Theme.team(p))
                }
            }
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
    }

    /// Column heading per commander: YOU / ALLY / ENEMY (numbered when there are several).
    func columnTitle(_ p: Int) -> String {
        let w = controller.world
        if controller.spectating { return "P\(p + 1)" }
        if p == controller.me { return "YOU" }
        let ally = w.isAlly(controller.me, p)
        let peers = w.players.indices.filter { $0 != controller.me && w.isAlly(controller.me, $0) == ally }
        let base = ally ? "ALLY" : "ENEMY"
        return peers.count > 1 ? "\(base) \((peers.firstIndex(of: p) ?? 0) + 1)" : base
    }

    func row(_ t: String, _ f: @escaping (PlayerStats) -> Int) -> some View {
        let values = controller.world.players.map { f($0.stats) }
        let m = Double(max(1, values.max() ?? 1))
        return HStack(spacing: 8) {
            Text(t).font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).frame(width: 110, alignment: .leading)
            ForEach(values.indices, id: \.self) { p in bar(values[p], m, Theme.team(p), columns: values.count) }
        }
    }

    /// One stat cell: a bar and the number. Numbers stay on one line (they shrink rather than wrap on narrow screens).
    func bar(_ v: Int, _ m: Double, _ c: Color, columns: Int) -> some View {
        HStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(c.opacity(0.85)).frame(width: g.size.width * CGFloat(Double(v) / m))
                }
            }.frame(height: 5)
            Text("\(v)").font(.system(size: 10, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: columns > 2 ? 30 : 44, alignment: .trailing)
        }.frame(maxWidth: .infinity)
    }
}
