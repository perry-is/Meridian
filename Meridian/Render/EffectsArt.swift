import CoreGraphics
import Foundation

/// Procedurally generated combat effect textures: fireball flipbooks, spark bursts, lightning, slashes,
/// splats, debris and decals. All white/neutral where they are tinted at runtime.
enum EffectsArt {

    /// 8-frame fireball: white-hot core expanding through orange into drifting smoke.
    static func explosionFrames() -> [CGImage] {
        (0..<8).map { i in
            let t = CGFloat(i) / 7
            return Pen.image(96, 96) { p in
                let r = 12 + 30 * (1 - pow(1 - t, 2.2))
                let fire = t < 0.55
                // Smoke body.
                for k in 0..<9 {
                    let a = CGFloat(k) / 9 * .pi * 2 + 0.4
                    let d = r * (0.45 + hnoise(k, 1, 2) * 0.35)
                    let rr = r * (0.38 + hnoise(k, 2, 3) * 0.25)
                    let col = RGB(0.24, 0.20, 0.22, max(0, 0.75 - t * 0.7))
                    p.fill(p.ellipsePath(48 + cos(a) * d, 46 + sin(a) * d * 0.8 + t * 10, rr, rr * 0.9), col)
                }
                if fire {
                    let f = 1 - t / 0.55
                    p.glow(48, 46, r * 1.25, RGB(1.0, 0.55, 0.15, 0.9 * f))
                    for k in 0..<7 {
                        let a = CGFloat(k) / 7 * .pi * 2
                        let d = r * 0.35 * hnoise(k, 4, 5)
                        p.fill(p.ellipsePath(48 + cos(a) * d, 46 + sin(a) * d, r * 0.42, r * 0.38), RGB(1.0, 0.62 + 0.2 * f, 0.2, 0.85 * f))
                    }
                    p.glow(48, 46, r * 0.7, RGB(1.0, 0.95, 0.75, f))
                }
            }
        }
    }

    /// 4-frame spark burst (white, tinted per weapon style).
    static func sparkFrames() -> [CGImage] {
        (0..<4).map { i in
            let t = CGFloat(i) / 3
            return Pen.image(40, 40) { p in
                p.glow(20, 20, 12 * (1 - t * 0.6), RGB(1, 1, 1, 1 - t * 0.7))
                for k in 0..<8 {
                    let a = CGFloat(k) / 8 * .pi * 2 + hnoise(k, 7, 1)
                    let r0 = 3 + t * 9, r1 = 7 + t * 12 + hnoise(k, 7, 2) * 5
                    p.line((20 + cos(a) * r0, 20 + sin(a) * r0), (20 + cos(a) * r1, 20 + sin(a) * r1), RGB(1, 1, 1, 1 - t * 0.8), 1.6 - t * 0.8)
                }
            }
        }
    }

    /// Jagged lightning bolt along +x (stretched between endpoints at runtime).
    static func lightning(_ v: Int) -> CGImage {
        Pen.image(128, 24) { p in
            var pts: [(CGFloat, CGFloat)] = [(0, 12)]
            for k in 1..<9 { pts.append((CGFloat(k) * 16, 12 + (hnoise(k, v, 9) - 0.5) * 18)) }
            pts.append((128, 12))
            for (w, a) in [(6.0, 0.25), (3.0, 0.6), (1.4, 1.0)] as [(CGFloat, CGFloat)] {
                let path = CGMutablePath(); path.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
                for q in pts.dropFirst() { path.addLine(to: CGPoint(x: q.0, y: q.1)) }
                p.stroke(path, RGB(1, 1, 1, a), w)
            }
            // A side fork.
            let f = pts[4]
            p.line(f, (f.0 + 14, f.1 + 9 * (v % 2 == 0 ? 1 : -1)), RGB(1, 1, 1, 0.7), 1.2)
        }
    }

