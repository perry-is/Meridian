import CoreGraphics
import Foundation
import MeridianCore

/// Faction architecture. Each building is drawn in an isometric canvas sized to its footprint
/// (64·n wide) with headroom for vertical elements. Coordinates use WorldArt.P(u, v, z, n).
enum BuildingArt {
    typealias P2 = (CGFloat, CGFloat)
    static func P(_ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ n: CGFloat) -> P2 { WorldArt.P(u, v, z, n) }

    static func headroom(_ k: BuildingKind) -> CGFloat {
        switch k {
        case .hq: return 150
        case .tower: return 140
        case .forward: return 120
        case .air, .research: return 112
        default: return 100
        }
    }

    /// Approximate height of the artwork above the footprint centre (for health bars and effects).
    static func visualHeight(_ d: BuildingDef) -> CGFloat {
        if let m = BuildingModels.meta(d.id) { return m.height }
        let table: [Faction: [BuildingKind: CGFloat]] = [
            .humans: [.hq: 120, .depot: 52, .infantry: 64, .heavy: 72, .air: 64, .research: 62, .tower: 100, .forward: 80],
            .machines: [.hq: 140, .depot: 50, .infantry: 44, .heavy: 72, .air: 96, .research: 72, .tower: 112, .forward: 112],
            .aliens: [.hq: 104, .depot: 42, .infantry: 52, .heavy: 62, .air: 92, .research: 58, .tower: 108, .forward: 90],
        ]
        return table[d.faction]?[d.kind] ?? 60
    }

    /// Light points (offset from footprint centre) that pulse at runtime: beacons, cores, glowing pores.
    static func lights(_ d: BuildingDef) -> [CGPoint] {
        if let m = BuildingModels.meta(d.id) { return m.lights.map { CGPoint(x: $0[0], y: $0[1]) } }
        switch (d.faction, d.kind) {
        case (.humans, .hq): return [CGPoint(x: -6, y: 120)]
        case (.humans, .tower): return [CGPoint(x: -14, y: 84)]
        case (.humans, .forward): return [CGPoint(x: 22, y: 80), CGPoint(x: -26, y: 36)]
        case (.humans, .air): return [CGPoint(x: -38, y: 51)]
        case (.machines, .hq): return [CGPoint(x: 0, y: 130)]
        case (.machines, .air): return [CGPoint(x: 0, y: 90)]
        case (.machines, .tower): return [CGPoint(x: 0, y: 100)]
        case (.machines, .forward): return [CGPoint(x: 0, y: 104)]
        case (.machines, .heavy): return [CGPoint(x: -10, y: 12)]
        case (.aliens, .hq): return [CGPoint(x: 6, y: 52)]
        case (.aliens, .tower): return [CGPoint(x: -2, y: 90)]
        case (.aliens, .forward): return [CGPoint(x: 2, y: 68)]
        case (.aliens, .research): return [CGPoint(x: 4, y: 42)]
        default: return []
        }
    }

    // MARK: Shared primitives

    static let outline = RGB(0.05, 0.04, 0.07, 0.9)

    static func box(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat, _ z0: CGFloat, _ z1: CGFloat, _ wall: RGB, _ roof: RGB) {
        WorldArt.prism(p, n, u0, v0, u1, v1, z0, z1, wall: wall, roof: roof)
    }

    /// Windows along the front-left face (v = v0) between u0..u1 at height z.
    static func windowsL(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ u1: CGFloat, _ v: CGFloat, _ z: CGFloat, _ count: Int, _ c: RGB, h: CGFloat = 5) {
        for i in 0..<count {
            let u = u0 + (u1 - u0) * (CGFloat(i) + 0.5) / CGFloat(count)
            let a = P(u - 0.07, v, z, n), b = P(u + 0.07, v, z, n), cc = P(u + 0.07, v, z + h, n), d = P(u - 0.07, v, z + h, n)
            p.fill(p.poly([a, b, cc, d]), c)
            p.glow((a.0 + cc.0) / 2, (a.1 + cc.1) / 2, 6, c.alpha(0.35))
        }
    }

    /// Windows along the front-right face (u = u) between v0..v1.
    static func windowsR(_ p: Pen, _ n: CGFloat, _ v0: CGFloat, _ v1: CGFloat, _ u: CGFloat, _ z: CGFloat, _ count: Int, _ c: RGB, h: CGFloat = 5) {
        for i in 0..<count {
            let v = v0 + (v1 - v0) * (CGFloat(i) + 0.5) / CGFloat(count)
            let a = P(u, v - 0.07, z, n), b = P(u, v + 0.07, z, n), cc = P(u, v + 0.07, z + h, n), d = P(u, v - 0.07, z + h, n)
            p.fill(p.poly([a, b, cc, d]), c.dark(0.25))
        }
    }

