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
}