    /// Crescent slash for melee strikes.
    static func slash() -> CGImage {
        Pen.image(48, 48) { p in
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: 24, y: 18), radius: 18, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            p.stroke(path, RGB(1, 1, 1, 0.35), 6)
            p.stroke(path, RGB(1, 1, 1, 0.95), 2)
        }
    }

    /// Ichor / oil / scorch splat decal.
    static func splat(_ v: Int) -> CGImage {
        Pen.image(64, 32) { p in
            for k in 0..<9 {
                let x = 32 + (hnoise(k, v, 11) - 0.5) * 36, y = 16 + (hnoise(k, v, 12) - 0.5) * 16
                let r = 4 + hnoise(k, v, 13) * 8
                p.fill(p.ellipsePath(x, y, r, r * 0.55), RGB(1, 1, 1, 0.75))
            }
        }
    }

    static func shard(_ v: Int) -> CGImage {
        Pen.image(14, 14) { p in
            let pts: [(CGFloat, CGFloat)] = v == 0 ? [(2, 3), (11, 2), (8, 11)] : [(3, 2), (12, 6), (6, 12), (2, 8)]
            p.shade(p.poly(pts), RGB(0.55, 0.55, 0.58), outline: RGB(0.1, 0.1, 0.1, 0.9), lw: 0.8)
        }
    }

    static func rubble() -> CGImage {
        Pen.image(128, 64) { p in
            p.fill(p.ellipsePath(64, 32, 56, 26), RGB(0.10, 0.08, 0.08, 0.55))
            for k in 0..<16 {
                let x = 64 + (hnoise(k, 3, 1) - 0.5) * 90, y = 32 + (hnoise(k, 3, 2) - 0.5) * 36
                let r = 3 + hnoise(k, 3, 3) * 7
                p.shade(p.poly([(x - r, y - r * 0.4), (x - r * 0.2, y + r * 0.7), (x + r, y + r * 0.2), (x + r * 0.3, y - r * 0.6)]), RGB(0.38, 0.35, 0.34), outline: RGB(0.05, 0.05, 0.05, 0.8), lw: 0.8)
            }
            for k in 0..<4 { p.glow(40 + CGFloat(k) * 16, 30 + hnoise(k, 5, 1) * 8, 6, RGB(1, 0.45, 0.1, 0.5)) }
        }
    }

    static func shockwave() -> CGImage {
        Pen.image(128, 64) { p in
            p.stroke(p.ellipsePath(64, 32, 58, 27), RGB(1, 1, 1, 0.25), 8)
            p.stroke(p.ellipsePath(64, 32, 58, 27), RGB(1, 1, 1, 0.9), 2.5)
        }
    }

    /// Class markers drawn under units (tinted with team colour at runtime).
    static func classRing(_ kind: String) -> CGImage {
        Pen.image(64, 32) { p in
            switch kind {
            case "heavy":
                p.fill(p.ellipsePath(32, 16, 28, 13), RGB(1, 1, 1, 0.22))
                p.stroke(p.ellipsePath(32, 16, 28.5, 13.5), RGB(1, 1, 1, 0.95), 2.6)
                p.stroke(p.ellipsePath(32, 16, 23, 10.5), RGB(1, 1, 1, 0.8), 1.6)
            case "siege":
                p.fill(p.ellipsePath(32, 16, 27, 12.5), RGB(1, 1, 1, 0.18))
                p.stroke(p.ellipsePath(32, 16, 27, 12.5), RGB(1, 1, 1, 0.95), 2.2)
                for (a, b) in [((2.0, 16.0), (9.0, 16.0)), ((55.0, 16.0), (62.0, 16.0)), ((32.0, 1.5), (32.0, 6.0)), ((32.0, 26.0), (32.0, 30.5))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                    p.line(a, b, RGB(1, 1, 1, 1), 2.4)
                }
            case "air":
                for k in 0..<12 where k % 2 == 0 {
                    var pts: [(CGFloat, CGFloat)] = []
                    let a0 = CGFloat(k) / 12 * .pi * 2, a1 = CGFloat(k + 1) / 12 * .pi * 2
                    for s in 0...6 { let a = a0 + (a1 - a0) * CGFloat(s) / 6; pts.append((32 + cos(a) * 27, 16 + sin(a) * 12.5)) }
                    let pp = CGMutablePath(); pp.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { pp.addLine(to: CGPoint(x: q.0, y: q.1)) }
                    p.stroke(pp, RGB(1, 1, 1, 0.95), 2.2)
                }
            case "support":
                // Support: ring with four plus-ticks.
                p.fill(p.ellipsePath(32, 16, 24, 11), RGB(1, 1, 1, 0.16))
                p.stroke(p.ellipsePath(32, 16, 24, 11), RGB(1, 1, 1, 0.9), 2)
                for (x, y) in [(8.0, 16.0), (56.0, 16.0), (32.0, 4.5), (32.0, 27.5)] as [(CGFloat, CGFloat)] {
                    p.line((x - 3.2, y), (x + 3.2, y), RGB(1, 1, 1, 1), 2); p.line((x, y - 3.2), (x, y + 3.2), RGB(1, 1, 1, 1), 2)
                }
            case "worker":
                // Workers: a slim, dashed ring that reads quieter than combat units'.
                for k in 0..<10 where k % 2 == 0 {
                    let a0 = CGFloat(k) / 10 * .pi * 2, a1 = CGFloat(k + 1) / 10 * .pi * 2
                    let pp = CGMutablePath()
                    for st in 0...6 {
                        let a = a0 + (a1 - a0) * CGFloat(st) / 6
                        let q = CGPoint(x: 32 + cos(a) * 22, y: 16 + sin(a) * 10)
                        if st == 0 { pp.move(to: q) } else { pp.addLine(to: q) }
                    }
                    p.stroke(pp, RGB(1, 1, 1, 0.9), 1.8)
                }
            case "marker":
                p.fill(p.ellipsePath(32, 16, 29, 13.5), RGB(1, 1, 1, 0.18))
                p.stroke(p.ellipsePath(32, 16, 29, 13.5), RGB(1, 1, 1, 0.9), 2)
                p.stroke(p.ellipsePath(32, 16, 15, 7), RGB(1, 1, 1, 0.7), 1.4)
                p.line((32, 9), (32, 23), RGB(1, 1, 1, 0.9), 1.4); p.line((22, 16), (42, 16), RGB(1, 1, 1, 0.9), 1.4)
            default: // field dome edge
                p.fill(p.ellipsePath(32, 16, 30, 14), RGB(1, 1, 1, 0.07))
                p.stroke(p.ellipsePath(32, 16, 30, 14), RGB(1, 1, 1, 0.55), 1.2)
            }
        }
    }

    static func selectRing() -> CGImage {
        Pen.image(80, 40) { p in
            for k in 0..<8 where k % 2 == 0 {
                let a0 = CGFloat(k) / 8 * .pi * 2, a1 = CGFloat(k + 1) / 8 * .pi * 2
                var pts: [(CGFloat, CGFloat)] = []
                for s in 0...10 { let a = a0 + (a1 - a0) * CGFloat(s) / 10; pts.append((40 + cos(a) * 36, 20 + sin(a) * 17)) }
                let pp = CGMutablePath(); pp.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { pp.addLine(to: CGPoint(x: q.0, y: q.1)) }
                p.stroke(pp, RGB(1, 1, 1, 1), 3)
            }
            p.stroke(p.ellipsePath(40, 20, 31, 14.5), RGB(1, 1, 1, 0.35), 1.2)
        }
    }

    // MARK: Living battlefield (Mission 5)

    /// Headlight beam pointing right, soft at the edges.
    static func cone() -> CGImage {
        Pen.image(96, 48) { p in
            for k in 0..<10 {
                let t = CGFloat(k) / 10
                let spread = 6 + 18 * (1 - t)
                p.fill(p.poly([(4, 24 - 2), (96 - t * 30, 24 - spread), (96 - t * 30, 24 + spread), (4, 24 + 2)]), RGB(1, 1, 1, 0.07))
            }
            p.glow(8, 24, 6, RGB(1, 1, 1, 0.8))
        }
    }

    /// Artillery crater: dark bowl, thrown-up rim.
    static func crater() -> CGImage {
        Pen.image(96, 48) { p in
            p.fill(p.ellipsePath(48, 24, 44, 21), RGB(0.05, 0.04, 0.04, 0.35))
            p.stroke(p.ellipsePath(48, 25, 30, 14), RGB(0.55, 0.45, 0.35, 0.55), 5)
            p.fill(p.ellipsePath(48, 24, 26, 12), RGB(0.06, 0.05, 0.05, 0.75))
            p.fill(p.ellipsePath(46, 23, 15, 7), RGB(0.02, 0.02, 0.02, 0.6))
            for k in 0..<9 {
                let a = CGFloat(k) / 9 * .pi * 2 + hnoise(k, 1, 4)
                let r0: CGFloat = 30, r1 = 36 + hnoise(k, 2, 4) * 8
                p.line((48 + cos(a) * r0, 24 + sin(a) * r0 * 0.47), (48 + cos(a) * r1, 24 + sin(a) * r1 * 0.47), RGB(0.08, 0.06, 0.05, 0.6), 2.5)
            }
        }
    }

    /// A short stretch of tread marks (two parallel bands), running left to right.
    static func track() -> CGImage {
        Pen.image(32, 16) { p in
            for y in [CGFloat(4), 12] {
                for k in 0..<6 { p.fill(p.roundRectPath(CGFloat(k) * 5 + 1, y - 2, 3.4, 4, 1), RGB(0, 0, 0, 0.55)) }
            }
        }
    }

    /// Distant flyer silhouette, wings up / down. Drawn white; tinted per biome at runtime.
    static func bird(_ frame: Int) -> CGImage {
        Pen.image(24, 14) { p in
            let up: CGFloat = frame == 0 ? 1 : -0.5
            for side in [-1.0, 1.0] as [CGFloat] {
                let wing = CGMutablePath()
                wing.move(to: CGPoint(x: 12, y: 7.5))
                wing.addQuadCurve(to: CGPoint(x: 12 + side * 11, y: 7 + 4.5 * up), control: CGPoint(x: 12 + side * 5, y: 7 + 3.5 * up + 1.5))
                wing.addQuadCurve(to: CGPoint(x: 12, y: 6), control: CGPoint(x: 12 + side * 5, y: 6 + 1.5 * up))
                wing.closeSubpath()
                p.fill(wing, RGB(1, 1, 1, 1))
            }
            p.fill(p.ellipsePath(12, 6.8, 2.2, 1.4), RGB(1, 1, 1, 1))
        }
    }

    /// Radar dish on a short mast (mast base at the bottom centre). Turned at runtime by squashing x.
    static func radarDish() -> CGImage {
        Pen.image(28, 30) { p in
            p.limb((14, 2), (14, 13), RGB(0.3, 0.3, 0.32), 2)
            p.shade(p.ellipsePath(14, 18, 11, 7), RGB(0.86, 0.87, 0.85), outline: RGB(0.05, 0.04, 0.07, 0.9))
            p.fill(p.ellipsePath(15, 18.5, 6.5, 4), RGB(0.62, 0.64, 0.66))
            p.limb((15, 18.5), (18, 24), RGB(0.3, 0.3, 0.32), 1.2)
            p.dot(18, 24, 1.6, RGB(1, 0.35, 0.25))
        }
    }

    /// Swallow-tail flag drawn upright (pole edge at the bottom); rotated to fly sideways at runtime.
    static func flag() -> CGImage {
        Pen.image(16, 26) { p in
            p.fill(p.poly([(1, 0), (15, 0), (15, 25), (8, 19), (1, 25)]), RGB(1, 1, 1))
            p.line((1, 3), (15, 3), RGB(0.7, 0.7, 0.7), 1)
        }
    }

    /// Small field critter (side view, facing right), two hop frames. Tinted per biome at runtime.
    static func critter(_ frame: Int) -> CGImage {
        Pen.image(18, 14) { p in
            let lift: CGFloat = frame == 0 ? 0 : 2
            p.fill(p.ellipsePath(9, 2, 6, 1.5), RGB(0, 0, 0, 0.25))
            p.shade(p.ellipsePath(8, 6 + lift, 6, 3.6), RGB(0.85, 0.85, 0.85), outline: RGB(0.08, 0.07, 0.07, 0.85), lw: 0.8)
            p.shade(p.ellipsePath(13.5, 8.5 + lift, 3, 2.6), RGB(0.9, 0.9, 0.9), outline: RGB(0.08, 0.07, 0.07, 0.85), lw: 0.8)
            p.limb((13, 10.5 + lift), (12, 13.5 + lift), RGB(0.8, 0.8, 0.8), 1.4)
            p.dot(14.6, 9 + lift, 0.8, RGB(0.05, 0.05, 0.05))
            if frame == 1 { p.limb((4, 5), (2, 2), RGB(0.7, 0.7, 0.7), 1.2) }
        }
    }

    /// A large gliding sky-ray (highlands), seen from below.
    static func skyray() -> CGImage {
        Pen.image(40, 22) { p in
            p.fill(p.poly([(2, 12), (16, 15), (20, 20), (24, 15), (38, 12), (24, 8), (20, 1), (16, 8)]), RGB(0.12, 0.08, 0.12, 0.92))
            p.line((20, 1), (20, -2), RGB(0.12, 0.08, 0.12, 0.8), 1)
        }
    }
}
