import CoreGraphics
import Foundation
import MeridianCore

/// Twilight Frontier environment art: mesas, alien flora, timber, ore and atmosphere textures.
enum EnvironmentArt {
    static let sun = RGB(1.0, 0.86, 0.62)
    static let shadow = RGB(0.10, 0.08, 0.16, 0.38)

    static func groundShadow(_ p: Pen, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        // Shadows fall to the lower right (light from the upper left).
        p.fill(p.ellipsePath(cx + rx * 0.25, cy - ry * 0.15, rx, ry), shadow)
    }

    // MARK: Cliffs (mesa chunks with strata). Variants 0-2 edge, 3-5 interior spires.

    static func cliff(_ v: Int) -> CGImage {
        let tall = v >= 3
        let W: CGFloat = 104, H: CGFloat = tall ? 140 : 100
        return Pen.image(W, H) { p in
            let palettes = [RGB(0.46, 0.42, 0.48), RGB(0.52, 0.44, 0.42), RGB(0.42, 0.42, 0.50)]
            let base = palettes[v % 3]
            groundShadow(p, 56, 20, 46, 15)
            // A cluster of faceted boulders, back to front; tall variants stack a spire on top.
            var chunks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(36, 30, 26, 30), (66, 28, 24, 26), (52, 18, 30, 22)]
            if tall { chunks.insert((52, 54, 22, 62), at: 0); chunks.insert((40, 40, 18, 40), at: 1) }
            for (k, (cx, by, r, h)) in chunks.enumerated() {
                let j = { (q: Int) -> CGFloat in (hnoise(q, v * 7 + k, 5) - 0.5) * r * 0.35 }
                let top = by + h
                // Silhouette points around the chunk.
                let pts: [(CGFloat, CGFloat)] = [(cx - r, by + j(1)), (cx - r * 0.9 + j(2), by + h * 0.55), (cx - r * 0.45 + j(3), top + j(4) * 0.4),
                                                 (cx + r * 0.2 + j(5), top + 4 + j(6) * 0.4), (cx + r * 0.85 + j(7), by + h * 0.6), (cx + r, by + j(8)), (cx + j(9) * 0.5, by - 6)]
                p.shade(p.poly(pts), base.mix(sun, 0.10), outline: RGB(0.07, 0.05, 0.10, 0.85), lw: 1.3, top: 0.18, bottom: 0.25)
                // Shaded right facet and lit top facet.
                p.shade(p.poly([(cx + r * 0.2 + j(5), top + 4 + j(6) * 0.4), (cx + r * 0.85 + j(7), by + h * 0.6), (cx + r, by + j(8)), (cx + j(9) * 0.5, by - 6), (cx + r * 0.05, by + h * 0.45)]),
                        base.dark(0.42).mix(RGB(0.2, 0.22, 0.42), 0.25), outline: nil, top: 0.02, bottom: 0.1)
                p.shade(p.poly([(cx - r * 0.45 + j(3), top + j(4) * 0.4), (cx + r * 0.2 + j(5), top + 4 + j(6) * 0.4), (cx + r * 0.05, by + h * 0.45), (cx - r * 0.7, by + h * 0.62)]),
                        base.light(0.25).mix(sun, 0.25), outline: nil, top: 0.15, bottom: 0.0)
                // Cracks.
                p.line((cx - r * 0.5, by + h * 0.35), (cx - r * 0.15, by + h * 0.15), base.dark(0.5).alpha(0.7), 1.1)
                if k % 2 == 0 { p.line((cx + r * 0.1, by + h * 0.8), (cx + r * 0.4, by + h * 0.55), base.dark(0.5).alpha(0.6), 1.0) }
            }
            // Lichen and a rare crystal vein.
            p.fill(p.ellipsePath(30, tall ? 70 : 52, 7, 2.5), RGB(0.45, 0.62, 0.30, 0.8))
            if v % 3 == 1 { p.glow(70, 40, 10, RGB(0.6, 0.85, 1.0, 0.7)); p.shade(p.poly([(66, 34), (70, 48), (74, 34)]), RGB(0.7, 0.9, 1.0)) }
        }
    }

    // MARK: Flora

    /// kinds: 0 golden tuft, 1 teal tuft, 2 reeds, 3 glowcaps, 4 crystal shard. Two variants each.
    static func flora(_ kind: Int, _ v: Int) -> CGImage {
        Pen.image(36, 40) { p in
            switch kind {
            case 0, 1:
                let c = kind == 0 ? RGB(0.62, 0.62, 0.26) : RGB(0.26, 0.55, 0.45)
                for i in 0..<7 {
                    let x = 10 + CGFloat(i) * 2.6 + CGFloat(v) * 2, lean = (CGFloat(i) - 3) * 1.6
                    p.line((x, 6), (x + lean, 16 + hnoise(i, v, kind) * 10), c.mix(RGB(1, 1, 0.8), CGFloat(i % 2) * 0.2), 1.3)
                }
                if kind == 1 { p.dot(14, 25, 1.6, RGB(1, 0.9, 0.6)); p.dot(22, 22, 1.4, RGB(1, 0.9, 0.6)) }
            case 2:
                for i in 0..<5 {
                    let x = 10 + CGFloat(i) * 3.5
                    let h = 20 + hnoise(i, v, 2) * 12
                    p.line((x, 5), (x + 1.5, h), RGB(0.36, 0.48, 0.24), 1.4)
                    if i % 2 == 0 { p.box(x, h - 6, 2.6, 6, RGB(0.45, 0.30, 0.18), r: 1.2) }
                }
            case 3:
                for (i, (x, s)) in [(12.0, 1.0), (20.0, 1.35), (26.0, 0.8)].enumerated() {
                    let cx = CGFloat(x), sz = CGFloat(s)
                    p.line((cx, 5), (cx, 5 + 8 * sz), RGB(0.85, 0.85, 0.75), 2 * sz)
                    p.glow(cx, 13 * sz + 1, 8 * sz, RGB(0.35, 0.95, 0.9, 0.65))
                    p.ellipse(cx, 12 * sz + 2, 5 * sz, 3.2 * sz, i == 1 && v == 1 ? RGB(0.7, 0.45, 1.0) : RGB(0.30, 0.85, 0.80))
                }
            default:
                groundShadow(p, 18, 6, 9, 3)
                p.glow(18, 18, 16, RGB(0.75, 0.6, 1.0, 0.45))
                p.shade(p.poly([(13, 5), (16, 30), (19, 34), (22, 26), (24, 5)]), RGB(0.72, 0.62, 1.0), outline: RGB(0.2, 0.12, 0.35, 0.9))
                p.shade(p.poly([(22, 5), (27, 20), (29, 6)]), RGB(0.62, 0.52, 0.95), outline: RGB(0.2, 0.12, 0.35, 0.9))
                p.line((17, 8), (18, 28), RGB(1, 1, 1, 0.6), 1)
            }
        }
    }

    // MARK: Resources

    static func tree(_ v: Int) -> CGImage {
        Pen.image(64, 104) { p in
            groundShadow(p, 34, 10, 20, 8)
            switch v % 3 {
            case 0: // Teal spire pine
                p.box(29, 6, 6, 22, RGB(0.36, 0.24, 0.16), r: 2)
                let leaf = RGB(0.12, 0.40, 0.40)
                for (i, y) in [(0, 20.0), (1, 38.0), (2, 56.0), (3, 72.0)] as [(Int, CGFloat)] {
                    let w: CGFloat = 26 - CGFloat(i) * 5.5
                    p.shade(p.poly([(32 - w, y), (32, y + 28 - CGFloat(i) * 3), (32 + w, y), (32, y - 5)]), leaf.light(CGFloat(i) * 0.06).mix(EnvironmentArt.sun, 0.06),
                            outline: RGB(0.03, 0.12, 0.12, 0.9))
                    p.line((32 - w * 0.7, y + 2), (32, y + 20 - CGFloat(i) * 3), RGB(0.5, 0.85, 0.75, 0.35), 1.2)
                }
            case 1: // Amber broadleaf
                p.limb((32, 6), (31, 38), RGB(0.40, 0.27, 0.18), 5)
                p.limb((31, 30), (20, 44), RGB(0.40, 0.27, 0.18), 3)
                p.limb((31, 32), (42, 46), RGB(0.40, 0.27, 0.18), 3)
                for (x, y, r) in [(20.0, 50.0, 14.0), (44.0, 52.0, 13.0), (32.0, 62.0, 17.0), (26.0, 72.0, 11.0), (40.0, 72.0, 10.0)] as [(CGFloat, CGFloat, CGFloat)] {
                    p.ellipse(x, y, r, r * 0.85, RGB(0.72, 0.52, 0.20).mix(RGB(0.45, 0.55, 0.20), hnoise(Int(x), Int(y), 1) * 0.5))
                }
                p.highlight(26, 68, 8, 4)
            default: // Twisted lantern tree with glowing pods
                p.limb((32, 6), (36, 28), RGB(0.30, 0.20, 0.26), 6)
                p.limb((36, 28), (26, 52), RGB(0.30, 0.20, 0.26), 4.5)
                p.limb((26, 52), (34, 74), RGB(0.30, 0.20, 0.26), 3.5)
                for (x, y, r) in [(20.0, 56.0, 12.0), (40.0, 46.0, 11.0), (32.0, 78.0, 14.0), (44.0, 66.0, 9.0)] as [(CGFloat, CGFloat, CGFloat)] {
                    p.ellipse(x, y, r, r * 0.8, RGB(0.26, 0.42, 0.30))
                }
                for (x, y) in [(18.0, 50.0), (44.0, 60.0), (30.0, 70.0)] as [(CGFloat, CGFloat)] {
                    p.glow(x, y - 4, 9, RGB(1.0, 0.75, 0.35, 0.75)); p.ellipse(x, y - 4, 2.6, 3.4, RGB(1, 0.85, 0.5))
                }
            }
        }
    }

    static func iron(_ v: Int) -> CGImage {
        Pen.image(72, 60) { p in
            groundShadow(p, 36, 14, 30, 11)
            let rocks: [(CGFloat, CGFloat, CGFloat)] = [[(22, 18, 14), (46, 16, 16), (34, 30, 13)], [(26, 16, 17), (48, 22, 12), (32, 32, 10)], [(18, 20, 11), (38, 18, 17), (54, 24, 9)]][v % 3]
            for (i, (x, y, r)) in rocks.enumerated() {
                let pts = [(x - r, y - r * 0.35), (x - r * 0.7, y + r * 0.55), (x - r * 0.1, y + r * 0.95), (x + r * 0.75, y + r * 0.45), (x + r, y - r * 0.2), (x + r * 0.4, y - r * 0.65)]
                p.shade(p.poly(pts), RGB(0.30, 0.31, 0.36), outline: RGB(0.06, 0.06, 0.09, 0.9), lw: 1.2)
                p.shade(p.poly([(x - r * 0.1, y + r * 0.95), (x + r * 0.75, y + r * 0.45), (x + r, y - r * 0.2), (x + r * 0.4, y - r * 0.65), (x + r * 0.1, y)]), RGB(0.20, 0.20, 0.26), outline: nil)
                // Metallic veins with a cool sheen and rust flecks.
                p.line((x - r * 0.55, y + r * 0.1), (x + r * 0.15, y + r * 0.55), RGB(0.70, 0.82, 0.95), 2.2)
                p.line((x - r * 0.2, y - r * 0.25), (x + r * 0.5, y + r * 0.05), RGB(0.55, 0.68, 0.85, 0.8), 1.4)
                p.dot(x + r * 0.15, y + r * 0.55, 2.2, RGB(0.95, 0.98, 1.0))
                p.dot(x - r * 0.4, y - r * 0.2, 1.8, RGB(0.78, 0.40, 0.18))
                if i == 0 { p.dot(x + r * 0.3, y + r * 0.2, 1.4, RGB(0.78, 0.40, 0.18)) }
            }
        }
    }

    static func gold(_ v: Int) -> CGImage {
        Pen.image(68, 72) { p in
            groundShadow(p, 34, 12, 26, 10)
            p.glow(34, 30, 32, RGB(1.0, 0.75, 0.25, 0.45))
            p.ellipse(34, 14, 24, 9, RGB(0.32, 0.24, 0.20))        // geode rim
            let shards: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(24, 14, 30, -0.25), (34, 12, 42, 0.0), (44, 14, 28, 0.3), (30, 16, 20, -0.5), (40, 16, 22, 0.55)]
            for (i, (x, y, h, lean)) in shards.enumerated() where !(v == 1 && i == 4) && !(v == 2 && i == 3) {
                let tip = (x + lean * h * 0.4, y + h)
                p.shade(p.poly([(x - 5, y), (x - 4, y + h * 0.7), tip, (x + 4, y + h * 0.7), (x + 5, y)]), RGB(1.0, 0.76, 0.22), outline: RGB(0.38, 0.22, 0.02, 0.9), lw: 1.2)
                p.shade(p.poly([(x, y), tip, (x + 4, y + h * 0.7), (x + 5, y)]), RGB(0.90, 0.55, 0.12), outline: nil)
                p.line((x - 2, y + 3), (tip.0 - 1, tip.1 - 4), RGB(1, 1, 0.85, 0.85), 1.2)
            }
            p.glow(30, 46, 6, RGB(1, 1, 0.9, 0.9))
        }
    }

    // MARK: Atmosphere textures

    static func vignette() -> CGImage {
        Pen.image(256, 256, scale: 1) { p in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.02, green: 0.02, blue: 0.06, alpha: 0), CGColor(srgbRed: 0.02, green: 0.02, blue: 0.06, alpha: 0),
                                                         CGColor(srgbRed: 0.03, green: 0.02, blue: 0.08, alpha: 0.55)] as CFArray, locations: [0, 0.55, 1])!
            p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 181, options: [.drawsAfterEndLocation])
        }
    }

    /// Team marker under every unit: a crisp ring with a soft inner wash (tinted per player at runtime).
    static func teamRing() -> CGImage {
        Pen.image(64, 32) { p in
            p.fill(p.ellipsePath(32, 16, 28, 13), RGB(1, 1, 1, 0.22))
            p.stroke(p.ellipsePath(32, 16, 28, 13), RGB(1, 1, 1, 0.95), 2.4)
            p.stroke(p.ellipsePath(32, 16, 24.5, 11), RGB(1, 1, 1, 0.35), 1)
        }
    }

    static func cloud() -> CGImage {
        Pen.image(256, 128, scale: 1) { p in
            for k in 0..<14 {
                let x = 40 + hnoise(k, 3, 1) * 176, y = 30 + hnoise(k, 3, 2) * 68, r = 22 + hnoise(k, 3, 3) * 30
                p.glow(x, y, r, RGB(0.42, 0.40, 0.55, 0.55))
            }
        }
    }
}
