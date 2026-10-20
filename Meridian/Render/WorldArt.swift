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

    static func prism(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat, _ z0: CGFloat, _ z1: CGFloat,
                      wall: RGB, roof: RGB, outline: Bool = true) {
        let o: RGB? = outline ? RGB(0.05, 0.05, 0.06, 0.85) : nil
        p.shade(p.poly([P(u0, v0, z0, n), P(u1, v0, z0, n), P(u1, v0, z1, n), P(u0, v0, z1, n)]), wall.light(0.08), outline: o, top: 0.1, bottom: 0.15)
        p.shade(p.poly([P(u1, v0, z0, n), P(u1, v1, z0, n), P(u1, v1, z1, n), P(u1, v0, z1, n)]), wall.dark(0.25), outline: o, top: 0.05, bottom: 0.2)
        p.shade(p.poly([P(u0, v0, z1, n), P(u1, v0, z1, n), P(u1, v1, z1, n), P(u0, v1, z1, n)]), roof, outline: o, top: 0.15, bottom: 0.1)
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

    static func pad(_ p: Pen, _ n: CGFloat, _ c: RGB) {
        p.shade(p.poly([P(0, 0, 0, n), P(n, 0, 0, n), P(n, n, 0, n), P(0, n, 0, n)]), c, outline: RGB(0, 0, 0, 0.35), top: 0.05, bottom: 0.1)
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

    static func humanBuilding(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let wall = RGB(0.64, 0.62, 0.56), roof = RGB(0.36, 0.38, 0.36), win = RGB(1, 0.82, 0.4)
        pad(p, n, RGB(0.42, 0.42, 0.40))
        let i: CGFloat = 0.12 * n
        switch k {
        case .hq:
            prism(p, n, i, i, n - i, n - i, 0, 30, wall: wall, roof: roof)
            prism(p, n, n * 0.3, n * 0.25, n * 0.7, n * 0.6, 30, 52, wall: wall.light(0.05), roof: roof.light(0.05))
            strip(p, n, i + 0.2, n - i - 0.2, i, 18, win, 3)
            strip(p, n, n * 0.32, n * 0.68, n * 0.25, 42, tc, 3)
            let (ax, ay) = P(n * 0.5, n * 0.45, 52, n)
            p.limb((ax, ay), (ax, ay + 26), RGB(0.3, 0.3, 0.3), 1.5); p.dot(ax, ay + 27, 2, RGB(1, 0.3, 0.3))
            let (dx, dy) = P(n * 0.75, n * 0.75, 30, n)
            p.ellipse(dx, dy + 8, 9, 4, RGB(0.8, 0.8, 0.78)); p.limb((dx, dy), (dx, dy + 6), RGB(0.3, 0.3, 0.3), 2)
        case .depot:
            prism(p, n, i, i, n * 0.6, n - i, 0, 18, wall: wall, roof: roof)
            p.ctx.saveGState()
            let (sx, sy) = P(n * 0.78, n * 0.55, 0, n)
            p.box(sx - 9, sy, 18, 30, RGB(0.7, 0.68, 0.62), r: 8); p.ellipse(sx, sy + 30, 9, 4, RGB(0.55, 0.55, 0.5))
            p.line((sx - 9, sy + 14), (sx + 9, sy + 14), tc, 2.5)
            p.ctx.restoreGState()
            for (u, v) in [(0.25, 0.2), (0.45, 0.2)] as [(CGFloat, CGFloat)] { prism(p, n, u * n, v * n - 0.15, u * n + 0.3, v * n + 0.15, 18, 26, wall: RGB(0.55, 0.42, 0.25), roof: RGB(0.62, 0.5, 0.3)) }
        case .infantry:
            prism(p, n, i, i, n - i, n * 0.62, 0, 22, wall: wall, roof: roof)
            prism(p, n, i, n * 0.62, n * 0.5, n - i, 0, 16, wall: wall.dark(0.05), roof: roof)
            strip(p, n, i + 0.2, n - i - 0.2, i, 13, win, 2.5)
            let (fx, fy) = P(n - i - 0.2, n * 0.62, 22, n)
            p.limb((fx, fy), (fx, fy + 28), RGB(0.3, 0.3, 0.3), 1.4); p.shape([(fx, fy + 28), (fx + 14, fy + 24), (fx, fy + 20)], tc)
        case .heavy:
            prism(p, n, i, i, n - i, n - i, 0, 26, wall: wall.dark(0.05), roof: roof)
            let a = P(n * 0.3, i, 2, n), b = P(n * 0.75, i, 2, n), c2 = P(n * 0.75, i, 20, n), d2 = P(n * 0.3, i, 20, n)
            p.shade(p.poly([a, b, c2, d2]), RGB(0.3, 0.3, 0.28)); for z in stride(from: 5 as CGFloat, to: 20, by: 4) { strip(p, n, n * 0.3, n * 0.75, i, z, RGB(0.42, 0.42, 0.4), 1) }
            strip(p, n, n * 0.3, n * 0.75, i, 23, tc, 3)
            let (cx, cy) = P(n * 0.8, n * 0.7, 26, n)
            p.limb((cx, cy), (cx, cy + 30), RGB(0.95, 0.75, 0.2), 2.5); p.limb((cx, cy + 30), (cx - 30, cy + 26), RGB(0.95, 0.75, 0.2), 2.5)
        case .air:
            pad(p, n, RGB(0.32, 0.33, 0.34))
            prism(p, n, n * 0.5, n * 0.1, n - i, n - i, 0, 24, wall: wall, roof: RGB(0.45, 0.5, 0.55))
            let (hx, hy) = P(n * 0.28, n * 0.4, 1, n)
            p.stroke(p.ellipsePath(hx, hy, 22, 11), RGB(1, 1, 1, 0.8), 2); p.line((hx - 7, hy), (hx + 7, hy), RGB(1, 1, 1, 0.8), 2)
            strip(p, n, n * 0.55, n - i, n * 0.1, 16, tc, 3)
            for u in stride(from: 0.2 as CGFloat, to: n * 0.45, by: 0.4) { let (x, y) = P(u, 0.12, 1, n); p.dot(x, y, 1.6, RGB(0.4, 1, 0.5)) }
        case .research:
            prism(p, n, i, i, n - i, n - i, 0, 14, wall: wall, roof: roof)
            dome(p, n, n * 0.5, n * 0.5, 14, n * 0.28, RGB(0.75, 0.82, 0.88), tall: 0.8)
            strip(p, n, i + 0.2, n - i - 0.2, i, 8, tc, 2.5)
            let (ax, ay) = P(n * 0.8, n * 0.8, 14, n)
            p.limb((ax, ay), (ax, ay + 24), RGB(0.3, 0.3, 0.3), 1.2); p.dot(ax, ay + 24, 1.8, RGB(0.3, 0.9, 1))
        case .tower:
            prism(p, n, 0.35, 0.35, n - 0.35, n - 0.35, 0, 54, wall: wall, roof: roof)
            prism(p, n, 0.2, 0.2, n - 0.2, n - 0.2, 54, 64, wall: RGB(0.45, 0.47, 0.45), roof: roof.light(0.1))
            strip(p, n, 0.4, n - 0.4, 0.35, 40, tc, 3)
            let (gx, gy) = P(n * 0.5, n * 0.5, 64, n)
            p.box(gx - 8, gy, 16, 9, RGB(0.3, 0.32, 0.3)); p.limb((gx + 4, gy + 5), (gx + 22, gy + 7), RGB(0.2, 0.2, 0.22), 2.5)
        case .forward:
            let (cx, cy) = P(n * 0.5, n * 0.5, 0, n)
            p.shape([(cx - 30, cy - 4), (cx, cy + 34), (cx + 30, cy - 4), (cx, cy - 16)], RGB(0.45, 0.5, 0.38))
            p.shape([(cx, cy + 34), (cx + 30, cy - 4), (cx, cy - 16)], RGB(0.36, 0.41, 0.3))
            p.line((cx - 20, cy + 6), (cx, cy + 26), tc, 3)
            for a in 0..<6 { let t = CGFloat(a) / 6 * .pi * 2; p.ellipse(cx + cos(t) * 30, cy + sin(t) * 13 - 4, 5, 3, RGB(0.6, 0.55, 0.4)) }
            p.limb((cx + 18, cy + 4), (cx + 18, cy + 46), RGB(0.3, 0.3, 0.3), 1.4); p.dot(cx + 18, cy + 46, 2, RGB(0.3, 1, 0.4))
        }
    }

    static func machineBuilding(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let wall = RGB(0.30, 0.32, 0.38), roof = RGB(0.20, 0.22, 0.27), glow = RGB(0.35, 0.95, 1.0)
        pad(p, n, RGB(0.22, 0.24, 0.28))
        let i: CGFloat = 0.1 * n
        func core(_ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ r: CGFloat) {
            let (x, y) = P(u, v, z, n); p.glow(x, y, r * 2.2, glow.alpha(0.7)); p.ellipse(x, y, r, r, glow.light(0.3)); p.dot(x - r * 0.3, y + r * 0.3, r * 0.3, RGB(1, 1, 1))
        }
        switch k {
        case .hq:
            prism(p, n, i, i, n - i, n - i, 0, 20, wall: wall, roof: roof)
            prism(p, n, n * 0.25, n * 0.25, n * 0.75, n * 0.75, 20, 44, wall: wall.light(0.08), roof: roof)
            prism(p, n, n * 0.38, n * 0.38, n * 0.62, n * 0.62, 44, 62, wall: wall.light(0.15), roof: roof)
            strip(p, n, i, n - i, i, 12, tc, 3); strip(p, n, n * 0.25, n * 0.75, n * 0.25, 34, glow, 2)
            core(n * 0.5, n * 0.5, 76, 7)
        case .depot:
            prism(p, n, i, i, n - i, n - i, 0, 18, wall: wall, roof: roof)
            for u in [0.35, 0.7] as [CGFloat] {
                let (x, y) = P(u * n, n * 0.6, 18, n)
                p.box(x - 4, y, 8, 22, RGB(0.25, 0.26, 0.3), r: 2); p.glow(x, y + 24, 8, RGB(1, 0.55, 0.15, 0.8))
            }
            strip(p, n, i, n - i, i, 9, RGB(1, 0.6, 0.2), 3); strip(p, n, i, n - i, i, 14, tc, 2)
        case .infantry:
            prism(p, n, i, i, n - i, n * 0.55, 0, 20, wall: wall, roof: roof)
            prism(p, n, i, n * 0.55, n - i, n - i, 0, 30, wall: wall.light(0.05), roof: roof)
            strip(p, n, i, n - i, i, 10, glow, 2.5); strip(p, n, i, n - i, n * 0.55, 24, tc, 3)
            let (ax, ay) = P(n * 0.5, n * 0.3, 20, n); p.limb((ax, ay), (ax + 14, ay + 18), RGB(0.6, 0.62, 0.68), 3); p.limb((ax + 14, ay + 18), (ax + 24, ay + 10), RGB(0.6, 0.62, 0.68), 2)
        case .heavy:
            prism(p, n, i, i, n - i, n - i, 0, 34, wall: wall.dark(0.05), roof: roof)
            strip(p, n, i, n - i, i, 26, tc, 4)
            let a = P(n * 0.3, i, 2, n), b = P(n * 0.75, i, 2, n), c2 = P(n * 0.75, i, 20, n), d2 = P(n * 0.3, i, 20, n)
            p.shade(p.poly([a, b, c2, d2]), RGB(0.12, 0.13, 0.16)); p.glow((a.0 + b.0) / 2, (a.1 + c2.1) / 2, 18, RGB(1, 0.5, 0.15, 0.6))
            core(n * 0.75, n * 0.75, 40, 5)
        case .air:
            prism(p, n, i, i, n - i, n - i, 0, 10, wall: wall, roof: roof)
            let (x, y) = P(n * 0.5, n * 0.5, 10, n)
            p.box(x - 6, y, 12, 50, wall.light(0.1), r: 3)
            for z in [20, 34, 48] as [CGFloat] { p.stroke(p.ellipsePath(x, y + z, 20 - z * 0.15, 6 - z * 0.04), glow.alpha(0.85), 2) }
            p.line((x - 5, y + 8), (x + 5, y + 8), tc, 3); core(n * 0.5, n * 0.5, 64, 4)
        case .research:
            prism(p, n, i, i, n - i, n - i, 0, 12, wall: wall, roof: roof)
            for (u, v) in [(0.3, 0.3), (0.3, 0.7), (0.7, 0.3), (0.7, 0.7)] as [(CGFloat, CGFloat)] {
                prism(p, n, u * n - 0.2, v * n - 0.2, u * n + 0.2, v * n + 0.2, 12, 38, wall: wall.light(0.1), roof: roof)
                let (x, y) = P(u * n, v * n, 40, n); p.glow(x, y, 7, glow.alpha(0.8))
            }
            strip(p, n, i, n - i, i, 7, tc, 3)
        case .tower:
            let (x, y) = P(n * 0.5, n * 0.5, 0, n)
            p.shape([(x - 22, y), (x - 10, y + 64), (x + 10, y + 64), (x + 22, y), (x, y - 11)], wall)
            p.shape([(x, y - 11), (x + 22, y), (x + 10, y + 64), (x, y + 60)], wall.dark(0.25))
            p.line((x - 15, y + 20), (x + 15, y + 20), tc, 3)
            p.glow(x, y + 74, 16, glow.alpha(0.8)); p.ellipse(x, y + 74, 8, 8, glow.light(0.3))
        case .forward:
            let (x, y) = P(n * 0.5, n * 0.5, 0, n)
            p.shape([(x - 18, y), (x - 4, y + 70), (x + 4, y + 70), (x + 18, y), (x, y - 9)], wall.light(0.05))
            p.stroke(p.ellipsePath(x, y + 78, 18, 6), glow, 2.5); p.glow(x, y + 78, 18, glow.alpha(0.5))
            p.line((x - 10, y + 16), (x + 10, y + 16), tc, 3)
        }
    }

    static func alienBuilding(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let chit = RGB(0.42, 0.26, 0.44), flesh = RGB(0.72, 0.42, 0.52), bio = RGB(0.55, 1.0, 0.35)
        // Organic creep base instead of a pad.
        let (cx, cy) = P(n * 0.5, n * 0.5, 0, n)
        p.fill(p.ellipsePath(cx, cy, 30 * n, 15 * n), RGB(0.30, 0.18, 0.32, 0.85))
        func pore(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { p.glow(x, y, r * 2.5, bio.alpha(0.7)); p.dot(x, y, r, bio.light(0.4)) }
        func spike(_ x: CGFloat, _ y: CGFloat, _ hgt: CGFloat, _ w: CGFloat) { p.shape([(x - w, y), (x + w * 0.2, y + hgt), (x + w, y)], RGB(0.88, 0.82, 0.68)) }
        switch k {
        case .hq:
            p.ellipse(cx, cy + 20, 26 * n * 0.8, 30, chit)
            p.ellipse(cx, cy + 36, 16 * n * 0.8, 26, flesh)
            p.fill(p.ellipsePath(cx, cy + 14, 20 * n * 0.6, 6), tc.alpha(0.85))
            pore(cx - 10, cy + 40, 4); pore(cx + 14, cy + 30, 3); pore(cx - 24, cy + 18, 3)
            spike(cx - 30, cy + 30, 34, 6); spike(cx + 26, cy + 34, 30, 6)
        case .depot:
            p.ellipse(cx, cy + 4, 24 * n * 0.8, 14, chit.dark(0.2))
            p.fill(p.ellipsePath(cx, cy + 6, 14 * n * 0.8, 7), RGB(0.3, 0.7, 0.25))
            for a in 0..<4 { let t = CGFloat(a) / 4 * .pi * 2; p.limb((cx + cos(t) * 20, cy + sin(t) * 9 + 4), (cx + cos(t) * 28, cy + sin(t) * 12 + 22), flesh, 4) }
            p.fill(p.ellipsePath(cx, cy - 4, 18, 3), tc.alpha(0.85))
        case .infantry:
            p.ellipse(cx, cy + 16, 30 * n * 0.7, 26, chit)
            for (dx, dy) in [(-18, 16), (6, 22), (22, 10)] as [(CGFloat, CGFloat)] { p.fill(p.ellipsePath(cx + dx, cy + dy, 6, 5), RGB(0.12, 0.05, 0.12)); pore(cx + dx, cy + dy, 1.6) }
            p.fill(p.ellipsePath(cx, cy + 2, 26, 4), tc.alpha(0.85))
        case .heavy:
            for (dx, dy, r) in [(-26, 10, 20), (14, 6, 24), (-4, 30, 22)] as [(CGFloat, CGFloat, CGFloat)] { p.ellipse(cx + dx, cy + dy, r, r * 0.9, flesh.dark(0.1)); pore(cx + dx + 4, cy + dy + 4, 3) }
            p.fill(p.ellipsePath(cx, cy - 6, 30, 5), tc.alpha(0.85))
        case .air:
            p.ellipse(cx, cy + 6, 22, 12, chit)
            for (dx, h) in [(-20, 52), (4, 64), (22, 44)] as [(CGFloat, CGFloat)] {
                p.limb((cx + dx, cy + 6), (cx + dx, cy + h), chit.light(0.1), 5)
                p.shape([(cx + dx - 14, cy + h - 4), (cx + dx, cy + h + 14), (cx + dx + 14, cy + h - 4), (cx + dx, cy + h - 8)], flesh)
                pore(cx + dx, cy + h + 1, 2.5)
            }
            p.fill(p.ellipsePath(cx, cy, 18, 4), tc.alpha(0.85))
        case .research:
            p.ellipse(cx, cy + 22, 34, 26, RGB(0.85, 0.6, 0.7))
            for i in 0..<5 { let x = cx - 24 + CGFloat(i) * 12; p.stroke(p.ellipsePath(x, cy + 24 + CGFloat(i % 2) * 6, 5, 12), RGB(0.6, 0.35, 0.45), 2) }
            pore(cx, cy + 40, 4); p.fill(p.ellipsePath(cx, cy + 2, 28, 4), tc.alpha(0.85))
        case .tower:
            p.ellipse(cx, cy + 6, 18, 9, chit)
            p.shape([(cx - 14, cy + 6), (cx - 2, cy + 86), (cx + 14, cy + 6)], RGB(0.5, 0.32, 0.5))
            p.shape([(cx + 2, cy + 6), (cx - 2, cy + 86), (cx + 14, cy + 6)], RGB(0.38, 0.22, 0.38))
            for (dx, dy) in [(-10, 30), (8, 46), (-6, 62), (10, 20)] as [(CGFloat, CGFloat)] { spike(cx + dx, cy + dy, 12, 3) }
            pore(cx - 1, cy + 74, 3); p.fill(p.ellipsePath(cx, cy + 2, 14, 3), tc.alpha(0.85))
        case .forward:
            for a in 0..<5 { let t = CGFloat(a) / 5 * .pi * 2; p.limb((cx, cy + 10), (cx + cos(t) * 32, cy + sin(t) * 14), chit.dark(0.1), 4) }
            p.ellipse(cx, cy + 24, 13, 18, flesh); pore(cx, cy + 30, 5)
            p.fill(p.ellipsePath(cx, cy + 6, 16, 3.5), tc.alpha(0.85))
        }
    }

    // MARK: Resources & doodads

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
