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

struct MainMenuView: View {
    @Binding var settings: GameSettings
    var loading: Bool
    var onStart: () -> Void
    @State private var showHelp = false
    let data = GameData.shared

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ZStack {
                LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.07, green: 0.1, blue: 0.16), Color(red: 0.02, green: 0.03, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text("MERIDIAN").font(.system(size: wide ? 56 : 42, weight: .black, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.white, Theme.accent], startPoint: .top, endPoint: .bottom))
                                .tracking(6)
                            Text("THREE FRONTS").font(.system(size: 13, weight: .semibold)).tracking(8).foregroundColor(.white.opacity(0.6))
                        }.padding(.top, 24)

                        sectionTitle("YOUR FACTION")
                        factionGrid(selection: $settings.playerFaction, wide: wide)
                        sectionTitle("OPPONENT")
                        factionGrid(selection: $settings.aiFaction, wide: wide, compact: true)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                sectionTitle("DIFFICULTY")
                                Picker("Difficulty", selection: $settings.difficulty) {
                                    ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) }
                                }.pickerStyle(.segmented)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                sectionTitle("AI STYLE")
                                Picker("Style", selection: $settings.strategy) {
                                    ForEach(AIStrategy.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                                }.pickerStyle(.menu)
                            }
                        }.padding(.horizontal)

                        VStack(alignment: .leading, spacing: 6) {
                            sectionTitle("BATTLEFIELD")
                            Picker("Map", selection: $settings.layout) {
                                ForEach(MapLayout.playable, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented)
                        }.padding(.horizontal)

                        Button(action: onStart) {
                            HStack {
                                if loading { ProgressView().tint(.black) }
                                Text(loading ? "DEPLOYING…" : "DEPLOY").font(.system(size: 20, weight: .heavy)).tracking(4)
                            }
                            .frame(maxWidth: 360).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.faction(settings.playerFaction)))
                            .foregroundColor(.black)
                        }
                        .disabled(loading)
                        .buttonStyle(.plain)
                        .padding(.top, 6)

                        Button("How to play") { showHelp = true }.foregroundColor(Theme.accent)
                            .buttonStyle(.plain)
                        Spacer(minLength: 30)
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
    }

    func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .bold)).tracking(3).foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
    }

    func factionGrid(selection: Binding<Faction>, wide: Bool, compact: Bool = false) -> some View {
        let cols = wide ? 3 : (compact ? 3 : 1)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
            ForEach(Faction.allCases, id: \.self) { f in
                let fd = data.faction(f)
                let on = selection.wrappedValue == f
                Button { selection.wrappedValue = f } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(Theme.faction(f)).frame(width: 10, height: 10)
                            Text(fd.name).font(.system(size: compact ? 13 : 17, weight: .bold))
                            Spacer()
                        }
                        Text(fd.tagline.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundColor(Theme.faction(f))
                        if !compact {
                            Text(fd.description).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                            Text("Durability ×\(String(format: "%.2f", fd.hpMult)) · Build time ×\(String(format: "%.2f", fd.buildTimeMult))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(on ? Theme.faction(f).opacity(0.18) : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.faction(f) : Color.white.opacity(0.1), lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group("Goal", [
                        "Destroy every enemy structure, or",
                        "Hold \(Int((7 * GameData.shared.rules.territory.dominanceFraction).rounded(.up))) of 7 strategic sites for \(Int(GameData.shared.rules.territory.dominanceSeconds / 60)) min \(Int(GameData.shared.rules.territory.dominanceSeconds) % 60) s once the dominance protocol activates at \(Int(GameData.shared.rules.territory.dominanceStart / 60)):00.",
                    ])
                    group("Touch controls", [
                        "Tap a unit or building to select it. Double-tap a unit to select all of that type.",
                        "Touch and hold, then drag, to box-select.",
                        "With units selected, tap the ground to move, tap an enemy to attack, tap a resource with workers to gather.",
                        "Drag with one or two fingers to pan; pinch to zoom. Tap the minimap to jump.",
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
            Color.black.opacity(0.55).ignoresSafeArea()
            Panel(padding: 22) {
                VStack(spacing: 14) {
                    Text("PAUSED").font(.system(size: 26, weight: .black)).tracking(5)
                    Text("Speed").font(.caption).foregroundColor(.secondary)
                    Picker("Speed", selection: $controller.speed) {
                        Text("0.75×").tag(0.75); Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0)
                    }.pickerStyle(.segmented).frame(width: 260)
                    Button("Resume", action: onResume).buttonStyle(.borderedProminent)
                    Button("Tech tree") { controller.showTech = true }.buttonStyle(.bordered)
                    Button("Surrender & quit", role: .destructive, action: onQuit).buttonStyle(.bordered)
                }
            }
        }
    }
}

struct GameOverView: View {
    @ObservedObject var controller: GameController
    let won: Bool
    let reason: String
    var onQuit: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            Panel(padding: 24) {
                VStack(spacing: 12) {
                    Text(won ? "VICTORY" : "DEFEAT").font(.system(size: 40, weight: .black)).tracking(6)
                        .foregroundColor(won ? Theme.accent : Color(red: 1, green: 0.4, blue: 0.3))
                    Text(reason).foregroundColor(.secondary)
                    Text("Match time \(Int(controller.world.time) / 60):\(String(format: "%02d", Int(controller.world.time) % 60))").font(.caption)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow { Text(""); Text("You").bold(); Text("Enemy").bold() }
                        row("Units produced") { $0.unitsProduced }
                        row("Units lost") { $0.unitsLost }
                        row("Kills") { $0.kills }
                        row("Buildings built") { $0.buildingsBuilt }
                        row("Iron gathered") { $0.gathered[0] }
                        row("Gold gathered") { $0.gathered[1] }
                        row("Wood gathered") { $0.gathered[2] }
                        row("Peak army") { $0.peakUnits }
                    }.font(.system(size: 13, design: .monospaced))
                    Button("Main menu", action: onQuit).buttonStyle(.borderedProminent).padding(.top, 6)
                }
            }
        }
    }

    func row(_ t: String, _ f: @escaping (PlayerStats) -> Int) -> some View {
        GridRow {
            Text(t).foregroundColor(.secondary)
            Text("\(f(controller.world.players[0].stats))")
            Text("\(f(controller.world.players[1].stats))")
        }
    }
}