    static func cylinder(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ h: CGFloat, _ c: RGB, cap: RGB? = nil) {
        p.shade(p.roundRectPath(x - r, y, r * 2, h, 0.1), c, outline: outline, top: 0.05, bottom: 0.2)
        p.shade(p.ellipsePath(x, y, r, r * 0.5), c.dark(0.1), outline: nil)
        p.ctx.saveGState(); p.ctx.addRect(CGRect(x: x, y: y - r, width: r + 1, height: h + r)); p.ctx.clip()
        p.fill(p.roundRectPath(x, y, r, h, 0.1), RGB(0.05, 0.03, 0.15, 0.25)); p.ctx.restoreGState()
        p.shade(p.ellipsePath(x, y + h, r, r * 0.5), cap ?? c.light(0.15), outline: outline)
    }

    static func hazard(_ p: Pen, _ a: P2, _ b: P2, _ width: CGFloat) {
        p.line(a, b, RGB(0.95, 0.75, 0.15), width)
        let steps = 6
        for i in 0..<steps where i % 2 == 0 {
            let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
            p.line((a.0 + (b.0 - a.0) * t0, a.1 + (b.1 - a.1) * t0), (a.0 + (b.0 - a.0) * t1, a.1 + (b.1 - a.1) * t1), RGB(0.1, 0.1, 0.1), width)
        }
    }

    static func antenna(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ h: CGFloat, light: RGB = RGB(1, 0.3, 0.25)) {
        p.limb((x, y), (x, y + h), RGB(0.25, 0.25, 0.27), 1.4)
        p.line((x - 4, y + h * 0.6), (x + 4, y + h * 0.6), RGB(0.3, 0.3, 0.32), 1)
        p.glow(x, y + h, 6, light.alpha(0.8)); p.dot(x, y + h, 1.8, light.light(0.3))
    }

    static func dish(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        p.limb((x, y), (x + 2, y + r * 0.9), RGB(0.3, 0.3, 0.32), 2)
        p.shade(p.ellipsePath(x + 3, y + r * 1.15, r, r * 0.55), RGB(0.86, 0.87, 0.85), outline: outline)
        p.fill(p.ellipsePath(x + 4, y + r * 1.2, r * 0.6, r * 0.3), RGB(0.62, 0.64, 0.66))
        p.dot(x + 4, y + r * 1.25, 1.6, RGB(0.3, 0.3, 0.32))
    }

    static func crate(_ p: Pen, _ n: CGFloat, _ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ s: CGFloat, _ c: RGB) {
        box(p, n, u, v, u + s, v + s, z, z + s * 26, c, c.light(0.15))
    }

    // MARK: Concord (humans)

