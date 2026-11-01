import SwiftUI
import QuartzCore
import MeridianCore

/// Live portrait of the selected unit: looks around and blinks on its own, and talks in time with its radio line.
struct UnitPortraitView: View {
    let unitID: String
    let unitType: Int
    let owner: Int
    var size: CGFloat = 72
    @ObservedObject var radio: Radio
    /// Bumped by the long-press toggle so the view redraws with the other portrait style at once.
    @State private var styleFlip = false
    @State private var flash: String? = nil

    var body: some View {
        let team = TeamColor.rgb(owner)
        let seed = unitType &* 37 &+ 11
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            Canvas { ctx, sz in
                ctx.withCGContext { cg in
                    cg.translateBy(x: 0, y: sz.height)
                    cg.scaleBy(x: sz.width / 40, y: -sz.height / 40)
                    cg.setLineJoin(.round); cg.setLineCap(.round)
                    let pose = PortraitArt.Pose(look: PortraitArt.look(t, seed: seed),
                                                blink: PortraitArt.blink(t, seed: seed),
                                                mouth: radio.mouth(at: CACurrentMediaTime(), unitType: unitType),
                                                t: t)
                    // The 3D model's portrait, else painted layers when this unit has them, else the Swift-drawn one.
                    if !LayeredPortrait.preferOriginal, let mp = ModelPortrait.portrait(for: unitID, team: team) {
                        mp.draw(cg, pose: pose)
                    } else if !LayeredPortrait.preferOriginal, let lp = LayeredPortrait.portrait(for: unitID) {
                        lp.draw(cg, pose: pose, team: team)
                    } else {
                        PortraitArt.draw(Pen(cg, 40, 40), unit: unitID, team: team, pose: pose)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Chamfer(cut: 9))
        .overlay(Chamfer(cut: 9).stroke(Theme.team(owner).opacity(0.85), lineWidth: 1.4))
        .overlay(alignment: .topTrailing) {
            if radio.line?.unitType == unitType {
                Circle().fill(Color(red: 0.4, green: 1, blue: 0.5)).frame(width: 5, height: 5).padding(5)
                    .shadow(color: .green, radius: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if let f = flash {
                Text(f).font(.system(size: 8, weight: .heavy)).tracking(1).foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2).background(Color.black.opacity(0.7)).padding(.bottom, 3)
            }
        }
        // Long-press compares the 3D or painted portrait with the original (only for units that have one).
        .onLongPressGesture(minimumDuration: 0.8) {
            let model = ModelPortrait.has(unitID)
            guard model || LayeredPortrait.portrait(for: unitID) != nil else { return }
            LayeredPortrait.preferOriginal.toggle()
            styleFlip.toggle()
            flash = LayeredPortrait.preferOriginal ? "ORIGINAL" : (model ? "3D" : "PAINTED")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flash = nil }
        }
        .id(styleFlip)
        .accessibilityHidden(true)
    }
}

/// The current radio line as a subtitle above the selection panel.
struct RadioSubtitle: View {
    @ObservedObject var radio: Radio
    let accent: Color

    var body: some View {
        if let l = radio.line {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10, weight: .bold)).foregroundColor(accent)
                Text(l.speaker.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(accent.opacity(0.9))
                Text(l.faction == .aliens ? "‹\(l.text)›" : "“\(l.text)”")
                    .font(.system(size: 12, weight: .semibold).italic()).foregroundColor(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Chamfer(cut: 6).fill(Color.black.opacity(0.62)))
            .overlay(Chamfer(cut: 6).stroke(accent.opacity(0.5), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .id(l.id)
            .allowsHitTesting(false)
        }
    }
}
