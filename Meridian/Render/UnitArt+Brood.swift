import CoreGraphics

/// The Verdant Brood: living weapons. Glossy chitin over soft flesh, segmented carapace plates, bone spines,
/// bioluminescent spots and translucent membranes; insect legs with three joints scuttle in alternating sets.
/// Team colour shows as a glowing marking on the carapace.
extension UnitArt {
    static let shell = RGB(0.36, 0.20, 0.40), shellHi = RGB(0.52, 0.30, 0.56), meat = RGB(0.72, 0.40, 0.48), membrane = RGB(0.72, 0.95, 0.62)

    /// Three-segment insect leg: up from the body to a high joint, then down to a pointed tip.
    static func bugLeg(_ p: Pen, hip: (CGFloat, CGFloat), reach: CGFloat, height: CGFloat, offset: CGFloat, _ c: RGB, _ w: CGFloat) {
        let a = ang(offset)
        let tipX = hip.0 + reach + sin(a) * reach * 0.45
        let tipY: CGFloat = 3.2 + max(0, cos(a)) * 1.4
        let joint: (CGFloat, CGFloat) = (hip.0 + reach * 0.55 + sin(a) * reach * 0.2, hip.1 + height)
        p.capsule(hip, joint, w * 0.55, w * 0.42, c)
        p.capsule(joint, (tipX, tipY), w * 0.42, w * 0.16, c.dark(0.1))
        p.ball(joint.0, joint.1, w * 0.45, w * 0.45, c.light(0.15), lw: 0.4, shine: 0.6)
    }

    /// Thick jointed beast leg (hind-leg bend) ending in bone claws.
    static func beastLeg(_ p: Pen, hip: (CGFloat, CGFloat), stride: CGFloat, offset: CGFloat, _ c: RGB, _ w: CGFloat) {
        let a = ang(offset)
        let fx = hip.0 + sin(a) * stride, fy: CGFloat = 3.4 + max(0, cos(a)) * 1.5
        let knee: (CGFloat, CGFloat) = ((hip.0 + fx) / 2 - w * 0.55, (hip.1 + fy) / 2 + 0.6)
        p.capsule(hip, knee, w * 0.72, w * 0.5, c)
        p.capsule(knee, (fx, fy + w * 0.35), w * 0.5, w * 0.36, c.dark(0.12))
        for k in 0..<3 {
            let dx = CGFloat(k - 1) * w * 0.32
            p.solid(p.poly([(fx + dx - w * 0.16, fy + w * 0.2), (fx + dx + w * 0.42, fy - 0.3), (fx + dx + w * 0.16, fy + w * 0.36)]), bone.dark(0.15), lw: 0.35)
        }
    }

    /// Glossy segmented carapace with spots and the team marking.
    static func carapace(_ p: Pen, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: RGB, tc: RGB, plates: Int = 3, spots: Int = 3) {
        p.ball(cx, cy, rx, ry, c, shine: 0.7)
        for k in 1..<plates {
            let x = cx - rx + 2 * rx * CGFloat(k) / CGFloat(plates)
            let h = ry * (1 - pow((x - cx) / rx, 2)).squareRoot()
            p.line((x, cy + h * 0.92), (x - 0.8, cy - h * 0.7), c.dark(0.45).alpha(0.75), 0.5)
            p.line((x + 0.4, cy + h * 0.9), (x - 0.4, cy - h * 0.6), c.light(0.35).alpha(0.4), 0.35)
        }
        let mark = p.ellipsePath(cx - rx * 0.1, cy + ry * 0.12, rx * 0.42, ry * 0.26)
        p.fill(mark, tc.alpha(0.85))
        p.glow(cx - rx * 0.1, cy + ry * 0.12, rx * 0.5, tc.alpha(0.35))
        for k in 0..<spots {
            let t = CGFloat(k) / CGFloat(max(1, spots - 1))
            p.lamp(cx - rx * 0.6 + rx * 1.1 * t, cy - ry * 0.45 + (k % 2 == 0 ? 0 : ry * 0.2), 0.45, bio)
        }
    }

