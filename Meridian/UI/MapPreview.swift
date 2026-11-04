import SwiftUI
import MeridianCore

/// Thumbnail of the battlefield the current settings will produce: terrain, resources, strategic sites and each
/// commander's start in their colour with their team letter. The map is generated off the main thread and redrawn
/// whenever the layout, seed, commander count or match length changes, so the setup screen shows the exact ground
/// the match will be fought on.
struct MapPreview: View {
    let layout: MapLayout
    let seed: UInt64
    let players: Int
    let quick: Bool
    let teams: [Int]

    @State private var image: CGImage? = nil
    @State private var starts: [(x: Double, y: Double, player: Int)] = []
    @State private var sites: [(Double, Double)] = []
    @State private var size = MatchConfig.defaultMapSize

    /// Changing any of these regenerates the preview.
    var key: String { "\(layout.rawValue)|\(seed)|\(players)|\(quick)" }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let n = Double(size)
            // Same isometric projection as the in-game minimap.
            let s = min(W / (2 * n), H / n)
            let ox = (W - s * 2 * n) / 2, oy = H / 2
            let tf = CGAffineTransform(a: s, b: s / 2, c: s, d: -s / 2, tx: ox, ty: oy)
            Canvas { ctx, _ in
                guard let img = image else { return }
                var c = ctx
                c.concatenate(tf)
                c.draw(Image(decorative: img, scale: 1), in: CGRect(x: 0, y: 0, width: n, height: n))
                func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(tf) }
                for site in sites {
                    let p = pt(site.0, site.1)
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 2.5, width: 8, height: 5)), with: .color(.white.opacity(0.85)), lineWidth: 1.2)
                }
                for st in starts {
                    let p = pt(st.x, st.y)
                    let col = Theme.team(st.player)
                    let r = CGRect(x: p.x - 8, y: p.y - 5, width: 16, height: 10)
                    ctx.fill(Path(ellipseIn: r), with: .color(col))
                    ctx.stroke(Path(ellipseIn: r), with: .color(.white.opacity(0.9)), lineWidth: 1)
                    let letter = st.player < teams.count ? SetupView.teamNames[min(teams[st.player], SetupView.teamNames.count - 1)] : "?"
                    ctx.draw(Text(letter).font(.system(size: 8, weight: .heavy)).foregroundColor(.black), at: p)
                }
            }
            .opacity(image == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.25), value: image == nil)
            .overlay { if image == nil { ProgressView().tint(.white.opacity(0.7)) } }
        }
        .task(id: key) { await generate() }
        .accessibilityLabel("Battlefield preview: \(layout.title), \(players) commanders, seed \(seed)")
    }

    /// Generates the map and its pixels on a background task; only plain data crosses back to the main actor.
    func generate() async {
        let l = layout, sd = seed, p = players, q = quick
        let result = await Task.detached(priority: .userInitiated) { () -> (px: [UInt8], n: Int, starts: [(Double, Double, Int)], sites: [(Double, Double)]) in
            let m = MapData.generate(layout: l, seed: sd, size: MatchConfig.mapSize(players: p, quick: q), players: p)
            let starts = m.starts.enumerated().map { (Double($0.element.x) + 2, Double($0.element.y) + 2, $0.offset) }
            return (MinimapView.terrainPixels(m), m.size, starts, m.sites.map { ($0.x, $0.y) })
        }.value
        // The settings may have moved on while we drew; a newer task will replace this one.
        guard key == "\(l.rawValue)|\(sd)|\(p)|\(q)" else { return }
        size = result.n
        starts = result.starts.map { (x: $0.0, y: $0.1, player: $0.2) }
        sites = result.sites
        image = MinimapView.image(result.px, result.n)
    }
}
