import CoreGraphics
import Foundation
import MeridianCore

/// Procedural art for buildings, resources, terrain and effects.
enum WorldArt {

    // MARK: Isometric helpers (inside a building canvas for an n-tile footprint)

    /// Tile-local (u,v) plus height z -> canvas point. Matches the scene projection (32(x+y), 16(y-x)).
    static func P(_ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ n: CGFloat) -> (CGFloat, CGFloat) {
        (32 * (u + v), 16 * (v - u) + 16 * n + z)
    }

    /// Iso box lit from the upper left: lit left wall, shaded right wall, both darkening toward the ground;
    /// a recessed roof behind a parapet lip; corner and edge highlights; optional panel seams.
    static func prism(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat, _ z0: CGFloat, _ z1: CGFloat,
                      wall: RGB, roof: RGB, outline: Bool = true, seams: CGFloat = 0.5) {
        let o: RGB? = outline ? RGB(0.05, 0.05, 0.06, 0.85) : nil
        func pt(_ q: (CGFloat, CGFloat)) -> CGPoint { CGPoint(x: q.0, y: q.1) }
        let h = z1 - z0
        // Left wall (faces the sun).
        let L = p.poly([P(u0, v0, z0, n), P(u1, v0, z0, n), P(u1, v0, z1, n), P(u0, v0, z1, n)])
        let lm = P((u0 + u1) / 2, v0, z1, n), lb = P((u0 + u1) / 2, v0, z0, n)
        p.grad(L, wall.light(0.16), wall.dark(0.16), from: pt(lm), to: pt(lb), outline: o, lw: 1.0)
        // Right wall (in shade).
        let R = p.poly([P(u1, v0, z0, n), P(u1, v1, z0, n), P(u1, v1, z1, n), P(u1, v0, z1, n)])
        let rm = P(u1, (v0 + v1) / 2, z1, n), rb = P(u1, (v0 + v1) / 2, z0, n)
        p.grad(R, wall.dark(0.2), wall.dark(0.44), from: pt(rm), to: pt(rb), outline: o, lw: 1.0)
        if seams > 0 && h >= 8 {
            var u = u0 + seams
            while u < u1 - 0.05 { p.line(P(u, v0, z0 + 1.5, n), P(u, v0, z1 - 1.5, n), wall.dark(0.3).alpha(0.45), 0.7); u += seams }
            var v = v0 + seams
            while v < v1 - 0.05 { p.line(P(u1, v, z0 + 1.5, n), P(u1, v, z1 - 1.5, n), wall.dark(0.55).alpha(0.45), 0.7); v += seams }
        }
        // Roof: lighter at the back-left; a parapet lip around a slightly recessed deck.
        let roofPath = p.poly([P(u0, v0, z1, n), P(u1, v0, z1, n), P(u1, v1, z1, n), P(u0, v1, z1, n)])
        p.grad(roofPath, roof.light(0.14), roof.dark(0.12), from: pt(P(u0, v1, z1, n)), to: pt(P(u1, v0, z1, n)), outline: o, lw: 1.0)
        let e = min(0.09, (u1 - u0) * 0.08, (v1 - v0) * 0.08)
        if h >= 10 && e > 0.02 {
            let deck = p.poly([P(u0 + e, v0 + e, z1, n), P(u1 - e, v0 + e, z1, n), P(u1 - e, v1 - e, z1, n), P(u0 + e, v1 - e, z1, n)])
            p.fill(deck, roof.dark(0.1).alpha(0.65))
            p.line(P(u0 + e, v1 - e, z1, n), P(u1 - e, v1 - e, z1, n), RGB(0, 0, 0, 0.25), 1.0)       // inner shadow under the back lip
            p.line(P(u0 + e, v0 + e, z1, n), P(u0 + e, v1 - e, z1, n), RGB(0, 0, 0, 0.18), 1.0)
        }
        // Highlights: the lit top edge of the left wall and the near vertical corner.
        p.line(P(u0, v0, z1, n), P(u1, v0, z1, n), wall.light(0.55).alpha(0.8), 0.8)
        p.line(P(u1, v0, z0 + 1, n), P(u1, v0, z1 - 0.5, n), wall.light(0.3).alpha(0.6), 0.7)
    }