    static func eye(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        p.ball(x, y, r, r * 0.85, RGB(0.06, 0.03, 0.06), lw: 0.3, shine: 0)
        p.lamp(x + r * 0.2, y + r * 0.1, r * 0.45, bio)
    }

    static func broodBase(_ id: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "a_weaver":
            for (i, x) in [12.0, 16.0, 20.0].enumerated() { bugLeg(p, hip: (CGFloat(x), 11), reach: 3.6, height: 3.8, offset: CGFloat(i % 2) * 0.5, shell.dark(0.3), 1.6) }
            p.ball(10.4, 13.4, 4.4, 3.8, membrane.dark(0.15), shine: 0.6)                                        // silk sac
            p.glow(10.4, 13.4, 4.0, bio.alpha(0.5))
            carapace(p, 18.6, 13.4, 7.6, 4.8, shellHi, tc: tc, plates: 3, spots: 2)
            for (i, x) in [14.0, 18.0, 22.0].enumerated() { bugLeg(p, hip: (CGFloat(x), 10.6), reach: 4.0, height: 4.2, offset: CGFloat(i % 2) * 0.5 + 0.5, shell.dark(0.15), 1.7) }
        case "a_glint":
            let bob = sin(ang(0)) * 1.2
            for k in 0..<4 { p.capsule((17 + CGFloat(k) * 2, 14 + bob), (15.6 + CGFloat(k) * 2.4 + sin(ang(CGFloat(k) * 0.2)) * 1.6, 5.0), 0.5, 0.2, membrane.alpha(0.7), outline: nil) }
            p.glow(20, 16 + bob, 12, bio.alpha(0.6))
            p.ball(20, 16.8 + bob, 6.2, 4.4, membrane, shine: 0.9)
            p.ball(20.6, 17.4 + bob, 3.0, 2.0, bio.light(0.3), outline: nil, shine: 0.5)
            eye(p, 24.4, 17.4 + bob, 1.0)
            p.dot(17.4, 18.6 + bob, 0.9, tc)
        case "a_mantis":
            beastLeg(p, hip: (16.6, 12.8), stride: 2.4, offset: 0.5, shell.dark(0.3), 2.4)
            carapace(p, 15.6, 14.6, 5.8, 4.2, shell, tc: tc, plates: 3, spots: 2)                               // abdomen
            beastLeg(p, hip: (18.6, 12.4), stride: 2.4, offset: 0, shell.dark(0.12), 2.5)
        case "a_ravager":
            for (i, x) in [10.0, 25.0].enumerated() { beastLeg(p, hip: (CGFloat(x), 12.4), stride: 2.6, offset: CGFloat(i) * 0.5, shell.dark(0.3), 3.6) }
            carapace(p, 18.6, 15.6, 13.4, 7.2, shellHi, tc: tc, plates: 4, spots: 3)
            for k in 0..<4 {
                let x = 8.6 + CGFloat(k) * 5.0
                p.solid(p.poly([(x, 20.4), (x + 2.6, 27.4 - CGFloat(k % 2) * 1.6), (x + 4.4, 20.6)]), bone, lw: 0.5, contrast: 1.2)
            }
            for (i, x) in [12.6, 27.4].enumerated() { beastLeg(p, hip: (CGFloat(x), 11.6), stride: 2.6, offset: CGFloat(i) * 0.5 + 0.5, shell.dark(0.12), 3.8) }
        case "a_spinecaster":
            for (i, x) in [11.0, 18.0, 25.0].enumerated() { beastLeg(p, hip: (CGFloat(x), 11.0), stride: 2.2, offset: CGFloat(i % 2) * 0.5, shell.dark(0.25 - CGFloat(i) * 0.05), 2.8) }
            carapace(p, 18.6, 15.0, 11.6, 6.6, meat.dark(0.2), tc: tc, plates: 3, spots: 2)
            p.ball(30.4, 15.4, 3.8, 3.4, shell, shine: 0.6); eye(p, 32.2, 16.2, 0.9)
        case "a_needleback":
            for (i, x) in [10.0, 16.0, 23.0, 28.0].enumerated() { beastLeg(p, hip: (CGFloat(x), 10.6), stride: 2.0, offset: CGFloat(i % 2) * 0.5, shell.dark(0.28 - CGFloat(i) * 0.05), 2.6) }
            carapace(p, 19.6, 14.4, 12.4, 7.4, shellHi, tc: tc, plates: 4, spots: 3)
            p.ball(31.6, 13.4, 3.4, 3.0, shell, shine: 0.6); eye(p, 33.2, 14.0, 0.8)
        case "a_lifebinder":
            let bob = sin(ang(0)) * 1.2
            for i in 0..<6 { let x = 11.4 + CGFloat(i) * 3.4; p.capsule((x, 14 + bob), (x + sin(ang(CGFloat(i) * 0.17)) * 2.4, 2.4), 0.8, 0.25, meat.light(0.25), lw: 0.5) }
            p.glow(20, 20 + bob, 17, bio.alpha(0.45))
            p.ball(20, 20.4 + bob, 11.2, 8.6, membrane.alpha(0.92), shine: 0.9)
            p.ball(20, 21.4 + bob, 6.0, 4.4, bio.light(0.35), outline: nil, shine: 0.4)
            p.fill(p.ellipsePath(20, 15.6 + bob, 6.4, 1.8), tc.alpha(0.85))
        case "a_shadeling":
            let sway = sin(ang(0)) * 1.4
            p.glow(20, 15, 15, RGB(0.45, 0.12, 0.55, 0.55))
            let cloak = p.poly([(8 + sway, 4), (13.6, 21.6), (20, 30.6), (26.4, 21.6), (32 + sway, 4), (26, 9.4), (20, 6.4), (14, 9.4)])
            p.solid(cloak, RGB(0.18, 0.09, 0.24), contrast: 1.3)
            p.solid(p.poly([(25.6, 20.4), (38.4, 25.4 + sway), (30.4, 16.2)]), bone.dark(0.35), lw: 0.5)
            p.solid(p.poly([(14.4, 20.4), (1.6, 25.4 - sway), (9.6, 16.2)]), bone.dark(0.35), lw: 0.5)
            p.lamp(17.4, 24.0, 0.8, RGB(0.95, 0.35, 1)); p.lamp(22.6, 24.0, 0.8, RGB(0.95, 0.35, 1))
            p.line((15.4, 14.0), (24.6, 14.0), tc, 1.0)
        case "a_skitter":
            for (i, x) in [13.0, 17.0, 21.0].enumerated() { bugLeg(p, hip: (CGFloat(x), 10.6), reach: 3.6, height: 3.6, offset: CGFloat(i % 2) * 0.5, shell.dark(0.3), 1.5) }
            carapace(p, 18.4, 13.4, 7.8, 4.6, shellHi.light(0.1), tc: tc, plates: 3, spots: 2)
            for (i, x) in [15.0, 19.0, 23.0].enumerated() { bugLeg(p, hip: (CGFloat(x), 10.2), reach: 3.8, height: 3.8, offset: CGFloat(i % 2) * 0.5 + 0.5, shell.dark(0.12), 1.6) }
        case "a_colossus":
            for (i, x) in [8.0, 25.0].enumerated() { beastLeg(p, hip: (CGFloat(x), 13.0), stride: 2.4, offset: CGFloat(i) * 0.5, shell.dark(0.35), 5.4) }
            carapace(p, 18.0, 19.6, 15.6, 11.0, shell.light(0.04), tc: tc, plates: 5, spots: 4)
            for k in 0..<5 {
                let x = 5.4 + CGFloat(k) * 5.2
                p.solid(p.poly([(x, 27.0 - CGFloat(abs(k - 2)) * 1.4), (x + 2.6, 36.4 - CGFloat(abs(k - 2)) * 2.0), (x + 5.0, 27.4 - CGFloat(abs(k - 2)) * 1.4)]), bone.dark(0.05), lw: 0.5, contrast: 1.2)
            }
            for (i, x) in [12.4, 28.4].enumerated() { beastLeg(p, hip: (CGFloat(x), 12.4), stride: 2.4, offset: CGFloat(i) * 0.5 + 0.5, shell.dark(0.15), 5.6) }
        case "a_rupturer":
            for (i, x) in [9.0, 16.0, 23.0, 29.0].enumerated() { beastLeg(p, hip: (CGFloat(x), 11.0), stride: 2.0, offset: CGFloat(i % 2) * 0.5, shell.dark(0.28 - CGFloat(i) * 0.05), 3.0) }
            carapace(p, 17.6, 17.6, 13.4, 9.6, meat.dark(0.15), tc: tc, plates: 3, spots: 2)
            let pulse = 0.5 + 0.12 * sin(ang(0))
            p.ball(15.6, 20.0, 8.6 + sin(ang(0)) * 0.3, 6.6, RGB(0.55, 0.85, 0.28, 0.95), shine: 0.9)
            p.glow(15.6, 20.0, 9.4, bio.alpha(pulse))
        case "a_seeder":
            beastLeg(p, hip: (18.0, 11.4), stride: 2.0, offset: 0.5, shell.dark(0.3), 2.4)
            p.ball(20, 14.2, 6.6, 5.4, meat.dark(0.2), shine: 0.5)
            p.fill(p.ellipsePath(20, 13.2, 3.6, 1.8), tc.alpha(0.85))
            beastLeg(p, hip: (21.8, 11.4), stride: 2.0, offset: 0, shell.dark(0.12), 2.4)
        case "a_wisp":
            let f = sin(ang(0)) * 3.2
            p.solid(p.poly([(20, 20.6), (5.6, 34.4 - f), (1.6, 23.0)]), membrane.alpha(0.55), outline: membrane.dark(0.3).alpha(0.8), contrast: 0.5)
            p.solid(p.poly([(20, 19.6), (6.0, 6.0 + f), (1.8, 17.6)]), membrane.alpha(0.7), outline: membrane.dark(0.3).alpha(0.8), contrast: 0.5)
            p.glow(20, 20, 12, bio.alpha(0.5))
            p.capsule((12.0, 20.2), (28.6, 20.6), 1.6, 2.4, shellHi.light(0.15))
            eye(p, 28.0, 21.2, 0.9)
            p.dot(17.6, 21.6, 0.8, tc)
        case "a_blightwing":
            let f = sin(ang(0)) * 3.0
            let wing = p.poly([(1.6, 24.4 + f), (13.4, 20.6), (20, 36.4 - f * 0.5), (26.6, 20.6), (38.4, 24.4 + f), (31.0, 15.6), (20, 11.6), (9.0, 15.6)])
            p.solid(wing, shell.light(0.08), contrast: 1.2)
            p.line((9.0, 15.8), (2.4, 23.6 + f), shell.dark(0.4), 0.5); p.line((31.0, 15.8), (37.6, 23.6 + f), shell.dark(0.4), 0.5)
            carapace(p, 20, 19.2, 6.4, 5.0, meat.dark(0.2), tc: tc, plates: 2, spots: 1)
            p.glow(20, 14.6, 7, bio.alpha(0.6))
        case "a_sporewing":
            for i in 0..<6 { let x = 10.4 + CGFloat(i) * 3.8; p.capsule((x, 16), (x + sin(ang(CGFloat(i) * 0.15)) * 2.2, 3.4), 0.7, 0.25, meat, lw: 0.5) }
            p.ball(20, 24.2, 15.4, 11.0, RGB(0.58, 0.38, 0.6), shine: 0.8)
            for (x, y) in [(13, 27), (20, 30.4), (27, 26), (17, 21), (25, 20)] as [(CGFloat, CGFloat)] { p.lamp(x, y, 0.9, bio) }
            p.fill(p.ellipsePath(20, 16.2, 9.6, 2.4), tc.alpha(0.8))
        default: return false
        }
        return true
    }

    static func broodUpper(_ id: String, _ v: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "a_weaver":
            p.ball(28.4, 14.8, 4.0, 3.4, shell, shine: 0.7)
            eye(p, 30.0, 16.0, 0.9)
            p.capsule((31.0, 13.6), (34.4, 12.2), 0.6, 0.2, bone); p.capsule((31.0, 15.2), (34.4, 16.6), 0.6, 0.2, bone)
            if v != "" { p.glow(34.0, 14.4, 3.2, bio.alpha(0.55)) }
        case "a_mantis":
            p.ball(21.0, 23.6, 3.6, 5.6, shell.light(0.06), shine: 0.6)                                          // thorax
            p.capsule((21.6, 26.6), (24.4, 30.4), 1.6, 1.2, shell)
            p.ball(25.6, 31.4, 3.0, 2.6, shellHi, shine: 0.7); eye(p, 27.0, 32.0, 0.8)
            p.capsule((22.6, 26.0), (31.4, 24.0), 1.0, 0.8, shell.dark(0.1))                                    // forearm
            let blade = p.poly([(30.6, 25.0), (35.6, 32.4), (34.0, 19.6), (31.6, 23.2)])
            p.solid(blade, bone, contrast: 1.4); p.line((31.8, 24.2), (34.8, 31.0), RGB(1, 1, 1, 0.6), 0.4)
            p.fill(p.ellipsePath(20.6, 21.6, 2.0, 2.2), tc.alpha(0.85))
        case "a_ravager":
            p.ball(31.6, 14.6, 5.4, 4.8, shell, shine: 0.6)
            p.solid(p.poly([(33.6, 11.2), (40.4, 7.0), (38.4, 14.6)]), bone, lw: 0.5, contrast: 1.3)              // horn
            p.solid(p.poly([(34.0, 17.4), (39.4, 15.4), (36.6, 19.6)]), bone.dark(0.1), lw: 0.5)                  // tusk
            eye(p, 34.4, 16.0, 1.0)
        case "a_spinecaster":
            for i in 0..<6 {
                let x = 9.6 + CGFloat(i) * 3.2
                p.capsule((x, 19.0), (x + 9.0, 30.6), 0.7, 0.2, bone.mix(bio, CGFloat(i % 2) * 0.15))
            }
        case "a_needleback":
            for i in 0..<8 {
                let x = 8.6 + CGFloat(i) * 3.2
                p.capsule((x, 19.6), (x + 2.6, 35.0), 0.55, 0.15, bone.mix(bio, 0.3))
                p.lamp(x + 2.6, 35.0, 0.25, bio)
            }
        case "a_skitter":
            p.ball(27.6, 13.6, 3.8, 3.2, shell, shine: 0.7)
            eye(p, 29.4, 14.6, 0.9)
            p.capsule((30.6, 12.4), (34.4, 11.0), 0.55, 0.2, bone); p.capsule((30.6, 14.2), (34.4, 15.0), 0.55, 0.2, bone)
        case "a_colossus":
            p.ball(33.4, 17.0, 6.6, 6.0, shell.dark(0.08), shine: 0.6)
            p.solid(p.poly([(35.6, 12.0), (41.0, 3.2), (40.6, 13.8)]), bone, lw: 0.5, contrast: 1.3)
            p.solid(p.poly([(37.0, 14.2), (41.6, 10.6), (39.6, 15.6)]), bone.dark(0.1), lw: 0.5)
            eye(p, 36.8, 18.6, 1.2)
        case "a_rupturer":
            p.capsule((24.0, 21.0), (36.8, 31.0), 2.4, 1.6, shell)
            p.ball(37.4, 31.4, 2.2, 2.0, meat, shine: 0.6)
            p.lamp(37.6, 31.6, 0.9, bio)
        case "a_seeder":
            let cap = p.poly([(5.6, 22.0), (12.0, 30.0), (20, 34.6), (28.0, 30.0), (34.4, 22.0), (20, 18.4)])
            p.solid(cap, RGB(0.55, 0.30, 0.56), contrast: 1.3)
            p.solid(p.poly([(5.6, 22.0), (20, 18.4), (34.4, 22.0), (20, 20.6)]), RGB(0.82, 0.62, 0.7), lw: 0.4)     // gills
            for i in 0..<5 { p.lamp(9.6 + CGFloat(i) * 5.2, 24.6 + CGFloat(i % 2) * 3.4, 0.7, bio) }
        default: return false
        }
        return true
    }
}