    static func human(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let concrete = RGB(0.66, 0.62, 0.54), armor = RGB(0.50, 0.52, 0.46), roof = RGB(0.34, 0.36, 0.35), win = RGB(1.0, 0.80, 0.42)
        WorldArt.pad(p, n, RGB(0.40, 0.39, 0.36))
        // Perimeter curb.
        for (a, b) in [(P(0.1, 0.1, 1, n), P(n - 0.1, 0.1, 1, n)), (P(n - 0.1, 0.1, 1, n), P(n - 0.1, n - 0.1, 1, n))] { p.line(a, b, RGB(0.55, 0.53, 0.48), 2) }
        switch k {
        case .hq:
            box(p, n, 0.35, 0.35, n - 0.35, n - 0.35, 0, 26, armor, roof)
            windowsL(p, n, 0.6, n - 0.6, 0.35, 12, 6, win)
            windowsR(p, n, 0.6, n - 0.6, n - 0.35, 12, 6, win)
            box(p, n, 1.0, 0.9, n - 1.2, n - 1.0, 26, 54, concrete, roof.light(0.05))
            windowsL(p, n, 1.2, n - 1.4, 0.9, 38, 4, win)
            box(p, n, 1.5, 1.4, n - 1.9, n - 1.8, 54, 78, concrete.light(0.05), roof)
            hazard(p, P(0.4, 0.35, 3, n), P(n - 0.4, 0.35, 3, n), 3)
            p.line(P(1.0, 0.9, 48, n), P(n - 1.2, 0.9, 48, n), tc, 4)
            let top = P(n * 0.5, n * 0.5, 78, n)
            antenna(p, top.0 - 6, top.1, 42)
            p.dot(top.0 + 12, top.1 - 4, 3, RGB(0.3, 0.3, 0.32))   // radar mount (the dish turns at runtime)
            // Helipad on the low deck.
            let hp = P(n - 0.9, n - 0.9, 26, n)
            p.stroke(p.ellipsePath(hp.0, hp.1, 13, 6.5), RGB(1, 1, 1, 0.8), 1.5); p.line((hp.0 - 4, hp.1), (hp.0 + 4, hp.1), RGB(1, 1, 1, 0.8), 1.5)
        case .depot:
            box(p, n, 0.15, 0.2, n * 0.62, n - 0.15, 0, 22, concrete, roof)
            let d0 = P(0.3, 0.2, 2, n), d1 = P(n * 0.55, 0.2, 2, n)
            p.shade(p.poly([d0, d1, (d1.0, d1.1 + 14), (d0.0, d0.1 + 14)]), RGB(0.32, 0.32, 0.3))
            hazard(p, (d0.0, d0.1 + 15), (d1.0, d1.1 + 15), 2.5)
            let s = P(n * 0.82, n * 0.6, 0, n)
            cylinder(p, s.0, s.1, 11, 40, RGB(0.74, 0.72, 0.66))
            p.line((s.0 - 11, s.1 + 26), (s.0 + 11, s.1 + 26), tc, 3)
            crate(p, n, n * 0.68, 0.15, 0, 0.32, RGB(0.55, 0.42, 0.24))
            crate(p, n, n * 0.68, 0.15, 8.3, 0.32, RGB(0.36, 0.48, 0.30))
        case .infantry:
            // Barrel-vault barracks.
            box(p, n, 0.3, 0.3, n - 0.3, n * 0.62, 0, 20, armor, roof)
            let a = P(0.3, 0.3, 20, n), b = P(n - 0.3, 0.3, 20, n), c = P(n - 0.3, n * 0.62, 20, n), d = P(0.3, n * 0.62, 20, n)
            let arch = CGMutablePath(); arch.move(to: CGPoint(x: a.0, y: a.1)); arch.addLine(to: CGPoint(x: b.0, y: b.1))
            arch.addQuadCurve(to: CGPoint(x: c.0, y: c.1), control: CGPoint(x: (b.0 + c.0) / 2, y: (b.1 + c.1) / 2 + 22))
            arch.addLine(to: CGPoint(x: d.0, y: d.1))
            arch.addQuadCurve(to: CGPoint(x: a.0, y: a.1), control: CGPoint(x: (a.0 + d.0) / 2, y: (a.1 + d.1) / 2 + 22)); arch.closeSubpath()
            p.shade(arch, roof.light(0.12), outline: outline)
            for i in 1..<5 { let u = 0.3 + (n - 0.6) * CGFloat(i) / 5; p.line(P(u, 0.3, 20, n), P(u, n * 0.62, 20, n), roof.dark(0.2), 1) }
            windowsL(p, n, 0.5, n - 0.5, 0.3, 8, 5, win)
            box(p, n, 0.3, n * 0.66, n * 0.5, n - 0.3, 0, 14, concrete, roof)
            let f = P(n - 0.5, n - 0.5, 0, n)
            p.limb((f.0, f.1), (f.0, f.1 + 62), RGB(0.3, 0.3, 0.3), 1.6)   // flag flies at runtime
        case .heavy:
            box(p, n, 0.2, 0.25, n - 0.2, n - 0.2, 0, 34, armor.dark(0.05), roof)
            for (u0, u1) in [(0.4, n * 0.45), (n * 0.55, n - 0.4)] {
                let a = P(u0, 0.25, 1, n), b = P(u1, 0.25, 1, n)
                p.shade(p.poly([a, b, (b.0, b.1 + 22), (a.0, a.1 + 22)]), RGB(0.26, 0.27, 0.26))
                for z in stride(from: 4 as CGFloat, to: 22, by: 4) { p.line((a.0, a.1 + z), (b.0, b.1 + z), RGB(0.38, 0.38, 0.36), 1) }
                hazard(p, (a.0, a.1 + 24), (b.0, b.1 + 24), 3)
            }
            p.line(P(0.2, 0.25, 30, n), P(n - 0.2, 0.25, 30, n), tc, 3)
            // Gantry crane.
            let c0 = P(n - 0.6, n - 0.6, 34, n)
            p.limb((c0.0, c0.1), (c0.0, c0.1 + 36), RGB(0.95, 0.72, 0.15), 3)
            p.limb((c0.0, c0.1 + 36), (c0.0 - 48, c0.1 + 30), RGB(0.95, 0.72, 0.15), 3)
            cylinder(p, P(0.6, n - 0.5, 34, n).0, P(0.6, n - 0.5, 34, n).1, 6, 18, RGB(0.6, 0.35, 0.2))
        case .air:
            WorldArt.pad(p, n, RGB(0.30, 0.31, 0.32))
            let pad = P(n * 0.3, n * 0.36, 1, n)
            p.stroke(p.ellipsePath(pad.0, pad.1, 26, 13), RGB(1, 1, 1, 0.85), 2); p.line((pad.0 - 8, pad.1), (pad.0 + 8, pad.1), RGB(1, 1, 1, 0.85), 2)
            for k in 0..<8 { let a = CGFloat(k) / 8 * .pi * 2; p.dot(pad.0 + cos(a) * 30, pad.1 + sin(a) * 15, 1.6, RGB(0.4, 1, 0.5)) }
            // Curved hangar.
            box(p, n, n * 0.5, 0.25, n - 0.2, n - 0.2, 0, 16, armor, roof)
            let a = P(n * 0.5, 0.25, 16, n), b = P(n - 0.2, 0.25, 16, n), c = P(n - 0.2, n - 0.2, 16, n), d = P(n * 0.5, n - 0.2, 16, n)
            let arch = CGMutablePath(); arch.move(to: CGPoint(x: a.0, y: a.1)); arch.addLine(to: CGPoint(x: b.0, y: b.1))
            arch.addQuadCurve(to: CGPoint(x: c.0, y: c.1), control: CGPoint(x: (b.0 + c.0) / 2 + 4, y: (b.1 + c.1) / 2 + 34))
            arch.addLine(to: CGPoint(x: d.0, y: d.1))
            arch.addQuadCurve(to: CGPoint(x: a.0, y: a.1), control: CGPoint(x: (a.0 + d.0) / 2 + 4, y: (a.1 + d.1) / 2 + 34)); arch.closeSubpath()
            p.shade(arch, RGB(0.55, 0.60, 0.64), outline: outline)
            p.line(P(n * 0.55, 0.25, 10, n), P(n - 0.3, 0.25, 10, n), tc, 3)
            // Control tower.
            let t = P(0.45, n - 0.5, 0, n)
            cylinder(p, t.0, t.1, 6, 46, concrete)
            p.shade(p.poly([(t.0 - 11, t.1 + 46), (t.0 + 11, t.1 + 46), (t.0 + 8, t.1 + 56), (t.0 - 8, t.1 + 56)]), RGB(0.35, 0.6, 0.75), outline: outline)
            p.glow(t.0, t.1 + 51, 9, RGB(0.6, 0.9, 1, 0.5))
        case .research:
            box(p, n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 18, concrete, roof)
            windowsL(p, n, 0.4, n - 0.4, 0.25, 7, 6, RGB(0.55, 0.9, 1.0))
            WorldArt.dome(p, n, n * 0.48, n * 0.5, 18, n * 0.3, RGB(0.80, 0.86, 0.92), tall: 0.95)
            let s = P(n * 0.48, n * 0.5, 18, n)
            p.fill(p.roundRectPath(s.0 - 3, s.1 + 10, 6, 28, 2), RGB(0.15, 0.2, 0.3, 0.7))       // telescope slot
            p.limb((s.0, s.1 + 26), (s.0 + 14, s.1 + 44), RGB(0.3, 0.32, 0.36), 4)
            p.dot(P(n - 0.5, n - 0.5, 18, n).0, P(n - 0.5, n - 0.5, 18, n).1, 2.5, RGB(0.3, 0.3, 0.32))
            p.line(P(0.25, 0.25, 14, n), P(n - 0.25, 0.25, 14, n), tc, 3)
        case .tower:
            let b = P(n * 0.5, n * 0.5, 0, n)
            box(p, n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 14, armor, roof)
            p.shade(p.poly([(b.0 - 20, b.1 + 6), (b.0 - 13, b.1 + 82), (b.0, b.1 + 76), (b.0, b.1 - 4)]), concrete, outline: outline)
            p.shade(p.poly([(b.0, b.1 - 4), (b.0, b.1 + 76), (b.0 + 13, b.1 + 82), (b.0 + 20, b.1 + 6)]), concrete.dark(0.3), outline: outline)
            p.line((b.0 - 17, b.1 + 46), (b.0 + 17, b.1 + 46), tc, 4)
            windowsL(p, n, 0.6, n - 0.6, 0.6, 60, 2, win, h: 4)
            p.shade(p.poly([(b.0 - 22, b.1 + 82), (b.0, b.1 + 92), (b.0 + 22, b.1 + 82), (b.0, b.1 + 72)]), roof.light(0.1), outline: outline)
            p.box(b.0 - 9, b.1 + 86, 18, 11, RGB(0.32, 0.34, 0.33))
            p.limb((b.0 + 4, b.1 + 92), (b.0 + 26, b.1 + 95), RGB(0.18, 0.18, 0.2), 3)
            p.limb((b.0 + 4, b.1 + 89), (b.0 + 26, b.1 + 91), RGB(0.18, 0.18, 0.2), 3)
            p.glow(b.0 - 14, b.1 + 84, 10, RGB(1, 0.95, 0.75, 0.6))
        case .forward:
            let c = P(n * 0.5, n * 0.5, 0, n)
            for a in 0..<10 { let t = CGFloat(a) / 10 * .pi * 2; p.ellipse(c.0 + cos(t) * 34, c.1 + sin(t) * 15 - 2, 6, 3.4, RGB(0.62, 0.56, 0.40)) }
            p.shape([(c.0 - 28, c.1 - 2), (c.0 - 2, c.1 + 30), (c.0 + 24, c.1 - 2), (c.0 - 2, c.1 - 14)], RGB(0.45, 0.50, 0.36))
            p.shape([(c.0 - 2, c.1 + 30), (c.0 + 24, c.1 - 2), (c.0 - 2, c.1 - 14)], RGB(0.35, 0.40, 0.28))
            p.line((c.0 - 18, c.1 + 6), (c.0 - 2, c.1 + 24), tc, 3)
            p.box(c.0 + 12, c.1 + 2, 16, 10, RGB(0.34, 0.40, 0.30))
            antenna(p, c.0 + 22, c.1 + 10, 70, light: RGB(0.3, 1, 0.45))
            p.limb((c.0 - 26, c.1 + 2), (c.0 - 26, c.1 + 34), RGB(0.3, 0.3, 0.3), 1.5)
            p.glow(c.0 - 26, c.1 + 36, 12, RGB(1, 0.95, 0.7, 0.7))
        }
    }

