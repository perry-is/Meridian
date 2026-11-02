import SwiftUI
import MeridianCore

/// Front end: boot loader → title (Play · How to play) → battle setup → match loading → game.

extension AIStrategy {
    /// Player-facing name for the opponent's temperament.
    var temperament: String {
        switch self {
        case .balanced: return "Steady"
        case .aggressive: return "Aggressive"
        case .territorial: return "Expansionist"
        case .tech: return "Scholarly"
        }
    }
    var temperamentBlurb: String {
        switch self {
        case .balanced: return "A measured commander who builds, expands and attacks in turn."
        case .aggressive: return "Strikes early and often. Expect raids."
        case .territorial: return "Fights for the map's strategic sites."
        case .tech: return "Researches hard for a powerful late army."
        }
    }
}

extension Difficulty {
    var blurb: String {
        switch self {
        case .easy: return "A gentle opponent. Great for learning — anyone can win."
        case .normal: return "A fair fight for players who know the basics."
        case .hard: return "Relentless, efficient and quick to punish mistakes."
        }
    }
}

enum Tips {
    static let all = [
        "Tap a tree or ore with workers selected to put them to work — a ring confirms the order.",
        "Press and hold, then drag, to draw a selection box. A quick drag moves the camera.",
        "Captured sites trickle all three resources. In Dominance mode, holding most of them wins the match.",
        "Up to four commanders can fight. Allies share vision and capture sites together.",
        "Destroy every enemy structure to win. A commander with no buildings left is out of the fight.",
        "Idle workers wear a small amber marker. Tap Idle to find one.",
        "Tap an enemy with combat units selected to focus your attack on it.",
        "Attack-Move sends units to a spot while fighting everything on the way.",
        "Patrol: tap two points and your units will guard the path between them.",
        "Concord units fight harder near their HQ, forward posts and captured sites.",
        "Lattice units linked to two allies take less damage. Keep them together.",
        "Brood regenerate and run faster inside their own territory.",
        "Towers get pricier with each one you build. Spread your defences.",
        "Pause any time to change game speed, volume or check the tech tree.",
    ]
}

// MARK: - Shared backdrop

/// The live battlefield behind the title and setup screens (a silent AI-vs-AI skirmish), dimmed.
struct MenuBackground: View {
    @ObservedObject var backdrop: MenuBackdrop
    var dim: Double = 0.55
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.05).ignoresSafeArea()
            if let s = backdrop.scene {
                SpriteHost(scene: s).ignoresSafeArea().allowsHitTesting(false).transition(.opacity)
            }
            LinearGradient(colors: [Color.black.opacity(dim), Color.black.opacity(dim * 0.3), Color.black.opacity(dim + 0.2), Color.black.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
        }
    }
}

// MARK: - Loading

/// Animated emblem: three faction arcs orbiting the glowing meridian line.
struct MeridianEmblem: View {
    var size: CGFloat = 140
    @State private var spin = false
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.accent.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: size * 0.6))
                .scaleEffect(pulse ? 1.1 : 0.9)
            ForEach(Array(Faction.allCases.enumerated()), id: \.offset) { i, f in
                Circle().trim(from: 0.04, to: 0.29)
                    .stroke(Theme.faction(f), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                    .rotationEffect(.degrees(Double(i) * 120 + (spin ? 360 : 0)))
                    .scaleEffect(x: 1, y: 0.5)
                    .shadow(color: Theme.faction(f).opacity(0.8), radius: 6)
            }
            .frame(width: size * 0.82, height: size * 0.82)
            Capsule().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: size)
                .shadow(color: Theme.accent, radius: 8)
            Circle().fill(.white).frame(width: size * 0.07).shadow(color: Theme.accent, radius: 10)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse = true }
        }
    }
}

/// Painted loading art: a phone-shaped version and a wider one for the Duo's unfolded screen and iPad.
/// The boot art has a progress bar painted in; the live bar is laid exactly over it.
enum LoadArt {
    case threeFronts, faction(Faction)

