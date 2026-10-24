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
                    PortraitArt.draw(Pen(cg, 40, 40), unit: unitID, team: team, pose: pose)
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
