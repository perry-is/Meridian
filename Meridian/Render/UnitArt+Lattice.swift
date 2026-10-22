import CoreGraphics

/// The Lattice: machine intelligence. Gunmetal and polished chrome, faceted hex armour, cyan energy cores
/// and seams; walkers stride on digitigrade legs with pistons, drones float on thruster light.
/// Team colour sits on chest plates and armour bands.
extension UnitArt {
    static let lmetal = RGB(0.24, 0.26, 0.31), lplate = RGB(0.36, 0.39, 0.46)

    /// Digitigrade machine leg: thigh forward to the knee, shin back to the ankle, a clawed foot; with a piston.
    static func mechLeg(_ p: Pen, hip: (CGFloat, CGFloat), len: CGFloat, stride: CGFloat, offset: CGFloat, _ c: RGB, _ w: CGFloat) {
        let a = ang(offset)
        let fx = hip.0 + sin(a) * stride, fy = hip.1 - len + max(0, cos(a)) * len * 0.16
        let knee: (CGFloat, CGFloat) = (hip.0 + len * 0.18 + sin(a) * stride * 0.4, hip.1 - len * 0.42)
        let ankle: (CGFloat, CGFloat) = (fx - len * 0.12, fy + len * 0.22)
        p.capsule(hip, knee, w * 0.62, w * 0.5, c)
        p.capsule(knee, ankle, w * 0.48, w * 0.38, c.dark(0.08))
        p.capsule(ankle, (fx, fy + w * 0.2), w * 0.36, w * 0.3, c.dark(0.12))
        p.limb((hip.0 - w * 0.3, hip.1 - w * 0.4), (ankle.0 - w * 0.2, ankle.1 + w * 0.3), chrome.dark(0.15), max(0.4, w * 0.18))   // piston
        p.ball(knee.0, knee.1, w * 0.5, w * 0.5, chrome.dark(0.2), lw: 0.5, shine: 0.6)
        p.solid(p.poly([(fx - w * 0.9, fy - 0.2), (fx + w * 1.3, fy - 0.2), (fx + w * 0.7, fy + w * 0.55), (fx - w * 0.6, fy + w * 0.55)]), c.dark(0.25), lw: 0.5)
    }

    /// Faceted hex armour block (front face plus top facet), with a glowing seam.
    static func hexHull(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RGB, tc: RGB? = nil, seam: Bool = true) {
        let cut = min(w, h) * 0.28
        let front = p.poly([(x + cut, y), (x + w - cut, y), (x + w, y + h * 0.5), (x + w - cut, y + h), (x + cut, y + h), (x, y + h * 0.5)])
        p.solid(front, c, contrast: 1.2)
        p.solid(p.poly([(x + cut, y + h), (x + w - cut, y + h), (x + w - cut + cut * 0.6, y + h + cut * 0.55), (x + cut + cut * 0.6, y + h + cut * 0.55)]), c.light(0.28), contrast: 0.5)
        if let t = tc { p.solid(p.poly([(x + cut * 1.4, y + h * 0.3), (x + w - cut * 1.4, y + h * 0.3), (x + w - cut * 1.1, y + h * 0.55), (x + cut * 1.1, y + h * 0.55)]), t, lw: 0.4) }
        if seam {
            p.line((x + cut * 0.6, y + h * 0.78), (x + w - cut * 0.6, y + h * 0.78), cyan.alpha(0.9), 0.5)
            p.glow(x + w * 0.5, y + h * 0.78, w * 0.3, cyan.alpha(0.25))
        }
    }

    static func core(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        p.ball(x, y, r * 1.35, r * 1.35, chrome.dark(0.25), lw: 0.5, shine: 0.3)
        p.lamp(x, y, r, cyan)
    }

    static func thruster(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        let flick: CGFloat = 0.75 + 0.25 * sin(ang(0) * 2)
        p.glow(x, y - r * 0.6, r * 3.2, cyan.alpha(0.45 * flick))
        p.fill(p.ellipsePath(x, y, r * 1.2, r * 0.5), cyan.light(0.4).alpha(0.9))
    }

