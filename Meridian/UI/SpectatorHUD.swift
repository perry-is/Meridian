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
                        HStack {
                            side(0, h, alignment: .leading)
                            Spacer()
                            Text(String(format: "%d:%02d", Int(h.time) / 60, Int(h.time) % 60)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                            Spacer()
                            side(1, h, alignment: .trailing)
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

    func side(_ p: Int, _ h: HUDState, alignment: HorizontalAlignment) -> some View {
        let s = p < h.sides.count ? h.sides[p] : (Faction.humans, 0, 0.0, 0)
        return VStack(alignment: alignment, spacing: 1) {
            Text(GameData.shared.faction(s.0).name.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1).foregroundColor(Theme.team(p))
            HStack(spacing: 6) {
                Label("\(s.1)", systemImage: "person.3.fill")
                Label("\(s.3)", systemImage: "scope")
            }.font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    func tug(_ h: HUDState) -> some View {
        let a = h.sides.first?.value ?? 1, b = h.sides.dropFirst().first?.value ?? 1
        let f = CGFloat(a / max(1, a + b))
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.team(1).opacity(0.85))
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