    var name: String {
        switch self {
        case .threeFronts: return "LoadBoot"
        case .faction(.humans): return "LoadConcord"
        case .faction(.machines): return "LoadLattice"
        case .faction(.aliens): return "LoadBrood"
        }
    }

    struct Variant { let image: String; let size: CGSize; let bar: CGRect? }

    /// Picks the version whose shape best fits the screen. Bar rects are in image pixels.
    func variant(for view: CGSize) -> Variant {
        let wide = view.width / max(1, view.height) > 0.62
        let bar: CGRect?
        if wide {
            if case .threeFronts = self { bar = CGRect(x: 404, y: 1907, width: 727, height: 14) } else { bar = nil }
            return Variant(image: name + "Wide", size: CGSize(width: 1536, height: 2048), bar: bar)
        }
        if case .threeFronts = self { bar = CGRect(x: 174, y: 1557, width: 594, height: 11) } else { bar = nil }
        return Variant(image: name, size: CGSize(width: 941, height: 1672), bar: bar)
    }
}

struct LoadingView: View {
    let title: String
    let step: String
    let progress: Double
    var tip: String? = nil
    var accent: Color = Theme.accent
    var art: LoadArt? = nil
    var body: some View {
        if let art { ArtLoadingView(art: art, title: title, step: step, progress: progress, tip: tip, accent: accent) } else { plain }
    }

    var plain: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.01, green: 0.02, blue: 0.04)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                // Distant stars.
                Canvas { ctx, sz in
                    for i in 0..<70 {
                        let x = CGFloat((i * 7919) % 1000) / 1000 * sz.width, y = CGFloat((i * 104729) % 1000) / 1000 * sz.height * 0.7
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.25 + Double(i % 5) * 0.1)))
                    }
                }.ignoresSafeArea()
                VStack(spacing: 22) {
                    Spacer()
                    MeridianEmblem(size: min(170, geo.size.width * 0.4))
                    Wordmark(wide: geo.size.width > 700)
                    Spacer()
                    VStack(spacing: 10) {
                        Text(title.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(4).foregroundColor(accent)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [accent.opacity(0.6), accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, min(300, geo.size.width - 80) * progress))
                                .shadow(color: accent.opacity(0.7), radius: 6)
                        }
                        .frame(width: min(300, geo.size.width - 80), height: 6)
                        .animation(.easeOut(duration: 0.35), value: progress)
                        Text(step).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    }
                    if let t = tip {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill").foregroundColor(Theme.gold)
                            Text(t).font(.system(size: 13)).foregroundColor(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: 420)
                        .background(Chamfer(cut: 8).fill(Color.white.opacity(0.06)))
                        .padding(.horizontal, 24)
                    }
                    Spacer().frame(height: 40)
                }
            }
        }
    }
}

