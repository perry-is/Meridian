import SwiftUI
import MeridianCore

/// Isometric minimap: terrain, fog, units, sites, camera footprint. Tap or drag to move the camera.
struct MinimapView: View {
    @ObservedObject var controller: GameController
    let scene: GameScene
    @State private var terrain: CGImage? = nil

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let n = Double(controller.world.map.size)
            // World (x,y) -> minimap point. Pixel (i,j) of an N×N image maps the same way.
            let s = min(W / (2 * n), H / n)
            let ox = (W - s * 2 * n) / 2, oy = H / 2
            let tf = CGAffineTransform(a: s, b: s / 2, c: s, d: -s / 2, tx: ox, ty: oy)
            Canvas { ctx, _ in
                _ = controller.minimapVersion
                if let t = terrain {
                    var c = ctx
                    c.concatenate(tf)
                    c.draw(Image(decorative: t, scale: 1), in: CGRect(x: 0, y: 0, width: n, height: n))
                    c.draw(Image(decorative: fogImage(), scale: 1), in: CGRect(x: 0, y: 0, width: n, height: n))
                }
                func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(tf) }
                for (i, site) in controller.world.sites.enumerated() {
                    let p = pt(site.x, site.y)
                    let col = site.owner >= 0 ? Theme.team(site.owner) : Color.white.opacity(0.7)
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 2.5, width: 8, height: 5)), with: .color(col), lineWidth: controller.selectedSite == i ? 2.5 : 1.5)
                }
                for d in controller.minimapDots() {
                    let p = pt(d.x, d.y)
                    let r: CGFloat = d.building ? 2.6 : 1.4
                    ctx.fill(Path(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Theme.team(d.owner)))
                }
                for ping in controller.attackPings {
                    let p = pt(ping.x, ping.y)
                    let age = controller.world.time - ping.t
                    let r = 4 + age * 3
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.red.opacity(max(0, 1 - age / 6))), lineWidth: 1.5)
                }
                let q = scene.visibleWorldQuad()
                if q.count == 4 {
                    var path = Path()
                    path.move(to: pt(q[0].0, q[0].1))
                    for k in 1..<4 { path.addLine(to: pt(q[k].0, q[k].1)) }
                    path.closeSubpath()
                    ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.panelStroke))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let w = v.location.applying(tf.inverted())
                scene.focus(Double(w.x), Double(w.y))
            })
            .onAppear { if terrain == nil { terrain = terrainImage() } }
        }
    }

    func terrainImage() -> CGImage {
        let m = controller.world.map
        let n = m.size
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let t = m.terrainAt(x, y)
                var c: (UInt8, UInt8, UInt8)
                switch t {
                case .grass: c = (60, 105, 55)
                case .dirt: c = (115, 92, 64)
                case .moss: c = (45, 90, 70)
                case .rock: c = (70, 66, 64)
                case .water: c = (30, 72, 110)
                }
                if m.elevation[m.idx(x, y)] > 0 && t.groundPassable { c = (c.0 &+ 14, c.1 &+ 14, c.2 &+ 10) }
                let i = (y * n + x) * 4
                px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2; px[i + 3] = 255
            }
        }
        for r in m.resources {
            let i = (r.y * n + r.x) * 4
            switch r.kind {
            case .iron: px[i] = 170; px[i + 1] = 180; px[i + 2] = 200
            case .gold: px[i] = 250; px[i + 1] = 210; px[i + 2] = 70
            case .wood: px[i] = 28; px[i + 1] = 70; px[i + 2] = 40
            }
        }
        return Self.image(px, n)
    }

    func fogImage() -> CGImage {
        let p = controller.world.players[controller.me]
        let n = controller.world.map.size
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let a: UInt8 = p.visible[i] > 0 ? 0 : (p.explored[i] ? 120 : 235)
            px[i * 4 + 3] = a
        }
        return Self.image(px, n)
    }

    static func image(_ px: [UInt8], _ n: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
}

struct TechTreeView: View {
    @ObservedObject var controller: GameController
    @Environment(\.dismiss) var dismiss
    var body: some View {
        let w = controller.world
        let p = w.players[controller.me]
        let data = w.data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(data.faction(p.faction).description).font(.callout).foregroundColor(.secondary)
                    ForEach(1...3, id: \.self) { tier in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIER \(tier)").font(.system(size: 12, weight: .heavy)).tracking(3).foregroundColor(Theme.faction(p.faction))
                            let units = data.unitIDs(p.faction).filter { unitTier(data.units[$0], data) == tier }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                                ForEach(units, id: \.self) { u in
                                    let d = data.units[u]
                                    let miss = p.missing(d.requires, data)
                                    TechCard(title: d.name, subtitle: "\(d.role.capitalized) · \(d.producedAt.rawValue)", detail: "\(d.description)\nStrong: \(d.strongVs)\nWeak: \(d.weakVs)",
                                             cost: d.cost, status: miss.isEmpty ? "Available" : "Needs " + miss.joined(separator: ", "), ok: miss.isEmpty, icon: TextureBank.cache.values.first?.unitIcons[u])
                                }
                                ForEach(data.upgradeIDs(p.faction).filter { data.upgrades[$0].tier == tier }, id: \.self) { g in
                                    let d = data.upgrades[g]
                                    let st = p.completedUpgrades.contains(g) ? "Researched" : (p.researching.contains(g) ? "Researching…" : (w.upgradeAvailability(controller.me, g) ?? "Available at \(d.researchedAt.rawValue)"))
                                    TechCard(title: d.name, subtitle: "Upgrade · \(d.researchedAt.rawValue)", detail: d.description + (d.exclusiveWith.map { "\nExclusive with \(data.upgrades[data.upgradeIndex[$0]!].name)" } ?? ""),
                                             cost: d.cost, status: st, ok: p.completedUpgrades.contains(g), icon: nil)
                                }
                            }
                        }
                    }
                }.padding()
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("\(data.faction(p.faction).name) Tech")
            .toolbar { ToolbarItem { Button("Close") { dismiss() } } }
        }
    }

    func unitTier(_ u: UnitDef, _ data: GameData) -> Int {
        if u.requires.contains(where: { $0.hasSuffix("tier3") }) { return 3 }
        if u.requires.contains(where: { $0.hasSuffix("tier2") }) || [.heavy, .air].contains(u.producedAt) { return 2 }
        return 1
    }
}

struct TechCard: View {
    let title: String, subtitle: String, detail: String
    let cost: Cost
    let status: String
    let ok: Bool
    let icon: CGImage?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let i = icon { Image(decorative: i, scale: 2).resizable().scaledToFit().frame(width: 40, height: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
                CostLine(cost: cost)
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(status).font(.system(size: 10, weight: .semibold)).foregroundColor(ok ? .green : .orange)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Chamfer(cut: 9).fill(LinearGradient(colors: [Color.white.opacity(ok ? 0.09 : 0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
        .overlay(Chamfer(cut: 9).stroke(ok ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
    }
}
