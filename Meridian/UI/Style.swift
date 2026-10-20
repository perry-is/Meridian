import SwiftUI
import MeridianCore

/// Meridian UI kit: chamfered "tactical glass" panels with faction-tinted edges.
struct Chamfer: Shape {
    var cut: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = min(cut, r.width / 3, r.height / 3)
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

enum Accent {
    static func of(_ f: Faction) -> Color { Theme.faction(f) }
}

struct GlassPanel<Content: View>: View {
    var accent: Color = Theme.accent
    var padding: CGFloat = 8
    var cut: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(
                Chamfer(cut: cut).fill(LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.93), Color(red: 0.03, green: 0.04, blue: 0.07).opacity(0.88)],
                                                      startPoint: .top, endPoint: .bottom))
            )
            .overlay(Chamfer(cut: cut).stroke(LinearGradient(colors: [accent.opacity(0.7), accent.opacity(0.12), Color.white.opacity(0.08)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                // Accent tick in the chamfered corner.
                Path { p in p.move(to: CGPoint(x: 0, y: cut + 6)); p.addLine(to: CGPoint(x: 0, y: cut)); p.addLine(to: CGPoint(x: cut, y: 0)); p.addLine(to: CGPoint(x: cut + 10, y: 0)) }
                    .stroke(accent, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }
}

/// Drawn resource glyphs (iron ingot, gold crystal, timber log).
struct ResourceGlyph: View {
    let kind: Int
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            switch kind {
            case 0:
                var top = Path(); top.move(to: CGPoint(x: w * 0.25, y: h * 0.35)); top.addLine(to: CGPoint(x: w * 0.75, y: h * 0.35)); top.addLine(to: CGPoint(x: w * 0.95, y: h * 0.55)); top.addLine(to: CGPoint(x: w * 0.05, y: h * 0.55)); top.closeSubpath()
                var body = Path(); body.addRect(CGRect(x: w * 0.05, y: h * 0.55, width: w * 0.9, height: h * 0.25))
                ctx.fill(body, with: .color(Color(red: 0.45, green: 0.52, blue: 0.62)))
                ctx.fill(top, with: .color(Color(red: 0.78, green: 0.85, blue: 0.95)))
            case 1:
                var g = Path(); g.move(to: CGPoint(x: w * 0.5, y: h * 0.05)); g.addLine(to: CGPoint(x: w * 0.85, y: h * 0.4)); g.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95)); g.addLine(to: CGPoint(x: w * 0.15, y: h * 0.4)); g.closeSubpath()
                ctx.fill(g, with: .color(Theme.gold))
                var f = Path(); f.move(to: CGPoint(x: w * 0.5, y: h * 0.05)); f.addLine(to: CGPoint(x: w * 0.85, y: h * 0.4)); f.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95)); f.closeSubpath()
                ctx.fill(f, with: .color(Color(red: 0.9, green: 0.55, blue: 0.12)))
            default:
                ctx.fill(Path(roundedRect: CGRect(x: w * 0.08, y: h * 0.3, width: w * 0.84, height: h * 0.4), cornerRadius: h * 0.2), with: .color(Theme.wood))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.7, y: h * 0.3, width: w * 0.22, height: h * 0.4)), with: .color(Color(red: 0.9, green: 0.75, blue: 0.5)))
                ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.75, y: h * 0.38, width: w * 0.12, height: h * 0.24)), with: .color(Color(red: 0.6, green: 0.4, blue: 0.2)), lineWidth: 0.8)
            }
        }
    }
}

struct Chip: View {
    let text: String
    var color: Color = .white
    var body: some View {
        Text(text).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.8)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.8))
            .foregroundColor(color)
    }
}

struct StatChip: View {
    let symbol: String
    let value: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.6))
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07)))
    }
}

/// Unit/building portrait framed with the owner's team colour.
struct Portrait: View {
    let type: Int
    let building: Bool
    let owner: Int
    var size: CGFloat = 52
    var body: some View {
        ZStack {
            Chamfer(cut: 8).fill(RadialGradient(colors: [Theme.team(owner).opacity(0.35), Color.black.opacity(0.6)], center: .center, startRadius: 2, endRadius: size * 0.7))
            if let img = building ? TextureBank.cache.values.first?.buildingIcons[type] : TextureBank.cache.values.first?.unitIcons[type] {
                Image(decorative: img, scale: 2).resizable().scaledToFit().padding(building ? 2 : 4)
            }
            Chamfer(cut: 8).stroke(Theme.team(owner).opacity(0.8), lineWidth: 1.2)
        }
        .frame(width: size, height: size)
    }
}

/// Segmented health bar.
struct HealthBar: View {
    let frac: Double
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(LinearGradient(colors: frac > 0.5 ? [Color(red: 0.35, green: 0.95, blue: 0.45), Color(red: 0.15, green: 0.7, blue: 0.35)]
                                              : (frac > 0.25 ? [.yellow, .orange] : [.red, Color(red: 0.6, green: 0.05, blue: 0.05)]), startPoint: .top, endPoint: .bottom))
                    .frame(width: g.size.width * CGFloat(max(0, min(1, frac))))
                HStack(spacing: 0) { ForEach(0..<10, id: \.self) { _ in Spacer(); Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1) }; Spacer() }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}