/// Loading screen over painted art (the art carries the game's title).
struct ArtLoadingView: View {
    let art: LoadArt
    let title: String
    let step: String
    let progress: Double
    var tip: String?
    var accent: Color

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let v = art.variant(for: full)
            let k = max(full.width / v.size.width, full.height / v.size.height)
            let ox = (full.width - v.size.width * k) / 2, oy = (full.height - v.size.height * k) / 2
            // Where the painted bar lands on screen (if it does).
            let painted: CGRect? = v.bar.map { CGRect(x: ox + $0.minX * k, y: oy + $0.minY * k, width: $0.width * k, height: max(6, $0.height * k)) }
                .flatMap { $0.minX >= 8 && $0.maxX <= full.width - 8 && $0.maxY <= full.height - 20 ? $0 : nil }
            ZStack(alignment: .topLeading) {
                Color.black
                Image(v.image).resizable().interpolation(.high)
                    .frame(width: v.size.width * k, height: v.size.height * k)
                    .position(x: full.width / 2, y: full.height / 2)
                if let r = painted {
                    // Live bar over the painted one, then the step and tip below it.
                    bar(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                    Text(step).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                        .position(x: full.width / 2, y: r.maxY + 16)
                    // The painted bar sits low, so the tip goes above it.
                    tipView.frame(width: full.width, height: 160, alignment: .bottom)
                        .position(x: full.width / 2, y: r.minY - 14 - 80)
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Text(title.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(4).foregroundColor(accent)
                            .shadow(color: .black, radius: 4)
                        bar(width: min(320, full.width - 80), height: 7)
                        Text(step).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black, radius: 3)
                        tipView
                        Spacer().frame(height: max(30, geo.safeAreaInsets.bottom + 20))
                    }
                    .frame(width: full.width, height: full.height)
                    .position(x: full.width / 2, y: full.height / 2)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: full.height * 0.38)
                    }
                }
            }
            .frame(width: full.width, height: full.height)
            .clipped()
            .offset(x: -geo.safeAreaInsets.leading, y: -geo.safeAreaInsets.top)
        }
    }

    func bar(width: CGFloat, height: CGFloat) -> some View {
        let p = max(0.03, min(1, progress))
        return ZStack(alignment: .leading) {
            Chamfer(cut: height * 0.5).fill(Color(red: 0.02, green: 0.04, blue: 0.08)).frame(width: width + 6, height: height + 6).offset(x: -3)
            Chamfer(cut: height * 0.5).stroke(Color(red: 0.35, green: 0.7, blue: 1).opacity(0.6), lineWidth: 1).frame(width: width, height: height)
            Chamfer(cut: height * 0.5)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.85, green: 0.95, blue: 1)], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(height * 2, width * p), height: height)
                .shadow(color: Color(red: 0.4, green: 0.8, blue: 1), radius: 6)
        }
        .frame(width: width, height: height, alignment: .leading)
        .animation(.easeOut(duration: 0.35), value: progress)
    }

    @ViewBuilder var tipView: some View {
        if let t = tip {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundColor(Theme.gold)
                Text(t).font(.system(size: 13)).foregroundColor(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 420)
            .background(Chamfer(cut: 8).fill(Color.black.opacity(0.6)))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Title

struct TitleView: View {
    @ObservedObject var backdrop: MenuBackdrop
    var onPlay: () -> Void
    var onContinue: () -> Void = {}
    var onTutorial: () -> Void = {}
    @State private var offerTutorial = false
    @State private var saved = SaveStore.info
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var appear = false
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ZStack {
                MenuBackground(backdrop: backdrop, dim: 0.5)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .semibold)).padding(10)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }.buttonStyle(.plain).foregroundColor(.white.opacity(0.8)).accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, 18).padding(.top, 10)
                    Spacer()
                    Wordmark(wide: wide)
                        .padding(.vertical, 26).padding(.horizontal, 30)
                        .background(Ellipse().fill(Color.black.opacity(0.5)).blur(radius: 30))
                        .scaleEffect(appear ? 1 : 0.92).opacity(appear ? 1 : 0)
                    Spacer()
                    VStack(spacing: 14) {
                        if let sv = saved {
                            Button { SoundEngine.shared?.play("built", at: nil, minGap: 0); onContinue() } label: {
                                VStack(spacing: 3) {
                                    Text("CONTINUE").font(.system(size: 22, weight: .black)).tracking(8)
                                    Text(sv.line).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).opacity(0.75)
                                }
                                .frame(maxWidth: 300).padding(.vertical, 11)
                                .background(Chamfer(cut: 14).fill(LinearGradient(colors: [Theme.faction(sv.playerFaction), Theme.faction(sv.playerFaction).opacity(0.65)], startPoint: .top, endPoint: .bottom)))
                                .overlay(Chamfer(cut: 14).stroke(Color.white.opacity(0.65), lineWidth: 1))
                                .shadow(color: Theme.faction(sv.playerFaction).opacity(0.55), radius: 14)
                                .foregroundColor(.black)
                            }
                            .buttonStyle(.plain).accessibilityLabel("CONTINUE")
                        }
                        Button {
                            SoundEngine.shared?.play("built", at: nil, minGap: 0)
                            // First time: offer the tutorial.
                            // Offer the tutorial until the player ticks "Don't show this again" (it stays in How to Play).
                            if !UserDefaults.standard.bool(forKey: "tutorial.hideOffer") && !ProcessInfo.processInfo.arguments.contains("-uitest") {
                                withAnimation(.easeOut(duration: 0.2)) { offerTutorial = true }
                            } else { onPlay() }
                        } label: {
                            Text(saved == nil ? "PLAY" : "NEW BATTLE").font(.system(size: saved == nil ? 24 : 18, weight: .black)).tracking(saved == nil ? 10 : 6)
                                .frame(maxWidth: 300).padding(.vertical, 16)
                                .background(Chamfer(cut: 14).fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.65)], startPoint: .top, endPoint: .bottom)))
                                .overlay(Chamfer(cut: 14).stroke(Color.white.opacity(0.65), lineWidth: 1))
                                .shadow(color: Theme.accent.opacity(0.6), radius: 16)
                                .foregroundColor(.black)
                        }
                        .buttonStyle(.plain).accessibilityLabel(saved == nil ? "PLAY" : "NEW BATTLE")
                        Button { SoundEngine.shared?.play("click", at: nil); showHelp = true } label: {
                            Text("HOW TO PLAY").font(.system(size: 15, weight: .heavy)).tracking(5)
                                .frame(maxWidth: 300).padding(.vertical, 13)
                                .background(Chamfer(cut: 12).fill(Color.black.opacity(0.55)))
                                .overlay(Chamfer(cut: 12).stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 30)
                    .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 20)
                    Spacer().frame(height: wide ? 80 : 60)
                    HStack(spacing: 16) {
                        ForEach(Faction.allCases, id: \.self) { f in
                            Text(GameData.shared.faction(f).name.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(2).foregroundColor(Theme.faction(f).opacity(0.8))
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView(onTutorial: onTutorial) }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 16) { Text("Settings").font(.title3.bold()); AudioSettings() }.padding(30).presentationDetents([.medium])
        }
        .overlay {
            if offerTutorial {
                TutorialOffer(onTutorial: { offerTutorial = false; onTutorial() },
                              onSkip: { offerTutorial = false; onPlay() },
                              onDismiss: { withAnimation(.easeOut(duration: 0.2)) { offerTutorial = false } })
                    .transition(.opacity)
            }
        }
        .onAppear { saved = SaveStore.info; withAnimation(.easeOut(duration: 0.9)) { appear = true } }
    }
}

