import CoreGraphics
import Foundation

/// Lattice portraits: close-ups of each machine's own sensor head, turret or cockpit in its in-game finish
/// (gunmetal, chrome, faceted hex plating, cyan energy, the team band), framed like a diagnostic feed.
/// The camera servos after the gaze, lenses track and close their aperture blades to "blink", and speech
/// lights a vox strip while the lens and cores pulse.
extension PortraitArt {
    private static var metal: RGB { UnitArt.lmetal }
    private static var plate: RGB { UnitArt.lplate }
    private static var chrome: RGB { UnitArt.chrome }
    private static var cyan: RGB { UnitArt.cyan }

    static func lattice(_ p: Pen, _ id: String, _ team: RGB, _ f: Pose) {
        latticeBackdrop(p, f)
        p.ctx.saveGState()
        // Servo camera: follows the gaze, with a faint hum.
        let hum = CGFloat(sin(f.t * 9)) * 0.06
        p.ctx.translateBy(x: f.look.x * 0.8, y: f.look.y * 0.5 + hum)
        switch id {
        case "m_fabricator": fabricator(p, team, f)
        case "m_recon": recon(p, team, f)
        case "m_arc": arc(p, team, f)
        case "m_shockframe": shockframe(p, team, f)
        case "m_piercer": piercer(p, team, f)
        case "m_flak": flak(p, team, f)
        case "m_repair": repair(p, team, f)
        case "m_jammer": jammer(p, team, f)
        case "m_runner": runner(p, team, f)
        case "m_bulwark": bulwark(p, team, f)
        case "m_coil": coil(p, team, f)
        case "m_suppress": suppress(p, team, f)
        case "m_vector": vector(p, team, f)
        case "m_quake": quake(p, team, f)
        case "m_carrier": carrier(p, team, f)
        default: arc(p, team, f)
        }
        p.ctx.restoreGState()
        // Scan line rolling down the feed.
        let y = CGFloat(40 - (f.t * 9).truncatingRemainder(dividingBy: 48))
        p.fill(p.poly([(0, y), (40, y), (40, y + 0.8), (0, y + 0.8)]), cyan.alpha(0.07))
    }

    // MARK: Feed backdrop and shared parts

