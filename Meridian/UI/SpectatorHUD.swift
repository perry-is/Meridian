import SwiftUI
import MeridianCore

/// Observer overlay: army strength tug-of-war, follow camera, playback speed and a cinematic (HUD-free) mode.
struct SpectatorHUD: View {
    @ObservedObject var controller: GameController
    let scene: GameScene
    var onQuit: () -> Void
    var onRestart: (() -> Void)?
    @State private var cinematic = false
    @State private var follow = true

    var body: some View {
        let h = controller.hud
        VStack(spacing: 6) {
            if !cinematic {
                GlassPanel(accent: Theme.accent, padding: 8) {
                    VStack(spacing: 5) {
                        HStack(alignment: .top) {
                            teamColumn(teams(h).first ?? 0, h, alignment: .leading)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(String(format: "%d:%02d", Int(h.time) / 60, Int(h.time) % 60)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                                if teams(h).count > 2 {
                                    // Free-for-all with three or four commanders: the middle ones go here.
                                    ForEach(Array(teams(h).dropFirst().dropLast()), id: \.self) { t in teamColumn(t, h, alignment: .center) }
                                }
                            }
                            Spacer()
                            teamColumn(teams(h).last ?? 1, h, alignment: .trailing)
                        }
                        tug(h)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if !cinematic {
                    MinimapFrame(controller: controller, scene: scene, accent: Theme.accent).frame(width: 150, height: 82)
                }
                Spacer()
                if cinematic {
                    pill("HUD", on: true, symbol: "film") { cinematic = false }
                } else {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { s in
                            pill(s == 1 ? "1×" : (s < 1 ? "½×" : "\(Int(s))×"), on: controller.speed == s) { controller.speed = s }
                        }
                    }
                    HStack(spacing: 6) {
                        pill(follow ? "FOLLOW ON" : "FOLLOW OFF", on: follow, symbol: "scope") { follow.toggle(); scene.battleCam.enabled = follow }
                        pill("CINEMA", on: false, symbol: "film") { cinematic = true }
                    }
                    HStack(spacing: 6) {
                        pill(controller.paused ? "PLAY" : "PAUSE", on: controller.paused, symbol: controller.paused ? "play.fill" : "pause.fill") { controller.paused.toggle() }
                        if let r = onRestart { pill("RESTART", on: false, symbol: "arrow.counterclockwise") { r() } }
                        pill("EXIT", on: false, symbol: "xmark") { onQuit() }
                    }
                }
                }
            }
        }
        .padding(8)
        .foregroundColor(.white)
    }

    /// Distinct teams in slot order.
    func teams(_ h: HUDState) -> [Int] {
        var out: [Int] = []
        for s in h.sides where !out.contains(s.team) { out.append(s.team) }
        return out
    }

    /// Every commander on a team, one line each (faction, army size, kills), in their player colour.
    func teamColumn(_ team: Int, _ h: HUDState, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            ForEach(Array(h.sides.enumerated()).filter { $0.element.team == team }, id: \.offset) { p, s in
                VStack(alignment: alignment, spacing: 1) {
                    Text(GameData.shared.faction(s.faction).name.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1)
                        .foregroundColor(Theme.team(p)).strikethrough(s.defeated)
                    HStack(spacing: 6) {
                        Label("\(s.units)", systemImage: "person.3.fill")
                        Label("\(s.kills)", systemImage: "scope")
                    }.font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    /// Army strength of the first team against everyone else.
    func tug(_ h: HUDState) -> some View {
        let first = teams(h).first ?? 0
        let a = h.sides.filter { $0.team == first }.reduce(0.0) { $0 + $1.value }
        let b = h.sides.filter { $0.team != first }.reduce(0.0) { $0 + $1.value }
        let f = CGFloat(a / max(1, a + b))
        let other = h.sides.firstIndex { $0.team != first } ?? 1
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.team(other).opacity(0.85))
                Rectangle().fill(Theme.team(0).opacity(0.85)).frame(width: g.size.width * f)
                Rectangle().fill(Color.white).frame(width: 2).offset(x: g.size.width * f - 1)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.4), value: f)
        .accessibilityLabel("Army strength balance")
    }

    func pill(_ t: String, on: Bool, symbol: String? = nil, _ a: @escaping () -> Void) -> some View {
        Button { a(); SoundEngine.shared?.play("click", at: nil) } label: {
            HStack(spacing: 4) {
                if let s = symbol { Image(systemName: s).font(.system(size: 10, weight: .bold)) }
                Text(t).font(.system(size: 10, weight: .heavy)).tracking(0.5)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Chamfer(cut: 6).fill(on ? Theme.accent.opacity(0.35) : Color.black.opacity(0.65)))
            .overlay(Chamfer(cut: 6).stroke(on ? Theme.accent : Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t)
    }
}