/// "New to Meridian?" card shown on Play, with an opt-out. The tutorial is always available from How to Play.
struct TutorialOffer: View {
    var onTutorial: () -> Void
    var onSkip: () -> Void
    var onDismiss: () -> Void
    @State private var hide = UserDefaults.standard.bool(forKey: "tutorial.hideOffer")

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "graduationcap.fill").font(.system(size: 30)).foregroundColor(Theme.gold)
                Text("NEW TO MERIDIAN?").font(.system(size: 17, weight: .black)).tracking(4).foregroundColor(.white)
                Text("Boot Camp teaches the basics by playing a short guided match.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.75)).multilineTextAlignment(.center)
                Button { SoundEngine.shared?.play("built", at: nil, minGap: 0); onTutorial() } label: {
                    Text("PLAY THE 5-MINUTE TUTORIAL").font(.system(size: 14, weight: .heavy)).tracking(2)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Chamfer(cut: 10).fill(Theme.gold))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain).accessibilityLabel("Play the tutorial")
                Button { SoundEngine.shared?.play("click", at: nil); onSkip() } label: {
                    Text("SKIP TO BATTLE SETUP").font(.system(size: 13, weight: .heavy)).tracking(2)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Chamfer(cut: 10).fill(Color.black.opacity(0.5)))
                        .overlay(Chamfer(cut: 10).stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain).accessibilityLabel("Skip to battle setup")
                Button {
                    hide.toggle()
                    UserDefaults.standard.set(hide, forKey: "tutorial.hideOffer")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: hide ? "checkmark.square.fill" : "square").font(.system(size: 17))
                            .foregroundColor(hide ? Theme.gold : .white.opacity(0.7))
                        Text("Don't show this again").font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Don't show this again").accessibilityValue(hide ? "On" : "Off")
                Text("You can always find the tutorial under How to Play.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(Chamfer(cut: 16).fill(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.96)))
            .overlay(Chamfer(cut: 16).stroke(Theme.gold.opacity(0.55), lineWidth: 1.2))
            .padding(24)
        }
    }
}