    static func latticeBackdrop(_ p: Pen, _ f: Pose) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [RGB(0.12, 0.20, 0.27).cg, RGB(0.03, 0.05, 0.08).cg] as CFArray, locations: [0, 1])!
        p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: 14, y: 30), startRadius: 0, endCenter: CGPoint(x: 20, y: 20), endRadius: 34, options: [.drawsAfterEndLocation])
        let s: CGFloat = 3.2
        for i in 0..<10 {
            for j in 0..<9 {
                let cx = CGFloat(i) * s * 1.5, cy = CGFloat(j) * s * 1.73 + (i % 2 == 0 ? 0 : s * 0.87)
                var pts: [(CGFloat, CGFloat)] = []
                for k in 0..<6 { let a = CGFloat(k) * .pi / 3; pts.append((cx + cos(a) * s, cy + sin(a) * s)) }
                p.stroke(p.poly(pts), cyan.alpha(0.05), 0.3)
            }
        }
    }

    /// Sensor lens: chrome housing, dark glass, an iris of light that tracks the gaze, and aperture blades
    /// that close to blink. Speech makes it flare.
    static func lens(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ f: Pose, color: RGB = UnitArt.cyan, housing: Bool = true) {
        if housing { p.ball(x, y, r * 1.3, r * 1.3, chrome.dark(0.15), lw: 0.5, shine: 0.5) }
        let glass = p.ellipsePath(x, y, r, r)
        p.fill(glass, RGB(0.02, 0.03, 0.05))
        p.ctx.saveGState(); p.ctx.addPath(glass); p.ctx.clip()
        let ix = x + f.look.x * r * 0.32, iy = y + f.look.y * r * 0.25
        if !PortraitArt.hidePupils { lensIris(p, ix, iy, r, flare: 1 + f.mouth * 0.35, color: color) }
        // Aperture blades.
        let open = r * (1.05 - f.blink * 1.05)
        if open < r {
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3
                let blade = p.poly([(x + cos(a) * r * 1.2, y + sin(a) * r * 1.2), (x + cos(a + 1.2) * r * 1.2, y + sin(a + 1.2) * r * 1.2),
                                    (x + cos(a + 0.6) * open, y + sin(a + 0.6) * open), (x + cos(a) * open * 0.8, y + sin(a) * open * 0.8)])
                p.solid(blade, metal.light(0.15), lw: 0.25, contrast: 0.6)
            }
        }
        p.fill(p.ellipsePath(x - r * 0.35, y + r * 0.42, r * 0.34, r * 0.18), RGB(1, 1, 1, 0.35))
        p.ctx.restoreGState()
        p.stroke(glass, RGB(0.02, 0.02, 0.03), 0.5)
    }

    /// The moving light inside a lens (its "pupil").
    static func lensIris(_ p: Pen, _ ix: CGFloat, _ iy: CGFloat, _ r: CGFloat, flare: CGFloat, color: RGB) {
        p.glow(ix, iy, r * 1.4 * flare, color.alpha(0.55))
        p.stroke(p.ellipsePath(ix, iy, r * 0.62, r * 0.62), color.alpha(0.6), max(0.25, r * 0.08))
        p.dot(ix, iy, r * 0.38 * flare, color.light(0.4))
        p.dot(ix, iy, r * 0.16, RGB(1, 1, 1, 0.95))
    }

    /// LED vox strip: bars that jump with speech, a low idle shimmer otherwise.
    static func vox(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ f: Pose, bars: Int = 5, color: RGB = UnitArt.cyan) {
        p.solid(p.roundRectPath(x - 0.6, y - 0.6, CGFloat(bars) * 1.3 + 0.6, 3.2, 0.6), RGB(0.04, 0.05, 0.07), lw: 0.35)
        for k in 0..<bars {
            let lvl = max(0.12, f.mouth * CGFloat(0.55 + 0.45 * sin(f.t * 21 + Double(k) * 1.9)))
            p.fill(p.roundRectPath(x + CGFloat(k) * 1.3, y, 0.8, 2 * lvl, 0.3), color.alpha(0.35 + 0.65 * min(1, lvl * 1.4)))
        }
    }

    /// Team band across armour.
    static func band(_ p: Pen, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ team: RGB, _ w: CGFloat = 1.6) {
        p.line(a, b, RGB(0.03, 0.03, 0.05), w + 0.8)
        p.line(a, b, team, w)
        p.line((a.0, a.1 + w * 0.25), (b.0, b.1 + w * 0.25), team.light(0.4).alpha(0.6), w * 0.25)
    }

    static func thrusterGlow(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ f: Pose) {
        let fl = 0.8 + 0.2 * CGFloat(sin(f.t * 17))
        p.glow(x, y, r * 3 * fl, cyan.alpha(0.5))
        p.fill(p.ellipsePath(x, y, r * 1.3, r * 0.5), cyan.light(0.5).alpha(0.9))
    }

    // MARK: Machines

    static func fabricator(_ p: Pen, _ team: RGB, _ f: Pose) {
        thrusterGlow(p, 20, -1, 4, f)
        UnitArt.hexHull(p, 1, 0, 38, 14, plate, tc: team)
        p.ball(20, 21, 12.5, 8.5, chrome.dark(0.1), shine: 0.8)
        p.seam((9, 17.6), (31, 17.6), chrome.dark(0.1))
        lens(p, 26.5, 21.5, 3.4, f)
        vox(p, 8.6, 20, f, bars: 4)
        // Welding arm in the foreground, its tip sparking when it speaks.
        p.capsule((31, 15), (36.5, 23), 1.6, 1.3, chrome.dark(0.05))
        p.capsule((36.5, 23), (38.5, 31), 1.3, 1.0, chrome)
        p.ball(36.5, 23, 1.7, 1.7, metal, lw: 0.4)
        p.lamp(38.6, 31.6, 1.0 + f.mouth * 0.6, cyan)
        if f.mouth > 0.1 { for k in 0..<4 { let a = CGFloat(f.t * 13) + CGFloat(k) * 1.6; p.line((38.6, 31.6), (38.6 + cos(a) * 2.6, 31.6 + sin(a) * 2.6), cyan.light(0.5), 0.3) } }
        p.capsule((8, 15), (3.5, 21), 1.4, 1.1, chrome.dark(0.2)); p.ball(3, 21.6, 1.8, 1.8, metal, lw: 0.4)
    }

    static func recon(_ p: Pen, _ team: RGB, _ f: Pose) {
        let spin = CGFloat(f.t * 40)
        for x in [1.0, 39.0] as [CGFloat] {
            p.fill(p.ellipsePath(x, 25, 9, 2.2), RGB(0.8, 0.9, 1, 0.14))
            p.line((x - cos(spin) * 9, 25 - sin(spin) * 2), (x + cos(spin) * 9, 25 + sin(spin) * 2), RGB(0.2, 0.22, 0.26, 0.7), 1.0)
        }
        p.capsule((2, 24), (38, 24), 1.3, 1.3, metal)
        p.solid(p.ellipsePath(20, 18, 19, 7.5), plate, contrast: 1.2)
        band(p, (5, 14.6), (35, 14.6), team, 1.8)
        p.ball(21, 22, 10, 6.5, chrome, shine: 0.8)
        lens(p, 25, 21.5, 3.8, f)
        vox(p, 12.2, 19.2, f, bars: 4)
        thrusterGlow(p, 20, 9.6, 2.4, f)
    }

    static func arc(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.hexHull(p, 3, -7, 34, 13, plate, tc: team)
        p.capsule((20, 5), (20, 15), 1.8, 1.5, chrome.dark(0.2))
        for k in 0..<3 { p.ball(20, 7.5 + CGFloat(k) * 2.8, 4.6 - CGFloat(k) * 0.7, 1.1, chrome, lw: 0.4, shine: 0.4) }
        // The head is one great chrome sensor sphere with its core as the eye.
        p.ball(20, 25, 11, 11, chrome.light(0.1), shine: 0.9)
        p.seam((10, 21), (30, 21), chrome)
        lens(p, 20 + f.look.x * 1.5, 25.5 + f.look.y, 6.2, f, housing: false)
        if f.mouth > 0.1 {
            for k in 0..<3 {
                let a = CGFloat(f.t * 7) + CGFloat(k) * 2.1
                var pts: [(CGFloat, CGFloat)] = []
                for s in 0..<5 { let r = 11.5 + CGFloat(s) * 1.4; let j = CGFloat(hash(s + k * 5, Int(f.t * 20))) - 0.5; pts.append((20 + cos(a + j * 0.3) * r, 25 + sin(a + j * 0.3) * r)) }
                for s in 0..<4 { p.line(pts[s], pts[s + 1], cyan.light(0.4).alpha(0.9), 0.4) }
            }
        }
        vox(p, 3, 4, f, bars: 4)
    }

    static func shockframe(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.hexHull(p, 3, -2, 34, 22, metal.light(0.1), tc: team)
        // Head block with a visor slit.
        p.block(10, 21, 20, 9, depth: 3, plate)
        let v = p.roundRectPath(12, 24, 16, 3, 1.2)
        p.fill(v, RGB(0.02, 0.03, 0.05))
        p.ctx.saveGState(); p.ctx.addPath(v); p.ctx.clip()
        let sx = 20 + f.look.x * 6
        p.glow(sx, 25.5, 5 * (1 - f.blink * 0.8), cyan.alpha(0.9))
        p.fill(p.roundRectPath(sx - 2, 24.8, 4, 1.4 * (1 - f.blink), 0.6), cyan.light(0.5))
        p.ctx.restoreGState()
        vox(p, 16.8, 13, f)
        // Shock gauntlets in the foreground.
        for (x, y, r, back) in [(3.0, 11.0, 6.5, true), (37.0, 13.0, 7.5, false)] as [(CGFloat, CGFloat, CGFloat, Bool)] {
            p.ball(x, y, r, r, chrome.dark(back ? 0.25 : 0.05), shine: 0.7)
            p.lamp(x + (back ? 2 : -2.5), y, 1.6 + f.mouth * 0.8, cyan)
            if f.mouth > 0.1 { p.glow(x, y, r * 1.6, cyan.alpha(0.25 * f.mouth)) }
        }
    }

    static func piercer(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.hexHull(p, -2, -1, 44, 13, plate, tc: team)
        p.ctx.saveGState()
        p.ctx.translateBy(x: 14, y: 20); p.ctx.rotate(by: f.look.y * 0.06); p.ctx.translateBy(x: -14, y: -20)
        p.block(4, 14, 20, 11, depth: 3, metal.light(0.1))
        p.tube(18, 46, 20, 2.6, chrome.dark(0.05))
        p.line((19, 20), (46, 20), cyan.alpha(0.6 + 0.4 * f.mouth), 0.8)
        for x in [26.0, 32.0, 38.0] as [CGFloat] { p.solid(p.roundRectPath(x - 1, 16.6, 2, 6.8, 0.6), plate, lw: 0.4) }
        lens(p, 10, 20.5, 2.8, f, color: RGB(1, 0.35, 0.3))
        p.ctx.restoreGState()
        vox(p, 5, 6, f)
    }

    static func flak(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.hexHull(p, -1, -2, 42, 13, plate, tc: team)
        thrusterGlow(p, 8, -1, 2.4, f); thrusterGlow(p, 32, -1, 2.4, f)
        p.block(7, 12, 22, 10, depth: 3, metal.light(0.1))
        for i in 0..<3 {
            let x0 = 13 + CGFloat(i) * 5
            p.capsule((x0, 18), (x0 + 9, 41), 2.0, 1.7, chrome.dark(0.06 * CGFloat(2 - i)))
            p.lamp(x0 + 9, 40.5, 0.8, cyan)
        }
        lens(p, 11, 17, 2.4, f)
        vox(p, 18, 13.6, f, bars: 4)
    }

    static func repair(_ p: Pen, _ team: RGB, _ f: Pose) {
        let green = RGB(0.4, 1, 0.55)
        for (x, y) in [(-1.0, 27.0), (41.0, 27.0)] as [(CGFloat, CGFloat)] {
            p.capsule((20, 21), (x, y), 2, 1.5, metal)
            p.ball(x, y, 4, 3.4, chrome.dark(0.15)); p.lamp(x + (x < 20 ? 1.5 : -1.5), y - 2.6, 0.9, green)
        }
        thrusterGlow(p, 20, 6, 3, f)
        p.ball(20, 20, 14, 11, chrome, shine: 0.9)
        band(p, (8, 11.5), (32, 11.5), team, 1.8)
        // The cross panel is its face; it brightens as it speaks.
        let g = 0.75 + f.mouth * 0.25 + 0.05 * CGFloat(sin(f.t * 3))
        p.glow(20, 18, 7 * g, green.alpha(0.35))
        p.solid(p.roundRectPath(17.8, 13, 4.4, 10.4, 0.6), green.mix(RGB(1, 1, 1), 0.2 * g), lw: 0.5)
        p.solid(p.roundRectPath(14.8, 16, 10.4, 4.4, 0.6), green.mix(RGB(1, 1, 1), 0.2 * g), lw: 0.5)
        lens(p, 20, 27.5, 2.6, f, color: green)
    }

    static func jammer(_ p: Pen, _ team: RGB, _ f: Pose) {
        let violet = RGB(0.75, 0.5, 1)
        UnitArt.hexHull(p, 5, -6, 30, 12, metal.light(0.08), tc: team, seam: false)
        p.capsule((20, 4), (20, 18), 1.5, 1.3, chrome.dark(0.15))
        // Expanding jamming rings.
        for k in 0..<3 {
            let u = CGFloat((f.t * 0.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1))
            p.stroke(p.ellipsePath(20, 30, 10 + u * 16, (10 + u * 16) * 0.45), violet.alpha((1 - u) * (0.5 + 0.4 * f.mouth)), 0.8)
        }
        let dish = p.poly([(2, 32), (38, 32), (29, 18), (11, 18)])
        p.solid(dish, chrome, contrast: 1.2)
        p.solid(p.ellipsePath(20, 32, 18, 5), chrome.dark(0.35), contrast: 0.6)
        p.fill(p.ellipsePath(20, 32.4, 15, 3.6), RGB(0.12, 0.10, 0.16))
        for r in [6.0, 10.0] as [CGFloat] { p.stroke(p.ellipsePath(20, 32.4, r, r * 0.25), violet.alpha(0.6), 0.6) }
        lens(p, 20, 31.6, 2.4, f, color: violet)
        vox(p, 16.8, 9, f, bars: 4, color: violet)
    }

    static func runner(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.offroadWheel(p, 9, 4, 9)
        let hull = p.poly([(-2, 9), (42, 11), (38, 19), (26, 23), (-2, 23)])
        p.solid(hull, chrome.dark(0.2), contrast: 1.2)
        p.solid(p.poly([(-2, 23), (26, 23), (28, 25), (-2, 25)]), chrome.light(0.1), contrast: 0.4)
        band(p, (-2, 15), (39, 16.4), team, 2.2)
        p.block(12, 24, 12, 6, depth: 2, metal)
        p.tube(22, 44, 27, 1.1, chrome.dark(0.1))
        lens(p, 34, 13.2, 2.8, f)
        vox(p, 3, 18.4, f)
    }

    static func bulwark(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.hexHull(p, -3, -4, 46, 26, metal.light(0.12), tc: team)
        p.block(-4, 20, 10, 8, depth: 2.4, chrome.dark(0.3))
        p.block(33, 20, 10, 8, depth: 2.4, chrome.dark(0.12))
        p.tube(40, 46, 24, 1.8, metal)
        p.block(11, 22, 18, 10, depth: 3, chrome.dark(0.15))
        lens(p, 20, 27, 3.6, f)
        vox(p, 16.8, 6, f)
        p.rivets([(13, 24), (27, 24), (13, 30), (27, 30)], chrome.dark(0.15))
    }

    static func coil(_ p: Pen, _ team: RGB, _ f: Pose) {
        UnitArt.tankTracks(p, -4, -3, 48, 11, metal)
        UnitArt.hexHull(p, -2, 7, 40, 10, plate, tc: team)
        p.block(3, 15, 18, 10, depth: 3, metal.light(0.1))
        p.capsule((12, 20), (46, 37), 2.4, 2.0, chrome.dark(0.15))
        for i in 0..<6 {
            let t = CGFloat(i) / 6
            let pulse = 0.5 + 0.5 * CGFloat(sin(f.t * 4 - Double(i) * 0.9)) + f.mouth * 0.5
            p.ball(18 + t * 24, 23 + t * 12, 1.6, 3.2, cyan.dark(0.4 - 0.3 * min(1, pulse)), lw: 0.4, shine: 0.6)
        }
        lens(p, 8.5, 20, 2.6, f, color: RGB(0.6, 0.6, 1))
        vox(p, 26, 8.8, f)
    }

    static func suppress(_ p: Pen, _ team: RGB, _ f: Pose) {
        let ringGlow = 0.6 + 0.4 * f.mouth + 0.1 * CGFloat(sin(f.t * 2.5))
        p.stroke(p.ellipsePath(20, 27, 19, 6.5), RGB(0.03, 0.03, 0.05, 0.9), 3.8)
        p.stroke(p.ellipsePath(20, 27, 19, 6.5), cyan.alpha(0.6 + 0.4 * ringGlow), 2.4)
        p.glow(20, 27, 16, cyan.alpha(0.3 * ringGlow))
        p.capsule((20, 17), (20, 24), 1.4, 1.2, chrome)
        p.ball(20, 12, 15, 11, plate, shine: 0.7)
        band(p, (7, 9), (33, 9), team, 2)
        lens(p, 20, 15, 3.6, f)
        vox(p, 16.8, 3, f)
        // Front of the ring passes over the stalk.
        let front = CGMutablePath()
        front.addArc(center: .zero, radius: 1, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false, transform: CGAffineTransform(translationX: 20, y: 27).scaledBy(x: 19, y: 6.5))
        p.stroke(front, cyan.alpha(0.6 + 0.4 * ringGlow), 2.4)
    }

    static func vector(_ p: Pen, _ team: RGB, _ f: Pose) {
        p.solid(p.poly([(4, 21), (22, 22), (2, 42)]), metal.dark(0.2), contrast: 0.8)
        p.solid(p.poly([(-2, 12), (10, 16), (44, 20), (10, 25), (-2, 28), (3, 20)]), chrome.dark(0.08), contrast: 1.2)
        p.solid(p.poly([(4, 19), (22, 18), (2, -2)]), metal, contrast: 1.0)
        band(p, (2, 20), (30, 20.4), team, 1.6)
        // Canopy strip with a sensor that slides along it.
        let c = p.roundRectPath(22, 20.6, 14, 2.6, 1.3)
        p.fill(c, RGB(0.02, 0.03, 0.05))
        p.ctx.saveGState(); p.ctx.addPath(c); p.ctx.clip()
        let sx = 29 + f.look.x * 5
        p.glow(sx, 21.9, 4 * (1 - f.blink * 0.8), cyan.alpha(0.9))
        p.fill(p.roundRectPath(sx - 1.6, 21.2, 3.2, 1.3 * (1 - f.blink), 0.6), cyan.light(0.5))
        p.ctx.restoreGState()
        p.lamp(43.4, 20, 0.8, cyan)
        vox(p, 8, 14.2, f, bars: 4)
    }

    static func quake(_ p: Pen, _ team: RGB, _ f: Pose) {
        thrusterGlow(p, 4, 1, 2.6, f); thrusterGlow(p, 36, 1, 2.6, f)
        let hex = p.poly([(-4, 20), (8, 39), (32, 39), (44, 20), (32, 1), (8, 1)])
        p.solid(hex, metal.light(0.12), contrast: 1.2)
        p.solid(p.poly([(7, 20), (13, 30), (27, 30), (33, 20), (27, 10), (13, 10)]), team.dark(0.15), lw: 0.6)
        lens(p, 20, 20, 5.4 + 0.3 * CGFloat(sin(f.t * 2)), f, color: RGB(1, 0.6, 0.2))
        p.rivets([(2, 20), (38, 20), (9, 34), (31, 34), (9, 6), (31, 6)], metal)
        vox(p, 16.8, 3.6, f)
    }

    static func carrier(_ p: Pen, _ team: RGB, _ f: Pose) {
        for x in [-1.0, 41.0] as [CGFloat] { p.ball(x, 20, 5, 3, metal, lw: 0.5); thrusterGlow(p, x, 16, 2.4, f) }
        p.block(1, 6, 38, 14, depth: 4, plate)
        band(p, (2, 13), (38, 13), team, 2.4)
        for x in [12.0, 20.0, 28.0] as [CGFloat] { p.seam((x, 7), (x, 11.4), plate) }
        p.block(9, 21, 22, 9, depth: 3, chrome.dark(0.1))
        lens(p, 20, 25.4, 2.8, f)
        vox(p, 4, 15.6, f, bars: 4)
    }
}