    /// Rooftop machinery: a small box unit with a fan grille.
    static func roofUnit(_ p: Pen, _ n: CGFloat, _ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ s: CGFloat = 0.32, _ c: RGB = RGB(0.62, 0.63, 0.6)) {
        prism(p, n, u, v, u + s, v + s, z, z + s * 18, wall: c, roof: c.light(0.1), seams: 0)
        let t = P(u + s / 2, v + s / 2, z + s * 18, n)
        p.stroke(p.ellipsePath(t.0, t.1, s * 18, s * 9), c.dark(0.45), 0.8)
        p.line((t.0 - s * 14, t.1), (t.0 + s * 14, t.1), c.dark(0.45), 0.7)
    }

    /// Small vent stack.
    static func vent(_ p: Pen, _ n: CGFloat, _ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ h: CGFloat = 7, _ c: RGB = RGB(0.5, 0.5, 0.5)) {
        let b = P(u, v, z, n)
        BuildingArt.cylinder(p, b.0, b.1, 2.6, h, c)
    }

    /// A row of windows / light strips on the front-left face.
    static func strip(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ u1: CGFloat, _ v: CGFloat, _ z: CGFloat, _ c: RGB, _ lw: CGFloat = 2) {
        p.line(P(u0, v, z, n), P(u1, v, z, n), c, lw)
    }