// MARK: - Battle setup ("Play")

struct SetupView: View {
    @Binding var settings: GameSettings
    @Binding var watch: Bool
    @ObservedObject var backdrop: MenuBackdrop
    var onBack: () -> Void
    var onDeploy: () -> Void
    let data = GameData.shared

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ZStack {
                MenuBackground(backdrop: backdrop, dim: 0.62)
                VStack(spacing: 0) {
                    HStack {
                        Button { SoundEngine.shared?.play("cancel", at: nil); onBack() } label: {
                            HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("BACK").tracking(2) }
                                .font(.system(size: 13, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Chamfer(cut: 6).fill(Color.black.opacity(0.5)))
                        }.buttonStyle(.plain).foregroundColor(.white).accessibilityLabel("BACK")
                        Spacer()
                        Text("NEW BATTLE").font(.system(size: 14, weight: .black)).tracking(5).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Color.clear.frame(width: 80, height: 1)
                    }
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
                    ScrollView {
                        VStack(spacing: 16) {
                            section(watch ? "COMMANDER 1" : "YOUR FACTION")
                            factionGrid(selection: $settings.playerFaction, wide: wide)
                            section(settings.slots.count > 2 ? "OTHER COMMANDERS" : "OPPONENT")
                            commanders
                            GlassPanel(accent: Theme.faction(settings.playerFaction), padding: 12) {
                                VStack(alignment: .leading, spacing: 12) {
                                    labeled("VICTORY") {
                                        Picker("Victory", selection: $settings.victory) { ForEach(VictoryMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                                            .pickerStyle(.segmented).accessibilityIdentifier("victoryMode")
                                        Text(settings.victory.blurb).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    labeled("MATCH LENGTH") {
                                        Picker("Match length", selection: $settings.quick) {
                                            Text("Standard").tag(false); Text("Quick").tag(true)
                                        }.pickerStyle(.segmented).accessibilityIdentifier("matchLength")
                                        Text(settings.quick ? "About 10 minutes: a smaller map, richer starts and everything built faster."
                                                            : "The full campaign for the map: room to expand, scout and outthink.")
                                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    labeled("DIFFICULTY") {
                                        Picker("Difficulty", selection: $settings.difficulty) { ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                                        Text(settings.difficulty.blurb).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    labeled("BATTLEFIELD") {
                                        Picker("Map", selection: $settings.layout) { ForEach(MapLayout.playable, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                                        Text("\(settings.layout.blurb) \(settings.slots.count)-commander version, \(settings.mapSize)×\(settings.mapSize) tiles.")
                                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    labeled("TEMPERAMENT") {
                                        Picker("Temperament", selection: $settings.strategy) { ForEach(AIStrategy.allCases, id: \.self) { Text($0.temperament).tag($0) } }.pickerStyle(.segmented)
                                        Text(settings.strategy.temperamentBlurb).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    Toggle(isOn: $watch) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("AI VS AI").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
                                            Text("Sit back and watch the computer commanders fight.").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                        }
                                    }
                                    .tint(Theme.faction(settings.playerFaction))
                                    .accessibilityIdentifier("aiVsAi")
                                }
                            }
                            .padding(.horizontal)
                            if !settings.hasOpposingTeams {
                                Text("Everyone is on the same team — give at least one commander another team.")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange).multilineTextAlignment(.center).padding(.horizontal)
                            }
                            Button { SoundEngine.shared?.play("built", at: nil, minGap: 0); onDeploy() } label: {
                                Text(watch ? "WATCH" : "DEPLOY").font(.system(size: 21, weight: .black)).tracking(6)
                                    .frame(maxWidth: 380).padding(.vertical, 15)
                                    .background(Chamfer(cut: 14).fill(LinearGradient(colors: [Theme.faction(settings.playerFaction), Theme.faction(settings.playerFaction).opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                                    .overlay(Chamfer(cut: 14).stroke(Color.white.opacity(0.6), lineWidth: 1))
                                    .shadow(color: Theme.faction(settings.playerFaction).opacity(0.6), radius: 14)
                                    .foregroundColor(.black)
                            }
                            .buttonStyle(.plain)
                            .disabled(!settings.hasOpposingTeams)
                            .opacity(settings.hasOpposingTeams ? 1 : 0.4)
                            .accessibilityLabel(watch ? "WATCH" : "DEPLOY")
                            .padding(.top, 4)
                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    func section(_ s: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.faction(settings.playerFaction)).frame(width: 14, height: 2)
            Text(s).font(.system(size: 11, weight: .heavy)).tracking(4).foregroundColor(.white.opacity(0.75))
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }.padding(.horizontal)
    }

    /// Teams are shown as letters, in the colour of the player's own team's first member.
    static let teamNames = ["A", "B", "C", "D"]

    /// The commander roster: the player's team, then every computer commander with a faction and a team,
    /// plus an Add button for up to four in all.
    var commanders: some View {
        VStack(spacing: 8) {
            teamRow(0, label: watch ? "Commander 1" : "You")
            ForEach(Array(settings.slots.indices.dropFirst()), id: \.self) { i in
                commanderRow(i)
            }
            if settings.slots.count < MatchConfig.maxPlayers {
                Button { settings.addSlot(); SoundEngine.shared?.play("click", at: nil) } label: {
                    HStack(spacing: 6) { Image(systemName: "plus.circle.fill"); Text("ADD COMMANDER").tracking(2) }
                        .font(.system(size: 12, weight: .heavy)).padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(Chamfer(cut: 10).fill(Color.black.opacity(0.5)))
                        .overlay(Chamfer(cut: 10).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain).foregroundColor(.white).accessibilityLabel("Add commander").accessibilityIdentifier("addCommander")
            }
            Text(teamSummary).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// "2v2", "Free-for-all", "You and 1 ally against 2".
    var teamSummary: String {
        let n = settings.slots.count
        let sizes = Dictionary(grouping: settings.slots, by: { $0.team }).values.map { $0.count }.sorted(by: >)
        if n == 2 { return "A classic duel." }
        if sizes.count == n { return "Free-for-all: \(n) commanders, every one for themselves." }
        if sizes.count == 1 { return "" }
        return sizes.map(String.init).joined(separator: "v") + (watch ? "" : " — you have \(settings.allyIndices.count) \(settings.allyIndices.count == 1 ? "ally" : "allies") against \(settings.enemyIndices.count).")
    }

    /// Slot 0: only the team can change here (the faction is picked above).
    func teamRow(_ i: Int, label: String) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundColor(Theme.faction(settings.slots[i].faction))
                .frame(minWidth: 70, alignment: .leading)
            Text(data.faction(settings.slots[i].faction).name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            teamPicker(i)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Chamfer(cut: 10).fill(Color.black.opacity(0.55)))
        .overlay(Chamfer(cut: 10).stroke(Theme.faction(settings.slots[i].faction).opacity(0.6), lineWidth: 1))
        .foregroundColor(.white)
    }

    /// A computer commander: faction, team and (when there are more than two commanders) a remove button.
    func commanderRow(_ i: Int) -> some View {
        let f = settings.slots[i].faction
        let ally = settings.slots[i].team == settings.slots[0].team
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text((watch ? "COMMANDER \(i + 1)" : (ally ? "ALLY" : "OPPONENT")) + " · AI").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundColor(Theme.faction(f))
                Spacer(minLength: 4)
                teamPicker(i)
                if settings.slots.count > 2 {
                    Button { settings.removeSlot(i); SoundEngine.shared?.play("cancel", at: nil) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.white.opacity(0.55))
                    }.buttonStyle(.plain).accessibilityLabel("Remove commander \(i + 1)")
                }
            }
            Picker("Faction", selection: Binding(get: { settings.slots[i].faction }, set: { settings.slots[i].faction = $0; SoundEngine.shared?.play("click", at: nil) })) {
                ForEach(Faction.allCases, id: \.self) { Text(data.faction($0).name).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("faction\(i)")
            Text(data.faction(f).tagline.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(2).foregroundColor(Theme.faction(f))
        }
        .padding(12)
        .background(Chamfer(cut: 10).fill(ally ? Theme.faction(settings.playerFaction).opacity(0.12) : Color.black.opacity(0.55)))
        .overlay(Chamfer(cut: 10).stroke(Theme.faction(f).opacity(0.5), lineWidth: 1))
        .foregroundColor(.white)
    }

    /// Four team letters; the selected one is lit.
    func teamPicker(_ i: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<MatchConfig.maxPlayers, id: \.self) { t in
                let on = settings.slots[i].team == t
                Button { settings.slots[i].team = t; SoundEngine.shared?.play("click", at: nil) } label: {
                    Text(SetupView.teamNames[t]).font(.system(size: 11, weight: .heavy))
                        .frame(width: 26, height: 24)
                        .background(Chamfer(cut: 5).fill(on ? Theme.accent : Color.white.opacity(0.08)))
                        .foregroundColor(on ? .black : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Team \(SetupView.teamNames[t])")
                .accessibilityIdentifier("team\(i)_\(t)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
            c()
        }
    }

    func showcase(_ f: Faction) -> [Int] {
        let ids = ["humans": ["h_ranger", "h_bastion", "h_harrier"], "machines": ["m_arc", "m_bulwark", "m_vector"], "aliens": ["a_mantis", "a_colossus", "a_blightwing"]][f.rawValue]!
        return ids.compactMap { data.unitIndex[$0] }
    }

    func factionGrid(selection: Binding<Faction>, wide: Bool, compact: Bool = false) -> some View {
        let cols = wide || compact ? 3 : 1
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
            ForEach(Faction.allCases, id: \.self) { f in
                let fd = data.faction(f)
                let on = selection.wrappedValue == f
                Button { selection.wrappedValue = f; SoundEngine.shared?.play("click", at: nil) } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fd.name).font(.system(size: compact ? 13 : 18, weight: .heavy))
                            Text(fd.tagline.uppercased()).font(.system(size: compact ? 8 : 10, weight: .heavy)).tracking(2).foregroundColor(Theme.faction(f))
                            if !compact {
                                Text(fd.description).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if !compact {
                            HStack(spacing: -12) {
                                ForEach(showcase(f), id: \.self) { u in
                                    if let img = TextureBank.portrait(u, team: 0) { Image(decorative: img, scale: 2).resizable().scaledToFit().frame(width: 52, height: 52) }
                                }
                            }
                        }
                    }
                    .padding(compact ? 10 : 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Chamfer(cut: 12).fill(on ? Theme.faction(f).opacity(0.2) : Color.black.opacity(0.55)))
                    .overlay(Chamfer(cut: 12).stroke(on ? Theme.faction(f) : Color.white.opacity(0.12), lineWidth: on ? 2 : 1))
                    .shadow(color: on ? Theme.faction(f).opacity(0.45) : .clear, radius: 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
    }
}
