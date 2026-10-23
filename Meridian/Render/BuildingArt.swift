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
        let table: [Faction: [BuildingKind: CGFloat]] = [
            .humans: [.hq: 120, .depot: 52, .infantry: 64, .heavy: 72, .air: 64, .research: 62, .tower: 100, .forward: 80],
            .machines: [.hq: 140, .depot: 50, .infantry: 44, .heavy: 72, .air: 96, .research: 72, .tower: 112, .forward: 112],
            .aliens: [.hq: 104, .depot: 42, .infantry: 52, .heavy: 62, .air: 92, .research: 58, .tower: 108, .forward: 90],
        ]
        return table[d.faction]?[d.kind] ?? 60
    }

    /// Light points (offset from footprint centre) that pulse at runtime: beacons, cores, glowing pores.
    static func lights(_ d: BuildingDef) -> [CGPoint] {
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

    /// Framed, lit windows along the front-left (sunlit) face at v between u0..u1, sill height z.
    static func windowsL(_ p: Pen, _ n: CGFloat, _ u0: CGFloat, _ u1: CGFloat, _ v: CGFloat, _ z: CGFloat, _ count: Int, _ c: RGB, h: CGFloat = 5) {
        for i in 0..<count {
            let u = u0 + (u1 - u0) * (CGFloat(i) + 0.5) / CGFloat(count)
            let w: CGFloat = 0.075
            let a = P(u - w, v, z, n), b = P(u + w, v, z, n), cc = P(u + w, v, z + h, n), d = P(u - w, v, z + h, n)
            p.fill(p.poly([P(u - w - 0.02, v, z - 0.8, n), P(u + w + 0.02, v, z - 0.8, n), P(u + w + 0.02, v, z + h + 0.8, n), P(u - w - 0.02, v, z + h + 0.8, n)]), RGB(0.12, 0.12, 0.13, 0.9))
            p.grad(p.poly([a, b, cc, d]), c.light(0.25), c.dark(0.25), from: CGPoint(x: d.0, y: d.1), to: CGPoint(x: a.0, y: a.1), outline: nil)
            p.line((d.0 + 0.6, d.1 - 0.8), (cc.0 - 0.6, cc.1 - 0.8 - (cc.1 - d.1) * 0.3), RGB(1, 1, 1, 0.45), 0.5)     // reflection
            p.line(P(u - w - 0.02, v, z - 0.9, n), P(u + w + 0.02, v, z - 0.9, n), RGB(0.85, 0.85, 0.8, 0.6), 0.6)    // sill
            p.glow((a.0 + cc.0) / 2, (a.1 + cc.1) / 2, 6, c.alpha(0.3))
        }
    }

    /// Windows along the front-right (shaded) face at u between v0..v1: dimmer, still lit from inside.
    static func windowsR(_ p: Pen, _ n: CGFloat, _ v0: CGFloat, _ v1: CGFloat, _ u: CGFloat, _ z: CGFloat, _ count: Int, _ c: RGB, h: CGFloat = 5) {
        for i in 0..<count {
            let v = v0 + (v1 - v0) * (CGFloat(i) + 0.5) / CGFloat(count)
            let w: CGFloat = 0.075
            p.fill(p.poly([P(u, v - w - 0.02, z - 0.8, n), P(u, v + w + 0.02, z - 0.8, n), P(u, v + w + 0.02, z + h + 0.8, n), P(u, v - w - 0.02, z + h + 0.8, n)]), RGB(0.08, 0.08, 0.09, 0.9))
            p.fill(p.poly([P(u, v - w, z, n), P(u, v + w, z, n), P(u, v + w, z + h, n), P(u, v - w, z + h, n)]), c.dark(0.35))
        }
    }

    /// Upright cylinder (silos, stacks, towers) with a shaded body, a dark seam band and a lit cap.
    static func cylinder(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ h: CGFloat, _ c: RGB, cap: RGB? = nil) {
        let body = p.roundRectPath(x - r, y, r * 2, h, 0.1)
        p.grad(body, c.light(0.2), c.dark(0.45), from: CGPoint(x: x - r * 0.6, y: y), to: CGPoint(x: x + r, y: y), outline: outline, lw: 0.9)
        p.fill(p.ellipsePath(x, y, r, r * 0.5), c.dark(0.3))
        if h > 12 { for z in stride(from: h * 0.3, to: h - 3, by: max(6, h * 0.3)) { p.stroke(p.ellipsePath(x, y + z, r, r * 0.5), c.dark(0.35).alpha(0.6), 0.6) } }
        p.line((x - r * 0.55, y + 2), (x - r * 0.55, y + h - 1), c.light(0.45).alpha(0.6), 0.8)
        p.solid(p.ellipsePath(x, y + h, r, r * 0.5), cap ?? c.light(0.15), outline: outline, lw: 0.9, contrast: 0.6)
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
        let concrete = RGB(0.72, 0.68, 0.60), armor = RGB(0.48, 0.51, 0.43), roof = RGB(0.52, 0.54, 0.50), win = RGB(1.0, 0.80, 0.42)
        let glass = RGB(0.55, 0.78, 0.92), steelC = RGB(0.62, 0.64, 0.64)
        WorldArt.pad(p, n, RGB(0.46, 0.45, 0.41))
        // Painted lane lines on the apron.
        p.line(P(0.25, 0.18, 0.5, n), P(n - 0.25, 0.18, 0.5, n), RGB(0.95, 0.85, 0.3, 0.35), 1.2)
        func barrier(_ u: CGFloat, _ v: CGFloat) { box(p, n, u, v, u + 0.28, v + 0.12, 0, 6, concrete.dark(0.05), concrete.light(0.1)) }
        func sandbags(_ u0: CGFloat, _ u1: CGFloat, _ v: CGFloat) {
            var u = u0
            while u < u1 { let q = P(u, v, 0, n); p.solid(p.ellipsePath(q.0, q.1 + 3, 5.2, 3.0), RGB(0.62, 0.56, 0.40), lw: 0.6, contrast: 1.2); u += 0.17 }
        }
        func lampPost(_ u: CGFloat, _ v: CGFloat, _ h: CGFloat = 30) {
            let q = P(u, v, 0, n)
            p.limb((q.0, q.1), (q.0, q.1 + h), RGB(0.3, 0.31, 0.32), 1.2)
            p.limb((q.0, q.1 + h), (q.0 + 4, q.1 + h + 1), RGB(0.3, 0.31, 0.32), 1.2)
            p.glow(q.0 + 4, q.1 + h - 1, 7, RGB(1, 0.92, 0.7, 0.55)); p.dot(q.0 + 4, q.1 + h - 0.5, 1.4, RGB(1, 0.95, 0.8))
        }
        func door(_ u: CGFloat, _ v: CGFloat, _ w: CGFloat = 0.22, _ h: CGFloat = 10) {
            let a = P(u - w / 2, v, 0.5, n), b2 = P(u + w / 2, v, 0.5, n)
            p.fill(p.poly([a, b2, (b2.0, b2.1 + h), (a.0, a.1 + h)]), RGB(0.12, 0.12, 0.13))
            p.grad(p.poly([(a.0 + 1, a.1 + 1), (b2.0 - 1, b2.1 + 1), (b2.0 - 1, b2.1 + h - 1), (a.0 + 1, a.1 + h - 1)]), win.alpha(0.9), win.dark(0.45), from: CGPoint(x: a.0, y: a.1 + h), to: CGPoint(x: a.0, y: a.1), outline: nil)
            p.glow((a.0 + b2.0) / 2, a.1 + 2, 9, win.alpha(0.35))
        }
        switch k {
        case .hq:
            box(p, n, 0.35, 0.35, n - 0.35, n - 0.35, 0, 26, armor, roof)
            windowsL(p, n, 0.6, n - 0.6, 0.35, 12, 6, win)
            windowsR(p, n, 0.6, n - 0.6, n - 0.35, 12, 6, win)
            hazard(p, P(0.4, 0.35, 3, n), P(n - 0.4, 0.35, 3, n), 3)
            door(n * 0.5, 0.35, 0.36, 11)
            box(p, n, n * 0.38, 0.12, n * 0.62, 0.35, 12, 14, steelC, steelC.light(0.15))                     // entrance canopy
            // Upper deck clutter on the low roof.
            WorldArt.roofUnit(p, n, 0.55, n - 0.95, 26, 0.34)
            WorldArt.roofUnit(p, n, n - 0.95, 0.55, 26, 0.3)
            box(p, n, 1.0, 0.9, n - 1.2, n - 1.0, 26, 54, concrete, roof.light(0.05))
            windowsL(p, n, 1.2, n - 1.4, 0.9, 38, 4, glass, h: 8)
            windowsR(p, n, 1.1, n - 1.2, n - 1.2, 38, 3, glass, h: 8)
            p.line(P(1.0, 0.9, 48, n), P(n - 1.2, 0.9, 48, n), tc, 4)
            box(p, n, 1.5, 1.4, n - 1.9, n - 1.8, 54, 78, concrete.light(0.05), roof)
            windowsL(p, n, 1.6, n - 2.0, 1.4, 64, 2, glass, h: 6)
            let top = P(n * 0.5, n * 0.5, 78, n)
            antenna(p, top.0 - 6, top.1, 42)
            p.dot(top.0 + 12, top.1 - 4, 3, RGB(0.3, 0.3, 0.32))
            let hp = P(n - 0.9, n - 0.9, 26, n)
            p.fill(p.ellipsePath(hp.0, hp.1, 15, 7.5), RGB(0.3, 0.32, 0.31, 0.7))
            p.stroke(p.ellipsePath(hp.0, hp.1, 13, 6.5), RGB(1, 1, 1, 0.85), 1.5); p.line((hp.0 - 4, hp.1), (hp.0 + 4, hp.1), RGB(1, 1, 1, 0.85), 1.5)
            barrier(0.15, 0.05); barrier(n - 0.5, 0.05)
            lampPost(0.2, 0.2); lampPost(n - 0.2, 0.2)
        case .depot:
            box(p, n, 0.15, 0.2, n * 0.62, n - 0.15, 0, 22, concrete, roof)
            let d0 = P(0.3, 0.2, 2, n), d1 = P(n * 0.55, 0.2, 2, n)
            p.solid(p.poly([d0, d1, (d1.0, d1.1 + 14), (d0.0, d0.1 + 14)]), RGB(0.34, 0.35, 0.33), lw: 0.8, contrast: 0.6)
            for z in stride(from: 4 as CGFloat, to: 15, by: 2.6) { p.line((d0.0, d0.1 + z), (d1.0, d1.1 + z), RGB(0.24, 0.24, 0.24, 0.8), 0.6) }   // roller door slats
            hazard(p, (d0.0, d0.1 + 15), (d1.0, d1.1 + 15), 2.5)
            // Skylights.
            for v in [0.45, 0.85] as [CGFloat] where v < n - 0.3 { p.fill(p.poly([P(0.3, v, 22, n), P(n * 0.55, v, 22, n), P(n * 0.55, v + 0.12, 22, n), P(0.3, v + 0.12, 22, n)]), glass.alpha(0.7)) }
            WorldArt.vent(p, n, n * 0.35, n - 0.4, 22, 6)
            let sp = P(n * 0.82, n * 0.6, 0, n)
            cylinder(p, sp.0, sp.1, 11, 40, RGB(0.76, 0.74, 0.68))
            p.line((sp.0 - 11, sp.1 + 26), (sp.0 + 11, sp.1 + 26), tc, 3)
            p.limb((sp.0 + 8, sp.1 + 2), (sp.0 + 8, sp.1 + 38), RGB(0.35, 0.35, 0.36), 0.8)                   // ladder
            crate(p, n, n * 0.68, 0.15, 0, 0.32, RGB(0.55, 0.42, 0.24))
            crate(p, n, n * 0.68, 0.15, 8.3, 0.32, RGB(0.36, 0.48, 0.30))
            crate(p, n, n * 0.68 + 0.36, 0.15, 0, 0.28, RGB(0.36, 0.48, 0.30))
        case .infantry:
            // Barrel-vault barracks with ribbed roof and an annex.
            box(p, n, 0.3, 0.3, n - 0.3, n * 0.62, 0, 20, armor, roof)
            let a = P(0.3, 0.3, 20, n), b = P(n - 0.3, 0.3, 20, n), c = P(n - 0.3, n * 0.62, 20, n), d = P(0.3, n * 0.62, 20, n)
            let arch = CGMutablePath(); arch.move(to: CGPoint(x: a.0, y: a.1)); arch.addLine(to: CGPoint(x: b.0, y: b.1))
            arch.addQuadCurve(to: CGPoint(x: c.0, y: c.1), control: CGPoint(x: (b.0 + c.0) / 2, y: (b.1 + c.1) / 2 + 22))
            arch.addLine(to: CGPoint(x: d.0, y: d.1))
            arch.addQuadCurve(to: CGPoint(x: a.0, y: a.1), control: CGPoint(x: (a.0 + d.0) / 2, y: (a.1 + d.1) / 2 + 22)); arch.closeSubpath()
            p.grad(arch, roof.light(0.3), roof.dark(0.2), from: CGPoint(x: (a.0 + d.0) / 2, y: (a.1 + d.1) / 2 + 20), to: CGPoint(x: (b.0 + c.0) / 2, y: (b.1 + c.1) / 2), outline: outline, lw: 1.0)
            for i in 1..<6 {
                let u = 0.3 + (n - 0.6) * CGFloat(i) / 6
                let q0 = P(u, 0.3, 20, n), q1 = P(u, n * 0.62, 20, n)
                let rib = CGMutablePath(); rib.move(to: CGPoint(x: q0.0, y: q0.1)); rib.addQuadCurve(to: CGPoint(x: q1.0, y: q1.1), control: CGPoint(x: (q0.0 + q1.0) / 2, y: (q0.1 + q1.1) / 2 + 22))
                p.stroke(rib, roof.dark(0.3), 1.0)
            }
            windowsL(p, n, 0.5, n - 0.5, 0.3, 8, 5, win)
            door(n * 0.5, 0.3)
            box(p, n, 0.3, n * 0.66, n * 0.5, n - 0.3, 0, 14, concrete, roof)
            WorldArt.vent(p, n, n * 0.25, n * 0.8, 14, 6)
            let f = P(n - 0.5, n - 0.5, 0, n)
            p.limb((f.0, f.1), (f.0, f.1 + 62), RGB(0.3, 0.3, 0.3), 1.6)   // flag flies at runtime
            p.dot(f.0, f.1 + 62.5, 1.6, RGB(0.8, 0.75, 0.4))
            sandbags(0.2, n * 0.45, 0.08)
        case .heavy:
            box(p, n, 0.2, 0.25, n - 0.2, n - 0.2, 0, 34, armor.dark(0.05), roof)
            for (u0, u1) in [(0.4, n * 0.45), (n * 0.55, n - 0.4)] {
                let a = P(u0, 0.25, 1, n), b = P(u1, 0.25, 1, n)
                p.solid(p.poly([a, b, (b.0, b.1 + 22), (a.0, a.1 + 22)]), RGB(0.28, 0.29, 0.28), lw: 0.8, contrast: 0.6)
                for z in stride(from: 4 as CGFloat, to: 22, by: 3) { p.line((a.0, a.1 + z), (b.0, b.1 + z), RGB(0.40, 0.40, 0.38), 0.8) }
                hazard(p, (a.0, a.1 + 24), (b.0, b.1 + 24), 3)
                p.glow((a.0 + b.0) / 2, a.1 + 3, 14, RGB(1, 0.75, 0.4, 0.3))                                  // work lights spill under the doors
            }
            p.line(P(0.2, 0.25, 30, n), P(n - 0.2, 0.25, 30, n), tc, 3)
            // Roof: skylight strips and extractor fans.
            for v in stride(from: 0.6 as CGFloat, to: n - 0.6, by: 0.55) { p.fill(p.poly([P(0.5, v, 34, n), P(n - 0.9, v, 34, n), P(n - 0.9, v + 0.14, 34, n), P(0.5, v + 0.14, 34, n)]), glass.alpha(0.55)) }
            WorldArt.roofUnit(p, n, n - 0.9, 0.5, 34, 0.32); WorldArt.roofUnit(p, n, 0.5, 0.5, 34, 0.28)
            let c0 = P(n - 0.6, n - 0.6, 34, n)
            p.limb((c0.0, c0.1), (c0.0, c0.1 + 36), RGB(0.95, 0.72, 0.15), 3)
            p.limb((c0.0, c0.1 + 36), (c0.0 - 48, c0.1 + 30), RGB(0.95, 0.72, 0.15), 3)
            for k in 1..<6 { let t = CGFloat(k) / 6; p.line((c0.0 - 48 * t, c0.1 + 36 - 6 * t), (c0.0 - 48 * t + 2, c0.1 + 33 - 6 * t), RGB(0.6, 0.45, 0.1), 0.6) }  // truss
            let st = P(0.6, n - 0.5, 34, n)
            cylinder(p, st.0, st.1, 6, 18, RGB(0.6, 0.35, 0.2))
            for k in 0..<3 { let q = P(n - 0.25, 0.4 + CGFloat(k) * 0.2, 0, n); cylinder(p, q.0, q.1, 3.2, 8, RGB(0.55, 0.25, 0.18)) }   // oil drums
        case .air:
            WorldArt.pad(p, n, RGB(0.32, 0.33, 0.34))
            for k in 0..<4 { let q0 = P(0.25 + CGFloat(k) * 0.28, 0.25, 0.5, n), q1 = P(0.25 + CGFloat(k) * 0.28 + 0.14, 0.25, 0.5, n); p.line(q0, q1, RGB(1, 1, 1, 0.6), 1.4) }   // runway dashes
            let pad = P(n * 0.3, n * 0.36, 1, n)
            p.fill(p.ellipsePath(pad.0, pad.1, 28, 14), RGB(0.24, 0.26, 0.27, 0.8))
            p.stroke(p.ellipsePath(pad.0, pad.1, 26, 13), RGB(1, 1, 1, 0.85), 2); p.line((pad.0 - 8, pad.1), (pad.0 + 8, pad.1), RGB(1, 1, 1, 0.85), 2)
            p.line((pad.0 - 8, pad.1 - 4), (pad.0 - 8, pad.1 + 4), RGB(1, 1, 1, 0.85), 2); p.line((pad.0 + 8, pad.1 - 4), (pad.0 + 8, pad.1 + 4), RGB(1, 1, 1, 0.85), 2)
            box(p, n, n * 0.5, 0.25, n - 0.2, n - 0.2, 0, 16, armor, roof)
            let a = P(n * 0.5, 0.25, 16, n), b = P(n - 0.2, 0.25, 16, n), c = P(n - 0.2, n - 0.2, 16, n), d = P(n * 0.5, n - 0.2, 16, n)
            let arch = CGMutablePath(); arch.move(to: CGPoint(x: a.0, y: a.1)); arch.addLine(to: CGPoint(x: b.0, y: b.1))
            arch.addQuadCurve(to: CGPoint(x: c.0, y: c.1), control: CGPoint(x: (b.0 + c.0) / 2 + 4, y: (b.1 + c.1) / 2 + 34))
            arch.addLine(to: CGPoint(x: d.0, y: d.1))
            arch.addQuadCurve(to: CGPoint(x: a.0, y: a.1), control: CGPoint(x: (a.0 + d.0) / 2 + 4, y: (a.1 + d.1) / 2 + 34)); arch.closeSubpath()
            p.grad(arch, RGB(0.70, 0.75, 0.80), RGB(0.38, 0.42, 0.48), from: CGPoint(x: (a.0 + d.0) / 2, y: (a.1 + d.1) / 2 + 30), to: CGPoint(x: (b.0 + c.0) / 2, y: (b.1 + c.1) / 2), outline: outline, lw: 1.0)
            for i in 1..<5 {
                let u = n * 0.5 + (n * 0.5 - 0.2) * CGFloat(i) / 5
                let q0 = P(u, 0.25, 16, n), q1 = P(u, n - 0.2, 16, n)
                let rib = CGMutablePath(); rib.move(to: CGPoint(x: q0.0, y: q0.1)); rib.addQuadCurve(to: CGPoint(x: q1.0, y: q1.1), control: CGPoint(x: (q0.0 + q1.0) / 2 + 4, y: (q0.1 + q1.1) / 2 + 34))
                p.stroke(rib, RGB(0.32, 0.36, 0.42, 0.8), 0.9)
            }
            p.line(P(n * 0.55, 0.25, 10, n), P(n - 0.3, 0.25, 10, n), tc, 3)
            let t = P(0.45, n - 0.5, 0, n)
            cylinder(p, t.0, t.1, 6, 46, concrete)
            p.solid(p.poly([(t.0 - 11, t.1 + 46), (t.0 + 11, t.1 + 46), (t.0 + 8, t.1 + 56), (t.0 - 8, t.1 + 56)]), RGB(0.35, 0.6, 0.75), lw: 0.9)
            p.line((t.0 - 9, t.1 + 52), (t.0 + 9, t.1 + 52), RGB(0.8, 0.95, 1, 0.6), 0.8)
            p.glow(t.0, t.1 + 51, 9, RGB(0.6, 0.9, 1, 0.5))
            let fuel = P(n - 0.35, 0.55, 0, n)
            cylinder(p, fuel.0, fuel.1, 7, 12, RGB(0.85, 0.82, 0.74)); p.line((fuel.0 - 7, fuel.1 + 6), (fuel.0 + 7, fuel.1 + 6), RGB(0.9, 0.2, 0.2), 1.5)
        case .research:
            box(p, n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 18, concrete, roof)
            windowsL(p, n, 0.4, n - 0.4, 0.25, 7, 6, RGB(0.55, 0.9, 1.0))
            windowsR(p, n, 0.4, n - 0.4, n - 0.25, 7, 6, RGB(0.55, 0.9, 1.0))
            // Solar array on the deck.
            for k in 0..<3 {
                let u = 0.45 + CGFloat(k) * 0.22
                p.solid(p.poly([P(u, 0.4, 19, n), P(u + 0.16, 0.4, 19, n), P(u + 0.16, 0.85, 23, n), P(u, 0.85, 23, n)]), RGB(0.18, 0.26, 0.42), lw: 0.5, contrast: 0.8)
                p.line(P(u + 0.08, 0.4, 19, n), P(u + 0.08, 0.85, 23, n), RGB(0.6, 0.75, 1, 0.5), 0.4)
            }
            WorldArt.dome(p, n, n * 0.48, n * 0.5, 18, n * 0.3, RGB(0.84, 0.88, 0.92), tall: 0.95)
            let s2 = P(n * 0.48, n * 0.5, 18, n)
            p.fill(p.roundRectPath(s2.0 - 3, s2.1 + 10, 6, 28, 2), RGB(0.15, 0.2, 0.3, 0.7))
            p.limb((s2.0, s2.1 + 26), (s2.0 + 14, s2.1 + 44), RGB(0.3, 0.32, 0.36), 4)
            p.dot(P(n - 0.5, n - 0.5, 18, n).0, P(n - 0.5, n - 0.5, 18, n).1, 2.5, RGB(0.3, 0.3, 0.32))
            p.line(P(0.25, 0.25, 14, n), P(n - 0.25, 0.25, 14, n), tc, 3)
            door(n * 0.25 + 0.3, 0.25, 0.2, 8)
        case .tower:
            let b = P(n * 0.5, n * 0.5, 0, n)
            box(p, n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 14, armor, roof)
            p.solid(p.poly([(b.0 - 20, b.1 + 6), (b.0 - 13, b.1 + 82), (b.0, b.1 + 76), (b.0, b.1 - 4)]), concrete, lw: 1.0)
            p.solid(p.poly([(b.0, b.1 - 4), (b.0, b.1 + 76), (b.0 + 13, b.1 + 82), (b.0 + 20, b.1 + 6)]), concrete.dark(0.3), lw: 1.0)
            for z in stride(from: 20 as CGFloat, to: 72, by: 13) {
                p.line((b.0 - 19 + z * 0.08, b.1 + z + 4), (b.0, b.1 + z), concrete.dark(0.3).alpha(0.6), 0.7)
                p.line((b.0, b.1 + z), (b.0 + 19 - z * 0.08, b.1 + z + 4), concrete.dark(0.55).alpha(0.6), 0.7)
            }
            p.line((b.0 - 17, b.1 + 46), (b.0 + 17, b.1 + 46), tc, 4)
            p.fill(p.roundRectPath(b.0 - 12, b.1 + 60, 7, 3, 1), RGB(0.12, 0.12, 0.13)); p.fill(p.roundRectPath(b.0 + 4, b.1 + 60, 7, 3, 1), RGB(0.1, 0.1, 0.11))   // gun slits
            p.solid(p.poly([(b.0 - 22, b.1 + 82), (b.0, b.1 + 92), (b.0 + 22, b.1 + 82), (b.0, b.1 + 72)]), roof.light(0.1), lw: 1.0)
            p.box(b.0 - 9, b.1 + 86, 18, 11, RGB(0.32, 0.34, 0.33))
            p.limb((b.0 + 4, b.1 + 92), (b.0 + 26, b.1 + 95), RGB(0.18, 0.18, 0.2), 3)
            p.limb((b.0 + 4, b.1 + 89), (b.0 + 26, b.1 + 91), RGB(0.18, 0.18, 0.2), 3)
            p.glow(b.0 - 14, b.1 + 84, 10, RGB(1, 0.95, 0.75, 0.6))
            sandbags(0.2, n - 0.2, 0.05)
        case .forward:
            let c = P(n * 0.5, n * 0.5, 0, n)
            for a in 0..<12 { let t = CGFloat(a) / 12 * .pi * 2; p.solid(p.ellipsePath(c.0 + cos(t) * 34, c.1 + sin(t) * 15 - 2, 6, 3.4), RGB(0.64, 0.58, 0.42), lw: 0.6, contrast: 1.2) }
            // Camouflage-netted command tent.
            p.solid(p.poly([(c.0 - 28, c.1 - 2), (c.0 - 2, c.1 + 30), (c.0 - 2, c.1 - 14)]), RGB(0.47, 0.52, 0.38), lw: 0.9)
            p.solid(p.poly([(c.0 - 2, c.1 + 30), (c.0 + 24, c.1 - 2), (c.0 - 2, c.1 - 14)]), RGB(0.34, 0.39, 0.28), lw: 0.9)
            for k in 0..<5 { p.dot(c.0 - 18 + CGFloat(k) * 8, c.1 + 4 + CGFloat(k % 2) * 6, 2.2, RGB(0.3, 0.36, 0.22, 0.8)) }
            p.fill(p.poly([(c.0 - 6, c.1 - 9), (c.0 + 2, c.1 - 9), (c.0 + 2, c.1 + 4), (c.0 - 6, c.1 + 4)]), RGB(1, 0.8, 0.45, 0.8))   // lit flap
            p.line((c.0 - 18, c.1 + 6), (c.0 - 2, c.1 + 24), tc, 3)
            box(p, n, n * 0.62, n * 0.25, n * 0.62 + 0.3, n * 0.25 + 0.22, 0, 7, RGB(0.36, 0.42, 0.30), RGB(0.42, 0.48, 0.35))   // radio crate
            antenna(p, c.0 + 22, c.1 + 10, 70, light: RGB(0.3, 1, 0.45))
            p.limb((c.0 - 26, c.1 + 2), (c.0 - 26, c.1 + 34), RGB(0.3, 0.3, 0.3), 1.5)
            p.glow(c.0 - 26, c.1 + 36, 12, RGB(1, 0.95, 0.7, 0.7))
        }
    }

    // MARK: Lattice (machines)

    static func machine(_ p: Pen, _ k: BuildingKind, _ n: CGFloat, _ tc: RGB) {
        let obs = RGB(0.20, 0.22, 0.28), obs2 = RGB(0.31, 0.34, 0.41), roof = RGB(0.17, 0.18, 0.23), cyan = RGB(0.35, 0.95, 1.0)
        // Hex plinth with real thickness, a glowing inner rim and nodes at the corners.
        let c = P(n * 0.5, n * 0.5, 0, n)
        let hex = (0..<6).map { (c.0 + cos(CGFloat($0) * .pi / 3) * 30 * n, c.1 + sin(CGFloat($0) * .pi / 3) * 15 * n) }
        let lowHex = hex.map { ($0.0, $0.1 - 4) }
        p.fill(p.poly(lowHex), RGB(0.08, 0.09, 0.12))
        for i in [3, 4, 5, 0] {        // front side walls
            let j = (i + 1) % 6
            p.fill(p.poly([hex[i], hex[j], lowHex[j], lowHex[i]]), i == 4 || i == 3 ? RGB(0.15, 0.16, 0.2) : RGB(0.1, 0.11, 0.14))
        }
        p.grad(p.poly(hex), RGB(0.24, 0.26, 0.32), RGB(0.13, 0.14, 0.18), from: CGPoint(x: hex[2].0, y: hex[2].1), to: CGPoint(x: hex[5].0, y: hex[5].1), outline: RGB(0, 0, 0, 0.6), lw: 0.9)
        let rim = hex.map { (c.0 + ($0.0 - c.0) * 0.86, c.1 + ($0.1 - c.1) * 0.86) }
        p.stroke(p.poly(rim), cyan.alpha(0.22), 4); p.stroke(p.poly(rim), cyan.alpha(0.7), 1.2)
        for q in rim { p.glow(q.0, q.1, 5, cyan.alpha(0.5)); p.dot(q.0, q.1, 1.2, cyan.light(0.4)) }
        func core(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            p.glow(x, y, r * 3.2, cyan.alpha(0.7))
            p.ball(x, y, r, r, cyan.light(0.2), outline: RGB(0.05, 0.15, 0.2, 0.8), lw: 0.8, shine: 1)
            p.dot(x - r * 0.3, y + r * 0.3, r * 0.35, RGB(1, 1, 1))
        }
        func circuit(_ a: P2, _ b: P2) { p.line(a, b, cyan.alpha(0.25), 4); p.line(a, b, cyan.alpha(0.95), 1.4) }
        func obelisk(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            let left = p.poly([(x - w, y), (x - w * 0.55, y + h), (x, y + h + w * 0.5), (x, y - w * 0.5)])
            let right = p.poly([(x, y - w * 0.5), (x, y + h + w * 0.5), (x + w * 0.55, y + h), (x + w, y)])
            p.grad(left, obs2.light(0.18), obs2.dark(0.2), from: CGPoint(x: x - w, y: y + h), to: CGPoint(x: x, y: y), outline: outline, lw: 1.0)
            p.grad(right, obs.dark(0.05), obs.dark(0.45), from: CGPoint(x: x, y: y + h), to: CGPoint(x: x + w, y: y), outline: outline, lw: 1.0)
            p.line((x - w * 0.55, y + h), (x, y + h + w * 0.5), RGB(0.75, 0.85, 1, 0.55), 0.8)                         // lit top edge
            p.line((x - w + 1, y + 1), (x - w * 0.55 + 0.6, y + h - 1), RGB(0.7, 0.8, 0.95, 0.35), 0.7)                 // left silhouette sheen
            for t in [0.3, 0.6] as [CGFloat] {
                let yy = y + h * t
                p.line((x - w + (w * 0.45) * t, yy), (x, yy - w * 0.25), cyan.alpha(0.35), 0.6)
                p.line((x, yy - w * 0.25), (x + w - (w * 0.45) * t, yy), cyan.alpha(0.2), 0.6)
            }
            p.line((x, y + 4), (x, y + h - 4), cyan.alpha(0.3), 3.6)
            p.line((x, y + 4), (x, y + h - 4), cyan.alpha(0.95), 1.1)
        }
        /// Obsidian block with glowing edge trim along the visible top edges.
        func mbox(_ n: CGFloat, _ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat, _ z0: CGFloat, _ z1: CGFloat, _ wall: RGB, _ rf: RGB) {
            WorldArt.prism(p, n, u0, v0, u1, v1, z0, z1, wall: wall, roof: rf, seams: 0.34)
            p.line(P(u0, v0, z1, n), P(u1, v0, z1, n), cyan.alpha(0.55), 0.9)
            p.line(P(u1, v0, z1, n), P(u1, v1, z1, n), cyan.alpha(0.35), 0.9)
            p.line(P(u0, v0, z0 + 2, n), P(u1, v0, z0 + 2, n), cyan.alpha(0.25), 0.7)
            // Circuit-grid roof: faint panel grid with a few live nodes.
            let e: CGFloat = 0.1
            var u = u0 + 0.3
            while u < u1 - 0.1 { p.line(P(u, v0 + e, z1, n), P(u, v1 - e, z1, n), RGB(0, 0, 0, 0.3), 0.6); u += 0.3 }
            var v = v0 + 0.3
            while v < v1 - 0.1 { p.line(P(u0 + e, v, z1, n), P(u1 - e, v, z1, n), RGB(0, 0, 0, 0.3), 0.6); v += 0.3 }
            var k = 0
            u = u0 + 0.3
            while u < u1 - 0.1 {
                v = v0 + 0.3
                while v < v1 - 0.1 {
                    if hnoise(Int(u * 10), Int(v * 10), Int(z1)) > 0.72 { let q = P(u, v, z1, n); p.glow(q.0, q.1, 4, cyan.alpha(0.45)); p.dot(q.0, q.1, 0.9, cyan.light(0.3)) }
                    v += 0.3; k += 1
                }
                u += 0.3
            }
        }
        switch k {
        case .hq:
            mbox(n, 0.4, 0.4, n - 0.4, n - 0.4, 0, 20, obs2, roof)
            mbox(n, 0.9, 0.9, n - 0.9, n - 0.9, 20, 44, obs2.light(0.05), roof)
            obelisk(c.0, c.1 + 44, 18, 62)
            circuit(P(0.4, 0.4, 10, n), P(n - 0.4, 0.4, 10, n)); circuit(P(n - 0.4, 0.4, 10, n), P(n - 0.4, n - 0.4, 10, n))
            p.line(P(0.9, 0.9, 32, n), P(n - 0.9, 0.9, 32, n), tc, 4)
            core(c.0, c.1 + 130, 9)
            p.stroke(p.ellipsePath(c.0, c.1 + 128, 26, 8), cyan.alpha(0.8), 2)
        case .depot:
            mbox(n, 0.2, 0.2, n - 0.2, n - 0.2, 0, 16, obs2, roof)
            for u in [0.35, 0.7] as [CGFloat] {
                let s = P(u * n, n * 0.62, 16, n)
                cylinder(p, s.0, s.1, 5, 26, obs)
                p.glow(s.0, s.1 + 30, 10, RGB(1, 0.55, 0.15, 0.85)); p.dot(s.0, s.1 + 27, 3, RGB(1, 0.8, 0.4))
            }
            circuit(P(0.2, 0.2, 8, n), P(n - 0.2, 0.2, 8, n))
            p.line(P(0.2, 0.2, 13, n), P(n - 0.2, 0.2, 13, n), tc, 2.5)
        case .infantry:
            mbox(n, 0.3, 0.3, n - 0.3, n * 0.55, 0, 22, obs2, roof)
            mbox(n, 0.3, n * 0.55, n - 0.3, n - 0.3, 0, 36, obs2.light(0.04), roof)
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
            mbox(n, 0.2, 0.2, n - 0.2, n - 0.2, 0, 40, obs, roof)
            let g0 = P(n * 0.25, 0.2, 2, n), g1 = P(n * 0.75, 0.2, 2, n)
            p.shade(p.poly([g0, g1, (g1.0, g1.1 + 26), (g0.0, g0.1 + 26)]), RGB(0.05, 0.05, 0.08))
            p.glow((g0.0 + g1.0) / 2, g0.1 + 12, 26, RGB(1, 0.5, 0.15, 0.55))
            p.line(P(0.2, 0.2, 32, n), P(n - 0.2, 0.2, 32, n), tc, 4)
            circuit(P(n - 0.2, 0.3, 20, n), P(n - 0.2, n - 0.3, 20, n))
            obelisk(P(n * 0.7, n * 0.7, 40, n).0, P(n * 0.7, n * 0.7, 40, n).1, 8, 30)
        case .air:
            mbox(n, 0.3, 0.3, n - 0.3, n - 0.3, 0, 10, obs2, roof)
            obelisk(c.0, c.1 + 10, 9, 72)
            for (z, r) in [(30, 24), (50, 19), (70, 14)] as [(CGFloat, CGFloat)] { p.stroke(p.ellipsePath(c.0, c.1 + z, r, r * 0.33), cyan.alpha(0.85), 2) }
            p.line((c.0 - 6, c.1 + 20), (c.0 + 6, c.1 + 20), tc, 3)
            core(c.0, c.1 + 90, 5)
        case .research:
            mbox(n, 0.25, 0.25, n - 0.25, n - 0.25, 0, 12, obs2, roof)
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
        // Creep mat: an organic, wobbling edge, darker and wetter toward the centre.
        let rx = 31 * n, ry = 15.5 * n
        var edge: [(CGFloat, CGFloat)] = []
        for i in 0..<28 {
            let t = CGFloat(i) / 28 * .pi * 2
            let w = 0.9 + 0.12 * hnoise(i, Int(n), 7)
            edge.append((c.0 + cos(t) * rx * w, c.1 + sin(t) * ry * w))
        }
        // Root tendrils reaching past the edge.
        for i in 0..<9 {
            let t = CGFloat(i) / 9 * .pi * 2 + 0.2
            let a: (CGFloat, CGFloat) = (c.0 + cos(t) * rx * 0.8, c.1 + sin(t) * ry * 0.8)
            let b: (CGFloat, CGFloat) = (c.0 + cos(t + 0.15) * rx * 1.12, c.1 + sin(t + 0.15) * ry * 1.12)
            p.capsule(a, b, 1.6, 0.4, RGB(0.36, 0.18, 0.36), lw: 0.5)
        }
        let mat = p.poly(edge)
        p.ctx.saveGState(); p.ctx.addPath(mat); p.ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [RGB(0.20, 0.10, 0.22).cg, RGB(0.32, 0.17, 0.33).cg, RGB(0.40, 0.24, 0.38).cg] as CFArray, locations: [0, 0.6, 1])!
        p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.0, y: c.1), startRadius: 0, endCenter: CGPoint(x: c.0, y: c.1), endRadius: rx, options: [.drawsAfterEndLocation])
        p.ctx.restoreGState()
        p.stroke(mat, RGB(0.12, 0.05, 0.13, 0.8), 1.0)
        // Veins: curving channels with a faint inner light.
        for a in 0..<9 {
            let t = CGFloat(a) / 9 * .pi * 2 + hnoise(a, 3, Int(n)) * 0.4
            let path = CGMutablePath()
            path.move(to: CGPoint(x: c.0 + cos(t) * 6 * n, y: c.1 + sin(t) * 3 * n))
            path.addQuadCurve(to: CGPoint(x: c.0 + cos(t + 0.35) * rx * 0.88, y: c.1 + sin(t + 0.35) * ry * 0.88),
                              control: CGPoint(x: c.0 + cos(t - 0.25) * rx * 0.5, y: c.1 + sin(t - 0.25) * ry * 0.5))
            p.stroke(path, RGB(0.12, 0.04, 0.14, 0.9), 2.6)
            p.stroke(path, RGB(0.62, 0.30, 0.58, 0.85), 1.2)
            p.stroke(path, bio.alpha(0.18), 3.6)
        }
        for i in 0..<Int(10 * n) {
            let t = hnoise(i, 5, Int(n)) * .pi * 2, r = 0.3 + 0.6 * hnoise(i, 6, Int(n))
            let q = (c.0 + cos(t) * rx * r, c.1 + sin(t) * ry * r)
            p.glow(q.0, q.1, 3, bio.alpha(0.5)); p.dot(q.0, q.1, 0.8, bio.light(0.4))
        }
        func pore(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            p.fill(p.ellipsePath(x, y, r * 1.5, r * 1.2), RGB(0.12, 0.04, 0.12))
            p.lamp(x, y, r, bio)
        }
        func spike(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ w: CGFloat, _ lean: CGFloat = 0.2) {
            let sp = p.poly([(x - w, y), (x + w * lean, y + h), (x + w, y)])
            p.grad(sp, bone.light(0.15), bone.dark(0.35), from: CGPoint(x: x - w, y: y + h * 0.5), to: CGPoint(x: x + w, y: y), outline: outline, lw: 0.9)
            p.line((x - w * 0.35, y + 2), (x + w * lean * 0.8, y + h - 3), RGB(1, 1, 0.95, 0.6), 0.8)
            for k in 1..<3 { let t = CGFloat(k) / 3; p.line((x - w * (1 - t), y + h * t * 0.9), (x + w * (1 - t) * 0.8, y + h * t * 0.9), bone.dark(0.3), 0.6) }   // growth rings
        }
        /// Glossy ribbed carapace dome.
        func ribbed(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ col: RGB) {
            p.ball(x, y, rx, ry, col, lw: 1.0, shine: 0.9)
            for i in 1..<6 {
                let t = CGFloat(i) / 6
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: x - rx + 2 * rx * t, y: y), radius: ry * 0.95, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                p.stroke(path, col.dark(0.45), 1.3)
                let hl = CGMutablePath()
                hl.addArc(center: CGPoint(x: x - rx + 2 * rx * t - 1.2, y: y), radius: ry * 0.95, startAngle: .pi * 0.4, endAngle: .pi * 0.7, clockwise: false)
                p.stroke(hl, col.light(0.45).alpha(0.5), 0.7)
            }
            p.fill(p.ellipsePath(x - rx * 0.35, y + ry * 0.5, rx * 0.22, ry * 0.12), RGB(1, 1, 1, 0.5))
        }
        switch k {
        case .hq:
            ribbed(c.0, c.1 + 26, 28 * n * 0.62, 32, chit)
            p.ball(c.0 + 6, c.1 + 50, 20, 22, flesh)
            p.glow(c.0 + 6, c.1 + 52, 28, RGB(1, 0.4, 0.6, 0.45))      // heart glow
            pore(c.0 + 6, c.1 + 52, 5)
            p.fill(p.ellipsePath(c.0, c.1 + 6, 30, 6), tc.alpha(0.85))
            spike(c.0 - 40, c.1 + 30, 46, 7); spike(c.0 + 38, c.1 + 34, 40, 7, 0.4); spike(c.0 - 14, c.1 + 66, 38, 5)
            for (dx, dy) in [(-28, 18), (26, 16), (-10, 30)] as [(CGFloat, CGFloat)] { pore(c.0 + dx, c.1 + dy, 2.5) }
        case .depot:
            p.ball(c.0, c.1 + 2, 26 * n * 0.75, 13, chit.dark(0.25))
            p.fill(p.ellipsePath(c.0, c.1 + 4, 17 * n * 0.75, 7), RGB(0.40, 0.82, 0.28)); p.glow(c.0, c.1 + 6, 18, bio.alpha(0.55))
            for a in 0..<5 {
                let t = CGFloat(a) / 5 * .pi * 2 + 0.3
                p.capsule((c.0 + cos(t) * 22, c.1 + sin(t) * 10 + 4), (c.0 + cos(t) * 30, c.1 + sin(t) * 13 + 30), 5 * 0.6, 5 * 0.42, flesh)
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
                p.ball(c.0 + dx, c.1 + dy, r, r * 0.92, flesh.dark(0.12))
                p.ball(c.0 + dx + 4, c.1 + dy + 2, r * 0.45, r * 0.4, RGB(0.85, 0.75, 0.45, 0.6))   // embryo shadow
                pore(c.0 + dx + 6, c.1 + dy + 6, 3)
            }
            p.fill(p.ellipsePath(c.0, c.1 - 8, 32, 5), tc.alpha(0.85))
        case .air:
            p.ball(c.0, c.1 + 6, 24, 12, chit)
            for (dx, h) in [(-22, 60), (4, 76), (24, 52)] as [(CGFloat, CGFloat)] {
                p.capsule((c.0 + dx, c.1 + 6), (c.0 + dx + 2, c.1 + h), 5 * 0.6, 5 * 0.42, chit.light(0.08))
                for k in 0..<5 {
                    let a = CGFloat(k) / 5 * .pi * 2
                    p.shape([(c.0 + dx + 2, c.1 + h), (c.0 + dx + 2 + cos(a) * 16, c.1 + h + sin(a) * 9 + 4), (c.0 + dx + 2 + cos(a + 0.5) * 8, c.1 + h + sin(a + 0.5) * 4)], flesh.light(0.08))
                }
                pore(c.0 + dx + 2, c.1 + h + 1, 3)
            }
            p.fill(p.ellipsePath(c.0, c.1, 20, 4), tc.alpha(0.85))
        case .research:
            p.ball(c.0, c.1 + 24, 36, 28, RGB(0.86, 0.62, 0.72))
            for i in 0..<6 {
                let x = c.0 - 28 + CGFloat(i) * 11
                p.stroke(p.ellipsePath(x, c.1 + 26 + CGFloat(i % 2) * 5, 5, 13), RGB(0.62, 0.36, 0.48), 2)
            }
            p.glow(c.0, c.1 + 30, 30, RGB(0.9, 0.6, 1, 0.35)); pore(c.0 + 4, c.1 + 42, 4)
            p.fill(p.ellipsePath(c.0, c.1 + 1, 30, 4.5), tc.alpha(0.85))
        case .tower:
            p.ball(c.0, c.1 + 6, 20, 10, chit)
            p.shape([(c.0 - 16, c.1 + 6), (c.0 - 3, c.1 + 104), (c.0 + 16, c.1 + 6)], RGB(0.52, 0.32, 0.52))
            p.shape([(c.0 + 2, c.1 + 6), (c.0 - 3, c.1 + 104), (c.0 + 16, c.1 + 6)], RGB(0.36, 0.20, 0.38))
            for (dx, dy) in [(-11, 30), (9, 48), (-7, 66), (11, 22), (5, 82)] as [(CGFloat, CGFloat)] { spike(c.0 + dx, c.1 + dy, 14, 3.4, dx > 0 ? 0.9 : -0.4) }
            pore(c.0 - 2, c.1 + 90, 3.5)
            p.fill(p.ellipsePath(c.0, c.1 + 2, 16, 3.5), tc.alpha(0.85))
        case .forward:
            for a in 0..<6 {
                let t = CGFloat(a) / 6 * .pi * 2
                p.capsule((c.0, c.1 + 10), (c.0 + cos(t) * 36, c.1 + sin(t) * 16), 4.5 * 0.6, 4.5 * 0.42, chit.dark(0.1))
            }
            p.capsule((c.0, c.1 + 6), (c.0 + 2, c.1 + 50), 6 * 0.6, 6 * 0.42, chit)
            p.ball(c.0 + 2, c.1 + 66, 15, 20, flesh)
            p.glow(c.0 + 2, c.1 + 68, 24, bio.alpha(0.55)); pore(c.0 + 2, c.1 + 68, 5)
            p.fill(p.ellipsePath(c.0, c.1 + 6, 18, 4), tc.alpha(0.85))
        }
    }
}
