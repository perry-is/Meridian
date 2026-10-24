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
        "Drag two fingers to draw a selection box. One finger moves the camera.",
        "Captured sites trickle all three resources. Hold most of them to win by dominance.",
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

struct LoadingView: View {
    let title: String
    let step: String
    let progress: Double
    var tip: String? = nil
    var accent: Color = Theme.accent
    var body: some View {
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
                            if !UserDefaults.standard.bool(forKey: "tutorial.offered") && !ProcessInfo.processInfo.arguments.contains("-uitest") {
                                UserDefaults.standard.set(true, forKey: "tutorial.offered"); offerTutorial = true
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
        .confirmationDialog("New to Meridian?", isPresented: $offerTutorial, titleVisibility: .visible) {
            Button("Play the 5-minute tutorial") { onTutorial() }
            Button("Skip to battle setup") { onPlay() }
        } message: { Text("Boot Camp teaches the basics by playing a short guided match.") }
        .onAppear { saved = SaveStore.info; withAnimation(.easeOut(duration: 0.9)) { appear = true } }
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
                            section(watch ? "SIDE A" : "YOUR FACTION")
                            factionGrid(selection: $settings.playerFaction, wide: wide)
                            section(watch ? "SIDE B" : "OPPONENT")
                            factionGrid(selection: $settings.aiFaction, wide: wide, compact: true)
                            GlassPanel(accent: Theme.faction(settings.playerFaction), padding: 12) {
                                VStack(alignment: .leading, spacing: 12) {
                                    labeled("DIFFICULTY") {
                                        Picker("Difficulty", selection: $settings.difficulty) { ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                                        Text(settings.difficulty.blurb).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    labeled("BATTLEFIELD") {
                                        Picker("Map", selection: $settings.layout) { ForEach(MapLayout.playable, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                                    }
                                    labeled("TEMPERAMENT") {
                                        Picker("Temperament", selection: $settings.strategy) { ForEach(AIStrategy.allCases, id: \.self) { Text($0.temperament).tag($0) } }.pickerStyle(.segmented)
                                        Text(settings.strategy.temperamentBlurb).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                    }
                                    Toggle(isOn: $watch) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("AI VS AI").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundColor(.white.opacity(0.55))
                                            Text("Sit back and watch two computer commanders fight.").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                        }
                                    }
                                    .tint(Theme.faction(settings.playerFaction))
                                    .accessibilityIdentifier("aiVsAi")
                                }
                            }
                            .padding(.horizontal)
                            Button { SoundEngine.shared?.play("built", at: nil, minGap: 0); onDeploy() } label: {
                                Text(watch ? "WATCH" : "DEPLOY").font(.system(size: 21, weight: .black)).tracking(6)
                                    .frame(maxWidth: 380).padding(.vertical, 15)
                                    .background(Chamfer(cut: 14).fill(LinearGradient(colors: [Theme.faction(settings.playerFaction), Theme.faction(settings.playerFaction).opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                                    .overlay(Chamfer(cut: 14).stroke(Color.white.opacity(0.6), lineWidth: 1))
                                    .shadow(color: Theme.faction(settings.playerFaction).opacity(0.6), radius: 14)
                                    .foregroundColor(.black)
                            }
                            .buttonStyle(.plain)
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