    // MARK: Lattice (machines)

    static func machine(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let obs = RGB(0.20, 0.22, 0.28), obs2 = RGB(0.30, 0.33, 0.40), roof = RGB(0.14, 0.15, 0.20), cyan = RGB(0.35, 0.95, 1.0)
        // Hex plinth.
        let c = P(n * 0.5, n * 0.5, 0, n)
        let hex = (0..<6).map { (c.0 + cos(CGFloat($0) * .pi / 3) * 30 * n, c.1 + sin(CGFloat($0) * .pi / 3) * 15 * n) }
        p.shade(p.poly(hex), RGB(0.17, 0.18, 0.23), outline: RGB(0, 0, 0, 0.5))
        p.stroke(p.poly(hex.map { (c.0 + ($0.0 - c.0) * 0.86, c.1 + ($0.1 - c.1) * 0.86) }), cyan.alpha(0.5), 1.4)
        func core(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            p.glow(x, y, r * 2.6, cyan.alpha(0.75)); p.ellipse(x, y, r, r, cyan.light(0.35)); p.dot(x - r * 0.3, y + r * 0.3, r * 0.35, RGB(1, 1, 1))
        }
        func circuit(_ a: P2, _ b: P2) { p.line(a, b, cyan.alpha(0.9), 1.6); p.line(a, b, cyan.alpha(0.25), 4) }
        func obelisk(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.shade(p.poly([(x - w, y), (x - w * 0.55, y + h), (x, y + h + w * 0.5), (x, y - w * 0.5)]), obs2, outline: outline)
            p.shade(p.poly([(x, y - w * 0.5), (x, y + h + w * 0.5), (x + w * 0.55, y + h), (x + w, y)]), obs, outline: outline)
            p.line((x, y + 4), (x, y + h - 4), cyan.alpha(0.8), 1.2)
        }
        switch k {
        case .hq:
            box(p, n, 0.4, 0.4, n - 0.4, n - 0.4, 0, 20, obs2, roof)
            box(p, n, 0.9, 0.9, n - 0.9, n - 0.9, 20, 44, obs2.light(0.05), roof)
            obelisk(c.0, c.1 + 44, 18, 62)
            circuit(P(0.4, 0.4, 10, n), P(n - 0.4, 0.4, 10, n)); circuit(P(n - 0.4, 0.4, 10, n), P(n - 0.4, n - 0.4, 10, n))
            p.line(P(0.9, 0.9, 32, n), P(n - 0.9, 0.9, 32, n), tc, 4)
            core(c.0, c.1 + 130, 9)
            p.stroke(p.ellipsePath(c.0, c.1 + 128, 26, 8), cyan.alpha(0.8), 2)
        case .depot:
            box(p, n, 0.2, 0.2, n - 0.2, n - 0.2, 0, 16, obs2, roof)
            for u in [0.35, 0.7] as [CGFloat] {
                let s = P(u * n, n * 0.62, 16, n)
                cylinder(p, s.0, s.1, 5, 26, obs)
                p.glow(s.0, s.1 + 30, 10, RGB(1, 0.55, 0.15, 0.85)); p.dot(s.0, s.1 + 27, 3, RGB(1, 0.8, 0.4))
            }
            circuit(P(0.2, 0.2, 8, n), P(n - 0.2, 0.2, 8, n))
            p.line(P(0.2, 0.2, 13, n), P(n - 0.2, 0.2, 13, n), tc, 2.5)
        case .infantry:
            box(p, n, 0.3, 0.3, n - 0.3, n * 0.55, 0, 22, obs2, roof)
            box(p, n, 0.3, n * 0.55, n - 0.3, n - 0.3, 0, 36, obs2.light(0.04), roof)
            let g0 = P(n * 0.25, 0.3, 2, n), g1 = P(n * 0.7, 0.3, 2, n)
            p.shade(p.poly([g0, g1, (g1.0, g1.1 + 16), (g0.0, g0.1 + 16)]), RGB(0.06, 0.08, 0.12))
            p.glow((g0.0 + g1.0) / 2, g0.1 + 10, 16, cyan.alpha(0.5))
            circuit(P(0.3, n * 0.55, 28, n), P(n - 0.3, n * 0.55, 28, n))
            p.line(P(0.3, 0.3, 18, n), P(n - 0.3, 0.3, 18, n), tc, 3)
            // Assembly arm.
            let a = P(n * 0.6, n * 0.45, 36, n)
            p.limb((a.0, a.1), (a.0 + 14, a.1 + 22), RGB(0.65, 0.68, 0.74), 3); p.limb((a.0 + 14, a.1 + 22), (a.0 + 30, a.1 + 14), RGB(0.65, 0.68, 0.74), 2.5)
            core(a.0 + 30, a.1 + 13, 2.5)
        case .heavy:
            box(p, n, 0.2, 0.2, n - 0.2, n - 0.2, 0, 40, obs, roof)
            let g0 = P(n * 0.25, 0.2, 2, n), g1 = P(n * 0.75, 0.2, 2, n)
            p.shade(p.poly([g0, g1, (g1.0, g1.1 + 26), (g0.0, g0.1 + 26)]), RGB(0.05, 0.05, 0.08))
            p.glow((g0.0 + g1.0) / 2, g0.1 + 12, 26, RGB(1, 0.5, 0.15, 0.55))
            p.line(P(0.2, 0.2, 32, n), P(n - 0.2, 0.2, 32, n), tc, 4)
            circuit(P(n - 0.2, 0.3, 20, n), P(n - 0.2, n - 0.3, 20, n))
            obelisk(P(n * 0.7, n * 0.7, 40, n).0, P(n * 0.7, n * 0.7, 40, n).1, 8, 30)
        case .air:
            box(p, n, 0.3, 0.3, n - 0.3, n - 0.3, 0, 10, obs2, roof)
            obelisk(c.0, c.1 + 10, 9, 72)
            for (z, r) in [(30, 24), (50, 19), (70, 14)] as [(CGFloat, CGFloat)] { p.stroke(p.ellipsePath(c.0, c.1 + z, r, r * 0.33), cyan.alpha(0.85), 2) }
            p.line((c.0 - 6, c.1 + 20), (c.0 + 6, c.1 + 20), tc, 3)
            core(c.0, c.1 + 90, 5)
        case .research:
            box(p, n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 12, obs2, roof)
            for (u, v, h) in [(0.3, 0.3, 40), (0.3, 0.7, 30), (0.7, 0.3, 34), (0.7, 0.7, 52)] as [(CGFloat, CGFloat, CGFloat)] {
                let s = P(u * n, v * n, 12, n); obelisk(s.0, s.1, 6, h); core(s.0, s.1 + h + 10, 3)
            }
            circuit(P(0.3 * n, 0.3 * n, 12, n), P(0.7 * n, 0.7 * n, 12, n)); circuit(P(0.3 * n, 0.7 * n, 12, n), P(0.7 * n, 0.3 * n, 12, n))
            p.line(P(0.25, 0.25, 8, n), P(n - 0.25, 0.25, 8, n), tc, 3)
        case .tower:
            obelisk(c.0, c.1, 22, 78)
            p.line((c.0 - 15, c.1 + 26), (c.0 + 15, c.1 + 26), tc, 3.5)
            core(c.0, c.1 + 100, 8)
            p.stroke(p.ellipsePath(c.0, c.1 + 100, 18, 6), cyan.alpha(0.7), 1.6)
        case .forward:
            obelisk(c.0, c.1, 13, 86)
            p.line((c.0 - 9, c.1 + 20), (c.0 + 9, c.1 + 20), tc, 3)
            for r in [20, 30] as [CGFloat] { p.stroke(p.ellipsePath(c.0, c.1 + 104, r, r * 0.3), cyan.alpha(0.75), 2) }
            core(c.0, c.1 + 104, 5)
        }
    }