    static func dome(_ p: Pen, _ n: CGFloat, _ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ r: CGFloat, _ c: RGB, tall: CGFloat = 1) {
        let (x, y) = P(u, v, z, n)
        let rx = r * 45, ry = r * 22
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: x, y: y), radius: rx, startAngle: .pi, endAngle: 0, clockwise: true, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: tall * 1.0, tx: 0, ty: 0).translatedBy(x: 0, y: 0))
        let e = CGMutablePath()
        e.addEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
        // Dome = lower ellipse + upper half ellipse stretched.
        let upper = CGPath(ellipseIn: CGRect(x: x - rx, y: y - rx * tall * 0.9, width: rx * 2, height: rx * tall * 1.8), transform: nil)
        p.ctx.saveGState()
        p.ctx.addRect(CGRect(x: x - rx - 2, y: y, width: rx * 2 + 4, height: rx * tall + 4)); p.ctx.clip()
        p.shade(upper, c)
        p.ctx.restoreGState()
        p.shade(e, c.dark(0.1))
        p.ctx.saveGState()
        p.ctx.addRect(CGRect(x: x - rx - 2, y: y, width: rx * 2 + 4, height: rx * tall + 4)); p.ctx.clip()
        p.shade(upper, c, outline: RGB(0.05, 0.05, 0.06, 0.85))
        p.ctx.restoreGState()
        p.highlight(x - rx * 0.35, y + rx * tall * 0.45, rx * 0.25, rx * tall * 0.15)
    }

    /// Foundation slab: a few pixels of visible thickness, a bevelled deck and corner bolts.
    /// Foundation slab: visible thickness, a bevelled deck, corner bolts and a little weathering.
    /// Inset 0.1 tile so the slab's thickness stays inside the canvas at the front corner.
    static func pad(_ p: Pen, _ n: CGFloat, _ c: RGB) {
        let t: CGFloat = 3, a: CGFloat = 0.1, b = n - 0.1
        p.fill(p.poly([P(a, a, -t, n), P(b, a, -t, n), P(b, a, 0, n), P(a, a, 0, n)]), c.dark(0.3))
        p.fill(p.poly([P(b, a, -t, n), P(b, b, -t, n), P(b, b, 0, n), P(b, a, 0, n)]), c.dark(0.48))
        let top = p.poly([P(a, a, 0, n), P(b, a, 0, n), P(b, b, 0, n), P(a, b, 0, n)])
        p.grad(top, c.light(0.08), c.dark(0.06), from: CGPoint(x: P(a, b, 0, n).0, y: P(a, b, 0, n).1), to: CGPoint(x: P(b, a, 0, n).0, y: P(b, a, 0, n).1), outline: RGB(0, 0, 0, 0.4), lw: 0.8)
        let e: CGFloat = 0.12
        p.stroke(p.poly([P(a + e, a + e, 0, n), P(b - e, a + e, 0, n), P(b - e, b - e, 0, n), P(a + e, b - e, 0, n)]), c.light(0.18).alpha(0.5), 0.7)
        for (u, v) in [(a + e * 0.5, a + e * 0.5), (b - e * 0.5, a + e * 0.5), (b - e * 0.5, b - e * 0.5), (a + e * 0.5, b - e * 0.5)] {
            let q = P(u, v, 0, n); p.dot(q.0, q.1, 1.1, c.dark(0.35)); p.dot(q.0 - 0.3, q.1 + 0.3, 0.5, c.light(0.3))
        }
        for k in 0..<Int(n * 3) {
            let q = P(a + hnoise(k, Int(n), 3) * (b - a), a + hnoise(k, Int(n), 4) * (b - a), 0, n)
            p.fill(p.ellipsePath(q.0, q.1, 6 + hnoise(k, 1, 5) * 8, 3 + hnoise(k, 1, 6) * 3), c.dark(0.2).alpha(0.18))
        }
    }

    static func buildingCanvas(_ d: BuildingDef) -> (w: CGFloat, h: CGFloat, anchorY: CGFloat) {
        let n = CGFloat(d.size)
        let extra = BuildingArt.headroom(d.kind)
        let h = 32 * n + extra
        return (64 * n, h, 16 * n / h)
    }

    // MARK: Buildings

    static func building(_ d: BuildingDef, team tc: RGB) -> CGImage {
        let c = buildingCanvas(d)
        let n = CGFloat(d.size)
        let img = Pen.image(c.w, c.h) { p in
            switch d.faction {
            case .humans: BuildingArt.human(p, d.kind, n, tc)
            case .machines: BuildingArt.machine(p, d.kind, n, tc)
            case .aliens: BuildingArt.alien(p, d.kind, n, tc)
            }
        }
        return Pen.lit(img, offset: 2.2)
    }

    static func resource(_ kind: ResourceKind, variant v: Int) -> CGImage {
        switch kind {
        case .iron:
            return Pen.image(64, 52) { p in
                let base = RGB(0.36, 0.38, 0.42)
                p.fill(p.ellipsePath(32, 14, 26, 10), RGB(0, 0, 0, 0.25))
                let rocks: [(CGFloat, CGFloat, CGFloat)] = v == 0 ? [(20, 18, 12), (40, 16, 14), (31, 28, 12)] : (v == 1 ? [(24, 16, 15), (42, 20, 11), (30, 30, 9)] : [(18, 20, 10), (34, 18, 15), (46, 24, 8)])
                for (x, y, r) in rocks {
                    p.shade(p.poly([(x - r, y - r * 0.4), (x - r * 0.6, y + r * 0.6), (x + r * 0.2, y + r * 0.9), (x + r, y + r * 0.2), (x + r * 0.7, y - r * 0.6)]), base)
                    p.line((x - r * 0.4, y + r * 0.1), (x + r * 0.5, y + r * 0.4), RGB(0.75, 0.82, 0.9), 2)
                    p.dot(x + r * 0.2, y - r * 0.1, 1.6, RGB(0.75, 0.42, 0.2))
                }
            }
        case .gold:
            return Pen.image(60, 60) { p in
                p.fill(p.ellipsePath(30, 12, 22, 9), RGB(0, 0, 0, 0.25))
                p.glow(30, 26, 26, RGB(1, 0.85, 0.3, 0.45))
                let shards: [(CGFloat, CGFloat, CGFloat)] = [(22, 12, 26), (32, 10, 36), (41, 13, 22), (28, 14, 18)]
                for (i, (x, y, h)) in shards.enumerated() where !(v == 1 && i == 3) {
                    p.shade(p.poly([(x - 5, y), (x - 3, y + h), (x, y + h + 5), (x + 3, y + h), (x + 5, y)]), RGB(1.0, 0.8, 0.22), outline: RGB(0.35, 0.22, 0.02, 0.9))
                    p.line((x - 1, y + 3), (x - 1, y + h), RGB(1, 1, 0.8, 0.8), 1.2)
                }
            }
        case .wood:
            return Pen.image(56, 84) { p in
                p.fill(p.ellipsePath(28, 10, 16, 7), RGB(0, 0, 0, 0.28))
                p.box(25, 6, 6, 18, RGB(0.42, 0.28, 0.16), r: 2)
                let leaf = [RGB(0.16, 0.42, 0.30), RGB(0.20, 0.48, 0.26), RGB(0.14, 0.38, 0.34)][v % 3]
                for (i, y) in [(0, 18), (1, 34), (2, 50)] as [(Int, CGFloat)] {
                    let w: CGFloat = 24 - CGFloat(i) * 6
                    p.shade(p.poly([(28 - w, y), (28, y + 26 - CGFloat(i) * 2), (28 + w, y), (28, y - 4)]), leaf.light(CGFloat(i) * 0.06), outline: RGB(0.04, 0.12, 0.08, 0.9))
                }
            }
        }
    }

    static func boulder(variant v: Int) -> CGImage {
        Pen.image(70, 70) { p in
            let c = [RGB(0.42, 0.40, 0.38), RGB(0.38, 0.36, 0.40), RGB(0.45, 0.42, 0.36)][v % 3]
            p.fill(p.ellipsePath(35, 16, 30, 12), RGB(0, 0, 0, 0.3))
            p.shade(p.poly([(6, 16), (12, 40), (26, 56), (42, 60), (58, 44), (64, 18), (36, 6)]), c)
            p.shade(p.poly([(36, 6), (64, 18), (58, 44), (42, 60), (40, 30)]), c.dark(0.22), outline: nil)
            p.line((18, 34), (30, 44), c.light(0.3), 2); p.line((44, 28), (52, 38), c.light(0.2), 1.5)
            if v == 1 { p.shade(p.poly([(46, 52), (52, 66), (60, 56)]), RGB(0.5, 0.75, 0.9)) }
        }
    }

    static func sitePlatform() -> CGImage {
        Pen.image(200, 100) { p in
            p.fill(p.ellipsePath(100, 50, 96, 48), RGB(0.2, 0.22, 0.25, 0.55))
            p.stroke(p.ellipsePath(100, 50, 94, 46), RGB(1, 1, 1, 0.7), 3)
            p.stroke(p.ellipsePath(100, 50, 60, 30), RGB(1, 1, 1, 0.35), 2)
            for a in 0..<8 { let t = CGFloat(a) / 8 * .pi * 2; p.line((100 + cos(t) * 64, 50 + sin(t) * 32), (100 + cos(t) * 90, 50 + sin(t) * 44), RGB(1, 1, 1, 0.5), 2) }
        }
    }

    static func siteBeacon() -> CGImage {
        Pen.image(48, 96) { p in
            p.fill(p.ellipsePath(24, 10, 18, 8), RGB(0, 0, 0, 0.3))
            p.shade(p.poly([(10, 10), (16, 50), (32, 50), (38, 10), (24, 4)]), RGB(0.55, 0.57, 0.6))
            p.shade(p.poly([(24, 4), (38, 10), (32, 50), (24, 48)]), RGB(0.38, 0.4, 0.44), outline: nil)
            p.glow(24, 70, 24, RGB(1, 1, 1, 0.7))
            p.shade(p.poly([(17, 64), (24, 88), (31, 64), (24, 52)]), RGB(0.95, 0.95, 1.0), outline: RGB(0.2, 0.2, 0.3, 0.8))
        }
    }

    // MARK: Terrain tiles (64x32 diamonds)

    static func tile(_ t: Terrain, variant v: Int, elevated: Bool) -> CGImage {
        Pen.image(64, 32, scale: 2) { p in
            let diamond = p.poly([(0, 16), (32, 32), (64, 16), (32, 0)])
            var base: RGB
            switch t {
            case .grass: base = RGB(0.30, 0.47, 0.26)
            case .dirt: base = RGB(0.50, 0.40, 0.28)
            case .moss: base = RGB(0.22, 0.40, 0.30)
            case .rock: base = RGB(0.33, 0.31, 0.30)
            case .water: base = RGB(0.12, 0.30, 0.45)
            }
            if elevated && t.groundPassable { base = base.light(0.08) }
            p.ctx.saveGState()
            p.ctx.addPath(diamond); p.ctx.clip()
            p.fill(diamond, base)
            // Speckle noise for texture; tiles tile seamlessly because noise is per-pixel random and soft.
            for k in 0..<160 {
                let x = hnoise(k, v, 1) * 64, y = hnoise(k, v, 2) * 32
                let n = hnoise(k, v, 3)
                let c = n > 0.5 ? base.light(0.12 * n) : base.dark(0.18 * (1 - n))
                p.dot(x, y, 0.6 + hnoise(k, v, 4) * 1.6, c.alpha(0.7))
            }
            if t == .grass || t == .moss {
                for k in 0..<10 {
                    let x = hnoise(k, v, 7) * 56 + 4, y = hnoise(k, v, 8) * 24 + 4
                    p.line((x, y), (x + 1.5, y + 4), base.light(0.25), 0.8); p.line((x + 2, y), (x + 1, y + 3.5), base.dark(0.2), 0.8)
                }
            }
            if t == .water {
                for k in 0..<5 {
                    let x = hnoise(k, v, 9) * 48 + 8, y = hnoise(k, v, 10) * 20 + 6
                    p.line((x - 5, y), (x + 5, y), RGB(0.5, 0.75, 0.9, 0.6), 1)
                }
            }
            p.ctx.restoreGState()
        }
    }

    // MARK: Effects (white, tinted at runtime)

    static func effect(_ name: String) -> CGImage {
        switch name {
        case "glow": return Pen.image(32, 32) { p in p.glow(16, 16, 16, RGB(1, 1, 1)) }
        case "ring": return Pen.image(64, 32) { p in p.stroke(p.ellipsePath(32, 16, 29, 13.5), RGB(1, 1, 1), 2.5) }
        case "shadow": return Pen.image(32, 16) { p in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 0, alpha: 0.45), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0.4, 1])!
            p.ctx.saveGState(); p.ctx.scaleBy(x: 1, y: 0.5)
            p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            p.ctx.restoreGState()
        }
        case "beam": return Pen.image(32, 8) { p in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.5, 1])!
            p.ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 8), options: [])
        }
        case "bolt": return Pen.image(10, 4) { p in p.fill(p.roundRectPath(0, 0.5, 10, 3, 1.5), RGB(1, 1, 1)) }
        case "orb": return Pen.image(10, 10) { p in p.glow(5, 5, 5, RGB(1, 1, 1)); p.dot(5, 5, 2.4, RGB(1, 1, 1)) }
        case "shell": return Pen.image(8, 8) { p in p.ellipse(4, 4, 3, 3, RGB(0.3, 0.3, 0.3)) }
        case "spark": return Pen.image(16, 16) { p in
            p.glow(8, 8, 8, RGB(1, 1, 1))
            p.line((8, 0), (8, 16), RGB(1, 1, 1, 0.8), 1.2); p.line((0, 8), (16, 8), RGB(1, 1, 1, 0.8), 1.2)
        }
        case "smoke": return Pen.image(32, 32) { p in
            for k in 0..<5 { p.fill(p.ellipsePath(10 + hnoise(k, 1, 1) * 12, 10 + hnoise(k, 1, 2) * 12, 7, 7), RGB(1, 1, 1, 0.35)) }
        }
        case "scorch": return Pen.image(48, 24) { p in
            for k in 0..<8 { p.fill(p.ellipsePath(14 + hnoise(k, 2, 1) * 20, 7 + hnoise(k, 2, 2) * 10, 8, 4), RGB(0, 0, 0, 0.18)) }
        }
        default: return Pen.image(4, 4) { p in p.fill(p.poly([(0, 0), (4, 0), (4, 4), (0, 4)]), RGB(1, 1, 1)) }
        }
    }
}