    static func latticeBase(_ id: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "m_fabricator":
            thruster(p, 20, 6.6, 2.4)
            p.solid(p.ellipsePath(20, 13.2, 9.6, 3.6), lmetal.dark(0.2), contrast: 0.6)
            hexHull(p, 11.0, 11.6, 18.0, 6.6, lplate, tc: tc)
            p.ball(20, 19.6, 5.2, 3.4, chrome.dark(0.1), shine: 0.7)
            p.lamp(22.4, 19.8, 1.0, cyan)
        case "m_recon":
            let spin = CGFloat(phase) * .pi / 4
            for x in [7.0, 33.0] as [CGFloat] {
                p.fill(p.ellipsePath(x, 22.4, 6.2, 1.5), RGB(0.8, 0.9, 1, 0.16))
                p.line((x - cos(spin) * 6, 22.4 - sin(spin) * 1.4), (x + cos(spin) * 6, 22.4 + sin(spin) * 1.4), RGB(0.2, 0.22, 0.26, 0.8), 0.8)
                p.ball(x, 22.4, 1.2, 0.8, chrome, lw: 0.4)
            }
            p.limb((8, 21.6), (32, 21.6), lmetal, 0.9)
            p.solid(p.ellipsePath(20, 20.4, 9.4, 3.8), lplate, contrast: 1.2)
            p.ball(21, 22.0, 4.0, 2.6, chrome, shine: 0.7)
            p.lamp(22.4, 21.4, 1.2, cyan)
            p.line((12, 19.4), (28, 19.4), tc, 1.1)
        case "m_arc":
            mechLeg(p, hip: (18.2, 15.2), len: 12, stride: 2.6, offset: 0.5, lmetal.dark(0.15), 3.0)
            hexHull(p, 12.6, 14.4, 15.6, 9.6, lplate, tc: tc)
            mechLeg(p, hip: (22.2, 15.2), len: 12, stride: 2.6, offset: 0, lmetal, 3.0)
        case "m_shockframe":
            mechLeg(p, hip: (16.4, 13.6), len: 11, stride: 2.8, offset: 0.5, lmetal.dark(0.15), 4.0)
            hexHull(p, 8.4, 12.8, 23.2, 13.4, lmetal.light(0.1), tc: tc)
            p.block(14.2, 26.0, 11.6, 2.6, depth: 1.6, lplate)
            p.lamp(20.0, 27.6, 0.8, cyan)
            mechLeg(p, hip: (23.6, 13.6), len: 11, stride: 2.8, offset: 0, lmetal, 4.0)
        case "m_piercer":
            for (i, x) in [8.0, 14.0, 25.0, 31.0].enumerated() { mechLeg(p, hip: (CGFloat(x), 11.8), len: 9, stride: 2.0, offset: CGFloat(i % 2) * 0.5, lmetal.dark(i < 2 ? 0.15 : 0), 2.2) }
            hexHull(p, 5.0, 10.4, 29.0, 7.6, lplate, tc: tc)
        case "m_flak":
            thruster(p, 13, 5.2, 1.8); thruster(p, 27, 5.2, 1.8)
            hexHull(p, 5.6, 7.0, 28.8, 8.4, lplate, tc: tc)
        case "m_repair":
            for (x, y) in [(5.0, 24.0), (35.0, 24.0)] as [(CGFloat, CGFloat)] {
                p.capsule((20, 20), (x, y), 1.1, 0.8, lmetal)
                p.ball(x, y, 2.4, 2.0, chrome.dark(0.15)); p.lamp(x, y - 1.6, 0.6, RGB(0.4, 1, 0.55))
            }
            p.ball(20, 20, 7.0, 5.0, chrome, shine: 0.8)
            p.solid(p.roundRectPath(18.6, 16.6, 2.8, 7.0, 0.4), RGB(0.3, 1, 0.5), lw: 0.4); p.solid(p.roundRectPath(16.6, 18.6, 6.8, 2.8, 0.4), RGB(0.3, 1, 0.5), lw: 0.4)
            p.line((14, 15.4), (26, 15.4), tc, 1.2)
            thruster(p, 20, 13.6, 1.6)
        case "m_jammer":
            mechLeg(p, hip: (18.4, 15.0), len: 12.4, stride: 2.2, offset: 0.5, lmetal.dark(0.15), 2.0)
            hexHull(p, 13.6, 13.2, 12.8, 9.4, lmetal.light(0.08), tc: tc, seam: false)
            p.line((15.0, 20.8), (25.0, 20.8), RGB(0.7, 0.45, 1, 0.9), 0.6)
            mechLeg(p, hip: (21.6, 15.0), len: 12.4, stride: 2.2, offset: 0, lmetal, 2.0)
        case "m_runner":
            for (x, k) in [(8.6, 0.12), (20.0, 0.06), (31.4, 0.0)] as [(CGFloat, CGFloat)] { offroadWheel(p, x, 5.8, 3.9, dim: k) }
            let hull = p.poly([(2.6, 8.0), (37.4, 8.6), (34.0, 14.2), (25.0, 16.6), (8.0, 16.4)])
            p.solid(hull, chrome.dark(0.2), contrast: 1.2)
            p.solid(p.poly([(8.0, 16.4), (25.0, 16.6), (26.4, 17.6), (9.2, 17.4)]), chrome.light(0.1), contrast: 0.4)
            p.line((6.0, 11.0), (33.0, 11.6), tc, 1.6)
            p.lamp(36.4, 10.0, 0.6, cyan)
        case "m_bulwark":
            mechLeg(p, hip: (14.0, 14.6), len: 13, stride: 2.6, offset: 0.5, lmetal.dark(0.2), 5.4)
            hexHull(p, 4.6, 13.6, 30.8, 13.4, lmetal.light(0.12), tc: tc)
            p.block(13.0, 27.0, 14.0, 4.6, depth: 2.0, chrome.dark(0.15))
            core(p, 20.0, 29.4, 1.2)
            mechLeg(p, hip: (26.0, 14.6), len: 13, stride: 2.6, offset: 0, lmetal, 5.4)
        case "m_coil":
            tankTracks(p, 3.4, 2.6, 30.8, 8.0, lmetal)
            hexHull(p, 4.6, 10.2, 27.4, 8.4, lplate, tc: tc)
        case "m_suppress":
            for (i, x) in [11.0, 20.0, 29.0].enumerated() { mechLeg(p, hip: (CGFloat(x) * 0.4 + 12, 15.6), len: 12, stride: 1.8, offset: CGFloat(i) / 3, lmetal.dark(CGFloat(2 - i) * 0.08), 1.9) }
            p.ball(20, 17.6, 7.4, 5.0, lplate)
            p.line((14.0, 17.0), (26.0, 17.0), tc, 1.2)
        case "m_vector":
            p.solid(p.poly([(14, 21.4), (25, 21.4), (8, 35.4)]), lmetal.dark(0.2), contrast: 0.8)
            p.solid(p.poly([(2.6, 16.6), (12, 18.6), (39.4, 20.4), (12, 22.4), (2.6, 24.2), (6.8, 20.4)]), chrome.dark(0.08), contrast: 1.2)
            p.solid(p.poly([(14, 19.4), (25, 19.4), (8, 5.4)]), lmetal, contrast: 1.0)
            p.line((10, 20.4), (32, 20.4), tc, 1.3)
            p.fill(p.roundRectPath(24, 19.6, 6, 1.8, 0.9), cyan.alpha(0.85))
            p.lamp(3.6, 20.4, 1.2, cyan)
        case "m_quake":
            let hex = p.poly([(5, 18), (11.6, 28.6), (28.4, 28.6), (35, 18), (28.4, 8.4), (11.6, 8.4)])
            p.solid(hex, lmetal.light(0.12), contrast: 1.2)
            p.solid(p.poly([(11.6, 28.6), (28.4, 28.6), (30.0, 30.0), (13.2, 30.0)]), lplate.light(0.2), contrast: 0.4)
            p.solid(p.poly([(12, 18), (15, 23.4), (25, 23.4), (28, 18), (25, 13), (15, 13)]), tc.dark(0.1), lw: 0.5)
            core(p, 20, 18, 2.4 + 0.3 * sin(ang(0)))
            for x in [9.0, 31.0] as [CGFloat] { thruster(p, x, 7.4, 1.6) }
            p.rivets([(8, 18), (32, 18), (13, 26), (27, 26)], lmetal)
        case "m_carrier":
            for x in [5.6, 34.4] as [CGFloat] { p.ball(x, 23.6, 3.4, 2.0, lmetal, lw: 0.5); thruster(p, x, 20.8, 1.6) }
            p.block(4.0, 18.0, 32.0, 6.6, depth: 2.6, lplate)
            p.block(11.0, 24.8, 18.0, 3.6, depth: 1.6, chrome.dark(0.1))
            p.line((6.0, 21.0), (34.0, 21.0), tc, 1.6)
            p.lamp(20, 26.6, 0.8, cyan)
        default: return false
        }
        return true
    }

    static func latticeUpper(_ id: String, _ v: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "m_fabricator":
            p.capsule((14.6, 17.6), (9.2, 13.6), 0.9, 0.7, chrome.dark(0.1)); p.ball(8.6, 13.0, 1.3, 1.3, lmetal, lw: 0.4)
            p.capsule((25.4, 17.6), (30.4, 13.6), 0.9, 0.75, chrome.dark(0.05))
            p.capsule((30.4, 13.6), (33.0, 11.2), 0.75, 0.55, chrome)
            p.lamp(33.0, 11.0, 0.8, cyan)
        case "m_arc":
            p.capsule((20, 24.6), (20, 29.4), 0.9, 0.7, chrome.dark(0.2))
            for k in 0..<3 { p.ball(20, 25.6 + CGFloat(k) * 1.4, 1.8 - CGFloat(k) * 0.3, 0.55, chrome, lw: 0.4, shine: 0.4) }     // coils
            p.ball(20, 32.2, 3.4, 3.4, chrome.light(0.1), shine: 0.8)
            p.lamp(20, 32.2, 1.6, cyan)
        case "m_shockframe":
            for (x, back) in [(9.0, true), (31.0, false)] as [(CGFloat, Bool)] {
                p.capsule((20, 21.6), (x, 17.6), 1.6, 1.4, lmetal.dark(back ? 0.2 : 0))
                p.ball(x, 16.0, 4.6, 4.6, chrome.dark(back ? 0.25 : 0.05), shine: 0.6)
                p.lamp(x + 2.2, 16.0, 1.4, cyan)
            }
        case "m_piercer":
            p.block(10.6, 16.0, 9.4, 4.6, depth: 1.6, lmetal.light(0.1))
            p.tube(14.0, 40.6, 19.0, 1.25, chrome.dark(0.05))
            p.line((15.0, 19.0), (40.0, 19.0), cyan.alpha(0.7), 0.5)
            for x in [24.0, 29.0, 34.0] as [CGFloat] { p.solid(p.roundRectPath(x - 0.8, 17.0, 1.6, 4.0, 0.5), lplate, lw: 0.4) }
            p.lamp(40.4, 19.0, 0.6, cyan)
        case "m_flak":
            p.block(14.6, 15.4, 10.8, 4.6, depth: 1.6, lmetal.light(0.1))
            for i in 0..<3 {
                let x0 = 16.4 + CGFloat(i) * 3.4
                p.capsule((x0, 18.6), (x0 + 5.0, 32.0), 0.95, 0.8, chrome.dark(0.05 * CGFloat(2 - i)))
                p.lamp(x0 + 5.0, 32.0, 0.5, cyan)
            }
        case "m_jammer":
            p.capsule((20, 22.2), (20, 28.4), 0.7, 0.6, chrome.dark(0.15))
            let dish = p.poly([(11.6, 34.6), (28.4, 34.6), (24.6, 28.4), (15.4, 28.4)])
            p.solid(dish, chrome, contrast: 1.2)
            for r in [5.6, 8.8] as [CGFloat] { p.stroke(p.ellipsePath(20, 35.4, r, r * 0.4), RGB(0.7, 0.45, 1, 0.65), 0.8) }
            p.lamp(20, 34.6, 0.7, RGB(0.75, 0.5, 1))
        case "m_runner":
            p.block(17.6, 14.6, 7.2, 3.4, depth: 1.2, lmetal)
            p.tube(23.6, 38.6, 16.8, 0.6, chrome.dark(0.1))
            p.lamp(38.6, 16.8, 0.4, cyan)
        case "m_bulwark":
            p.block(0.8, 18.6, 7.2, 5.2, depth: 1.6, chrome.dark(0.3))
            p.block(31.0, 18.6, 6.4, 5.2, depth: 1.6, chrome.dark(0.12))
            p.tube(36.4, 40.2, 21.2, 1.0, lmetal)
            p.lamp(39.9, 21.2, 0.8, cyan)
        case "m_coil":
            p.block(8.4, 14.6, 8.4, 5.4, depth: 1.8, lmetal.light(0.1))
            p.capsule((12.0, 17.4), (39.4, 27.0), 1.4, 1.1, chrome.dark(0.15))
            for i in 0..<5 {
                let t = CGFloat(i) / 5
                p.ball(17.0 + t * 17.6, 19.2 + t * 6.2, 1.0, 2.0, cyan.dark(0.2), lw: 0.4, shine: 0.6)
            }
            p.lamp(39.4, 27.0, 0.8, cyan)
        case "m_suppress":
            p.capsule((20, 20.2), (20, 23.6), 0.7, 0.6, chrome)
            p.stroke(p.ellipsePath(20, 25.2, 13.4, 5.0), RGB(0.05, 0.05, 0.07, 0.9), 2.6)
            p.stroke(p.ellipsePath(20, 25.2, 13.4, 5.0), cyan.alpha(0.95), 1.6)
            p.glow(20, 25.2, 12, cyan.alpha(0.35))
        default: return false
        }
        return true
    }
}