    // MARK: Brood (aliens)

    static func alien(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let chit = RGB(0.44, 0.26, 0.46), flesh = RGB(0.74, 0.42, 0.52), bio = RGB(0.55, 1.0, 0.38), bone = RGB(0.88, 0.82, 0.68)
        let c = P(n * 0.5, n * 0.5, 0, n)
        // Creep mat with veins.
        p.fill(p.ellipsePath(c.0, c.1, 31 * n, 15.5 * n), RGB(0.28, 0.16, 0.30, 0.9))
        for a in 0..<7 {
            let t = CGFloat(a) / 7 * .pi * 2
            p.line((c.0 + cos(t) * 8 * n, c.1 + sin(t) * 4 * n), (c.0 + cos(t + 0.3) * 28 * n, c.1 + sin(t + 0.3) * 13 * n), RGB(0.55, 0.25, 0.5, 0.7), 1.6)
        }
        func pore(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { p.glow(x, y, r * 2.8, bio.alpha(0.75)); p.dot(x, y, r, bio.light(0.45)) }
        func spike(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ w: CGFloat, _ lean: CGFloat = 0.2) {
            p.shape([(x - w, y), (x + w * lean, y + h), (x + w, y)], bone)
            p.line((x - w * 0.3, y + 2), (x + w * lean * 0.8, y + h - 3), RGB(1, 1, 0.95, 0.5), 0.9)
        }
        func ribbed(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ col: RGB) {
            p.ellipse(x, y, rx, ry, col)
            for i in 1..<5 {
                let t = CGFloat(i) / 5
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: x - rx + 2 * rx * t, y: y), radius: ry * 0.95, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                p.stroke(path, col.dark(0.35), 1.4)
            }
            p.highlight(x - rx * 0.35, y + ry * 0.45, rx * 0.25, ry * 0.15)
        }
        switch k {
        case .hq:
            ribbed(c.0, c.1 + 26, 28 * n * 0.62, 32, chit)
            p.ellipse(c.0 + 6, c.1 + 50, 20, 22, flesh)
            p.glow(c.0 + 6, c.1 + 52, 28, RGB(1, 0.4, 0.6, 0.45))      // heart glow
            pore(c.0 + 6, c.1 + 52, 5)
            p.fill(p.ellipsePath(c.0, c.1 + 6, 30, 6), tc.alpha(0.85))
            spike(c.0 - 40, c.1 + 30, 46, 7); spike(c.0 + 38, c.1 + 34, 40, 7, 0.4); spike(c.0 - 14, c.1 + 66, 38, 5)
            for (dx, dy) in [(-28, 18), (26, 16), (-10, 30)] as [(CGFloat, CGFloat)] { pore(c.0 + dx, c.1 + dy, 2.5) }
        case .depot:
            p.ellipse(c.0, c.1 + 2, 26 * n * 0.75, 13, chit.dark(0.25))
            p.fill(p.ellipsePath(c.0, c.1 + 4, 17 * n * 0.75, 7), RGB(0.40, 0.82, 0.28)); p.glow(c.0, c.1 + 6, 18, bio.alpha(0.55))
            for a in 0..<5 {
                let t = CGFloat(a) / 5 * .pi * 2 + 0.3
                p.limb((c.0 + cos(t) * 22, c.1 + sin(t) * 10 + 4), (c.0 + cos(t) * 30, c.1 + sin(t) * 13 + 30), flesh, 5)
                pore(c.0 + cos(t) * 30, c.1 + sin(t) * 13 + 31, 2)
            }
            p.fill(p.ellipsePath(c.0, c.1 - 6, 20, 3.5), tc.alpha(0.85))
        case .infantry:
            ribbed(c.0, c.1 + 18, 32 * n * 0.62, 28, chit)
            for (dx, dy) in [(-20, 18), (6, 26), (24, 12)] as [(CGFloat, CGFloat)] {
                p.fill(p.ellipsePath(c.0 + dx, c.1 + dy, 7, 5.5), RGB(0.10, 0.03, 0.10)); pore(c.0 + dx, c.1 + dy - 1, 1.8)
            }
            p.fill(p.ellipsePath(c.0, c.1 + 1, 28, 4.5), tc.alpha(0.85))
            spike(c.0 - 4, c.1 + 42, 22, 4)
        case .heavy:
            for (dx, dy, r) in [(-26, 12, 22), (16, 8, 26), (-4, 34, 24)] as [(CGFloat, CGFloat, CGFloat)] {
                p.ellipse(c.0 + dx, c.1 + dy, r, r * 0.92, flesh.dark(0.12))
                p.ellipse(c.0 + dx + 4, c.1 + dy + 2, r * 0.45, r * 0.4, RGB(0.85, 0.75, 0.45, 0.6))   // embryo shadow
                pore(c.0 + dx + 6, c.1 + dy + 6, 3)
            }
            p.fill(p.ellipsePath(c.0, c.1 - 8, 32, 5), tc.alpha(0.85))
        case .air:
            p.ellipse(c.0, c.1 + 6, 24, 12, chit)
            for (dx, h) in [(-22, 60), (4, 76), (24, 52)] as [(CGFloat, CGFloat)] {
                p.limb((c.0 + dx, c.1 + 6), (c.0 + dx + 2, c.1 + h), chit.light(0.08), 5)
                for k in 0..<5 {
                    let a = CGFloat(k) / 5 * .pi * 2
                    p.shape([(c.0 + dx + 2, c.1 + h), (c.0 + dx + 2 + cos(a) * 16, c.1 + h + sin(a) * 9 + 4), (c.0 + dx + 2 + cos(a + 0.5) * 8, c.1 + h + sin(a + 0.5) * 4)], flesh.light(0.08))
                }
                pore(c.0 + dx + 2, c.1 + h + 1, 3)
            }
            p.fill(p.ellipsePath(c.0, c.1, 20, 4), tc.alpha(0.85))
        case .research:
            p.ellipse(c.0, c.1 + 24, 36, 28, RGB(0.86, 0.62, 0.72))
            for i in 0..<6 {
                let x = c.0 - 28 + CGFloat(i) * 11
                p.stroke(p.ellipsePath(x, c.1 + 26 + CGFloat(i % 2) * 5, 5, 13), RGB(0.62, 0.36, 0.48), 2)
            }
            p.glow(c.0, c.1 + 30, 30, RGB(0.9, 0.6, 1, 0.35)); pore(c.0 + 4, c.1 + 42, 4)
            p.fill(p.ellipsePath(c.0, c.1 + 1, 30, 4.5), tc.alpha(0.85))
        case .tower:
            p.ellipse(c.0, c.1 + 6, 20, 10, chit)
            p.shape([(c.0 - 16, c.1 + 6), (c.0 - 3, c.1 + 104), (c.0 + 16, c.1 + 6)], RGB(0.52, 0.32, 0.52))
            p.shape([(c.0 + 2, c.1 + 6), (c.0 - 3, c.1 + 104), (c.0 + 16, c.1 + 6)], RGB(0.36, 0.20, 0.38))
            for (dx, dy) in [(-11, 30), (9, 48), (-7, 66), (11, 22), (5, 82)] as [(CGFloat, CGFloat)] { spike(c.0 + dx, c.1 + dy, 14, 3.4, dx > 0 ? 0.9 : -0.4) }
            pore(c.0 - 2, c.1 + 90, 3.5)
            p.fill(p.ellipsePath(c.0, c.1 + 2, 16, 3.5), tc.alpha(0.85))
        case .forward:
            for a in 0..<6 {
                let t = CGFloat(a) / 6 * .pi * 2
                p.limb((c.0, c.1 + 10), (c.0 + cos(t) * 36, c.1 + sin(t) * 16), chit.dark(0.1), 4.5)
            }
            p.limb((c.0, c.1 + 6), (c.0 + 2, c.1 + 50), chit, 6)
            p.ellipse(c.0 + 2, c.1 + 66, 15, 20, flesh)
            p.glow(c.0 + 2, c.1 + 68, 24, bio.alpha(0.55)); pore(c.0 + 2, c.1 + 68, 5)
            p.fill(p.ellipsePath(c.0, c.1 + 6, 18, 4), tc.alpha(0.85))
        }
    }
}
