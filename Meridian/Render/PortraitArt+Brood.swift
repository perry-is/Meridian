import CoreGraphics
import Foundation

/// Brood portraits: extreme close-ups of each creature's own head in its in-game colours (purple chitin,
/// bone horns and teeth, bioluminescent green, the team marking), cropped tight and lit from the side in a
/// murky hive. The head sways and breathes; eyes track and a translucent membrane sweeps across them to blink;
/// jaws, mandibles, orifices and bells open and pulse with speech.
extension PortraitArt {
    private static var shell: RGB { UnitArt.shell }
    private static var shellHi: RGB { UnitArt.shellHi }
    private static var bone: RGB { UnitArt.bone }
    private static var bio: RGB { UnitArt.bio }
    private static var meat: RGB { UnitArt.meat }
    private static var membrane: RGB { UnitArt.membrane }

    static func brood(_ p: Pen, _ id: String, _ team: RGB, _ f: Pose) {
        broodBackdrop(p, f)
        p.ctx.saveGState()
        let sway = CGFloat(sin(f.t * 0.8)) * 0.025 + f.look.x * 0.05
        let breathe = 1 + CGFloat(sin(f.t * 1.7)) * 0.012
        p.ctx.translateBy(x: 20 + f.look.x * 0.9, y: 4 + f.look.y * 0.6)
        p.ctx.rotate(by: -sway)
        p.ctx.scaleBy(x: breathe, y: breathe)
        p.ctx.translateBy(x: -20, y: -4)
        switch id {
        case "a_weaver": bugHead(p, team, f, big: true)
        case "a_skitter": bugHead(p, team, f, big: false)
        case "a_mantis": mantis(p, team, f)
        case "a_ravager": beast(p, team, f, heavy: false)
        case "a_colossus": beast(p, team, f, heavy: true)
        case "a_spinecaster": quillback(p, team, f, needles: false)
        case "a_needleback": quillback(p, team, f, needles: true)
        case "a_glint": glint(p, team, f)
        case "a_lifebinder": bell(p, team, f, spores: false)
        case "a_sporewing": bell(p, team, f, spores: true)
        case "a_shadeling": shadeling(p, team, f)
        case "a_rupturer": rupturer(p, team, f)
        case "a_seeder": seeder(p, team, f)
        case "a_wisp": wisp(p, team, f)
        case "a_blightwing": blightwing(p, team, f)
        default: bugHead(p, team, f, big: true)
        }
        p.ctx.restoreGState()
        // Spores drifting past the lens.
        for k in 0..<5 {
            let u = (f.t * (0.05 + Double(k) * 0.013) + hash(k, 4)).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(hash(k, 6)) * 40 + CGFloat(sin(f.t * 0.7 + Double(k))) * 1.5
            p.dot(x, CGFloat(u) * 44 - 2, 0.25 + CGFloat(hash(k, 8)) * 0.3, bio.alpha(0.35))
        }
    }

    // MARK: Hive backdrop and shared parts

    static func broodBackdrop(_ p: Pen, _ f: Pose) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [RGB(0.22, 0.12, 0.24).cg, RGB(0.06, 0.03, 0.07).cg] as CFArray, locations: [0, 1])!
        p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: 12, y: 30), startRadius: 0, endCenter: CGPoint(x: 20, y: 20), endRadius: 34, options: [.drawsAfterEndLocation])
        let pulse = 0.5 + 0.5 * CGFloat(sin(f.t * 1.1))
        for k in 0..<4 {
            let v = CGMutablePath()
            let y0 = 6 + CGFloat(k) * 9
            v.move(to: CGPoint(x: -1, y: y0)); v.addCurve(to: CGPoint(x: 41, y: y0 + 6), control1: CGPoint(x: 12, y: y0 + 9), control2: CGPoint(x: 26, y: y0 - 6))
            p.stroke(v, RGB(0.35, 0.16, 0.30, 0.35), 1.2)
            p.stroke(v, bio.alpha(0.06 + 0.06 * pulse), 0.4)
        }
    }

    /// Glossy bead eye with a slit pupil that tracks; a translucent nictitating membrane sweeps down to blink.
    static func beadEye(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ f: Pose, glow: RGB = UnitArt.bio) {
        p.glow(x, y, r * 2.4, glow.alpha(0.35))
        let path = p.ellipsePath(x, y, r, r * 0.9)
        p.ball(x, y, r, r * 0.9, RGB(0.05, 0.02, 0.07), lw: 0.5, shine: 0)
        p.ctx.saveGState(); p.ctx.addPath(path); p.ctx.clip()
        let ix = x + f.look.x * r * 0.3, iy = y + f.look.y * r * 0.2
        p.fill(p.ellipsePath(ix, iy, r * 0.66, r * 0.62), glow.dark(0.1))
        p.fill(p.ellipsePath(ix - r * 0.1, iy + r * 0.1, r * 0.4, r * 0.36), glow.light(0.3))
        p.fill(p.ellipsePath(ix, iy, r * 0.13, r * 0.52), RGB(0.02, 0.01, 0.03))
        p.dot(x - r * 0.38, y + r * 0.36, r * 0.17, RGB(1, 1, 1, 0.9))
        if f.blink > 0.02 {
            let edge = y + r - 2 * r * f.blink
            p.fill(p.poly([(x - r, y + r), (x + r, y + r), (x + r, edge), (x - r, edge - r * 0.2)]), membrane.mix(RGB(0.9, 0.85, 0.8), 0.4).alpha(0.82))
        }
        p.ctx.restoreGState()
    }

    /// Big faceted insect eye: a hex lattice of facets, a glow that follows the gaze, membrane blink.
    static func compoundEye(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ f: Pose, glow: RGB = UnitArt.bio) {
        p.glow(x, y, max(rx, ry) * 1.8, glow.alpha(0.3))
        let path = p.ellipsePath(x, y, rx, ry)
        p.ball(x, y, rx, ry, RGB(0.07, 0.03, 0.09), lw: 0.6, shine: 0)
        p.ctx.saveGState(); p.ctx.addPath(path); p.ctx.clip()
        p.glow(x + f.look.x * rx * 0.4, y + f.look.y * ry * 0.3, max(rx, ry) * 1.1, glow.alpha(0.6))
        let s = max(rx, ry) / 4.2
        for i in -6...6 {
            for j in -6...6 {
                let cx = x + CGFloat(i) * s * 1.5, cy = y + CGFloat(j) * s * 1.73 + (i % 2 == 0 ? 0 : s * 0.87)
                var pts: [(CGFloat, CGFloat)] = []
                for k in 0..<6 { let a = CGFloat(k) * .pi / 3; pts.append((cx + cos(a) * s * 0.95, cy + sin(a) * s * 0.95)) }
                p.stroke(p.poly(pts), RGB(0.02, 0.01, 0.03, 0.55), 0.3)
            }
        }
        p.fill(p.ellipsePath(x - rx * 0.32, y + ry * 0.42, rx * 0.38, ry * 0.2), RGB(1, 1, 1, 0.45))
        if f.blink > 0.02 {
            let edge = y + ry - 2 * ry * f.blink
            p.fill(p.poly([(x - rx, y + ry), (x + rx, y + ry), (x + rx, edge), (x - rx, edge - ry * 0.25)]), membrane.mix(RGB(0.9, 0.85, 0.8), 0.4).alpha(0.75))
        }
        p.ctx.restoreGState()
        p.stroke(path, shell.dark(0.5), 0.5)
    }

    /// A row of bone teeth along a→b, pointing `dir` (+1 up, -1 down).
    static func teeth(_ p: Pen, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), n: Int, len: CGFloat, dir: CGFloat) {
        for k in 0..<n {
            let t0 = CGFloat(k) / CGFloat(n), t1 = CGFloat(k + 1) / CGFloat(n)
            let x0 = a.0 + (b.0 - a.0) * t0, y0 = a.1 + (b.1 - a.1) * t0
            let x1 = a.0 + (b.0 - a.0) * t1, y1 = a.1 + (b.1 - a.1) * t1
            let l = len * (0.7 + 0.3 * CGFloat(hash(k, 13)))
            p.solid(p.poly([(x0, y0), ((x0 + x1) / 2, (y0 + y1) / 2 + l * dir), (x1, y1)]), bone.light(0.05), lw: 0.3, contrast: 0.8)
        }
    }

    /// Team marking: a glowing patch on the carapace.
    static func marking(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ team: RGB) {
        p.glow(x, y, max(rx, ry) * 1.4, team.alpha(0.35))
        p.fill(p.ellipsePath(x, y, rx, ry), team.alpha(0.85))
        p.fill(p.ellipsePath(x - rx * 0.25, y + ry * 0.3, rx * 0.4, ry * 0.25), RGB(1, 1, 1, 0.3))
    }

    /// Plate seams across a carapace.
    static func plates(_ p: Pen, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, n: Int, _ c: RGB) {
        for k in 1..<n {
            let x = cx - rx + 2 * rx * CGFloat(k) / CGFloat(n)
            let h = ry * max(0, 1 - pow((x - cx) / rx, 2)).squareRoot()
            p.line((x, cy + h * 0.92), (x - 1.2, cy - h * 0.75), c.dark(0.45).alpha(0.7), 0.6)
            p.line((x + 0.5, cy + h * 0.9), (x - 0.6, cy - h * 0.65), c.light(0.35).alpha(0.35), 0.4)
        }
    }

    // MARK: Creatures

    /// Weaver / Skitter: ant-like worker heads with pincer mandibles and feelers.
    static func bugHead(_ p: Pen, _ team: RGB, _ f: Pose, big: Bool) {
        let c = big ? shellHi : shellHi.light(0.1).mix(RGB(0.6, 0.25, 0.3), 0.15)
        let hx: CGFloat = 19, hy: CGFloat = 20, rx: CGFloat = big ? 12.5 : 11, ry: CGFloat = big ? 10.5 : 9.4
        // Thorax below.
        p.ball(15, 1, 16, 7, shell.dark(0.2), shine: 0.3)
        plates(p, 15, 1, 16, 7, n: 4, shell.dark(0.2))
        // Feelers.
        for (k, base) in [(15.0, 28.0), (24.0, 29.0)].enumerated() {
            let sway = CGFloat(sin(f.t * 1.4 + Double(k) * 1.3)) * 1.6
            let a = CGMutablePath()
            let tip = CGPoint(x: CGFloat(base.0) + (k == 0 ? -9 : 9) + sway, y: 41)
            a.move(to: CGPoint(x: base.0, y: base.1))
            a.addQuadCurve(to: tip, control: CGPoint(x: CGFloat(base.0) + (k == 0 ? -1 : 3), y: 39))
            p.stroke(a, Pen.ink, 1.5); p.stroke(a, shell.light(0.15), 0.8)
        }
        if !big {
            for k in 0..<3 { let x = hx - 6 + CGFloat(k) * 5; p.solid(p.poly([(x - 1.4, hy + ry - 1.5), (x + 0.6, hy + ry + 4 - CGFloat(k % 2) * 1.5), (x + 1.6, hy + ry - 1.2)]), bone, lw: 0.4) }
        }
        p.ball(hx, hy, rx, ry, c, shine: 0.8)
        plates(p, hx, hy, rx, ry, n: 3, c)
        p.fill(p.ellipsePath(hx + rx * 0.6, hy - ry * 0.2, rx * 0.5, ry * 0.9), shell.dark(0.5).alpha(0.35))
        marking(p, hx - 4, hy + 5.5, 3.2, 1.8, team)
        // Mandibles: two bone hooks that part to speak.
        let open = 0.12 + f.mouth * 0.42 + CGFloat(sin(f.t * 2.3)) * 0.04
        let hinge = (hx + rx * 0.62, hy - ry * 0.55)
        if f.mouth > 0.05 { p.glow(hinge.0 + 5, hinge.1, 3 + f.mouth * 3, bio.alpha(0.6)); p.fill(p.ellipsePath(hinge.0 + 2.4, hinge.1, 2.2, 0.8 + f.mouth * 1.8), RGB(0.25, 0.05, 0.12)) }
        for side in [1.0, -1.0] as [CGFloat] {
            let a = side * open
            let L: CGFloat = big ? 9 : 10.5
            let tip = (hinge.0 + cos(a) * L, hinge.1 + sin(a) * L + side * 0.6)
            let m = CGMutablePath()
            m.move(to: CGPoint(x: hinge.0 - 1, y: hinge.1 + side * 1.4))
            m.addQuadCurve(to: CGPoint(x: tip.0, y: tip.1), control: CGPoint(x: hinge.0 + L * 0.6, y: hinge.1 + side * (3.4 + open * 4)))
            m.addQuadCurve(to: CGPoint(x: hinge.0 + 0.6, y: hinge.1 - side * 0.4), control: CGPoint(x: hinge.0 + L * 0.5, y: hinge.1 + side * (1.4 + open * 3)))
            m.closeSubpath()
            p.solid(m, bone.dark(side > 0 ? 0 : 0.15), lw: 0.5, contrast: 1.2)
        }
        if big { compoundEye(p, hx + 6.5, hy + 1.5, 4.6, 4.0, f) } else { beadEye(p, hx + 6.2, hy + 1.6, 2.8, f) }
    }

    /// Mantis: narrow wedge head, bulging eyes, a scythe raised in the foreground.
    static func mantis(_ p: Pen, _ team: RGB, _ f: Pose) {
        p.ball(18, 2, 11, 8, shell, shine: 0.4)
        marking(p, 15, 5, 3.4, 2, team)
        p.capsule((19, 8), (20, 15), 3.4, 2.6, shell.dark(0.1))
        let head = p.poly([(7, 27), (13, 32), (27, 32.5), (33, 27), (24, 12), (20, 10.5), (16, 12)])
        p.solid(head, shellHi.light(0.04), contrast: 1.2)
        p.line((20, 31), (20, 14), shellHi.light(0.4).alpha(0.5), 0.6)
        compoundEye(p, 9.6, 26.4, 4.2, 5.4, f)
        compoundEye(p, 30.6, 26.6, 4.6, 5.8, f)
        // Feelers.
        for side in [-1.0, 1.0] as [CGFloat] {
            let sway = CGFloat(sin(f.t * 1.6 + Double(side))) * 1.2
            p.line((20 + side * 2, 31), (20 + side * 7 + sway, 41), Pen.ink, 1.1); p.line((20 + side * 2, 31), (20 + side * 7 + sway, 41), shellHi, 0.5)
        }
        // Small jaws at the chin.
        let o = f.mouth
        if f.mouth > 0.05 { p.fill(p.ellipsePath(20, 12, 1.8 + o, 0.8 + o * 2), RGB(0.25, 0.05, 0.12)); p.glow(20, 12, 3 * o, bio.alpha(0.6)) }
        for side in [-1.0, 1.0] as [CGFloat] {
            p.solid(p.poly([(20 + side * 1.6, 15), (20 + side * (4 + o * 2.6), 8.4 - o * 0.6), (20 + side * (1.6 + o * 1.4), 9.8), (20 + side * 0.6, 12)]), bone.dark(0.1), lw: 0.4)
        }
        // Scythe arm, foreground right, lifting slightly while it talks.
        p.ctx.saveGState()
        p.ctx.translateBy(x: 36, y: 6); p.ctx.rotate(by: f.mouth * 0.12 + CGFloat(sin(f.t * 0.9)) * 0.03); p.ctx.translateBy(x: -36, y: -6)
        p.capsule((42, 2), (34, 15), 2.6, 2.0, shell.dark(0.05))
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 33, y: 14)); blade.addQuadCurve(to: CGPoint(x: 37, y: 40), control: CGPoint(x: 30, y: 30))
        blade.addQuadCurve(to: CGPoint(x: 36, y: 15), control: CGPoint(x: 34.8, y: 28)); blade.closeSubpath()
        p.solid(blade, bone, lw: 0.6, contrast: 1.4)
        for k in 0..<5 { let y = 19 + CGFloat(k) * 3.6; p.solid(p.poly([(33.2 + CGFloat(k) * 0.25, y), (31.4 + CGFloat(k) * 0.2, y + 1.2), (33.4 + CGFloat(k) * 0.25, y + 1.6)]), bone.dark(0.1), lw: 0.3) }
        p.line((34.4, 18), (36.4, 37), RGB(1, 1, 1, 0.55), 0.4)
        p.ctx.restoreGState()
    }

    /// Ravager / Colossus: armoured beast skulls with bone horns, tusks and a jaw full of teeth.
    static func beast(_ p: Pen, _ team: RGB, _ f: Pose, heavy: Bool) {
        let c = heavy ? shell.light(0.04) : shellHi
        let k: CGFloat = heavy ? 1.12 : 1
        // Dorsal bone spikes behind.
        for i in 0..<(heavy ? 5 : 3) {
            let x = 2 + CGFloat(i) * (heavy ? 5.2 : 6), top = 36 + CGFloat(i % 2) * 3 - CGFloat(i) * (heavy ? 0.4 : 1.4)
            p.solid(p.poly([(x, 24), (x + 2.6, top), (x + 5.4, 24.6)]), bone.dark(0.08), lw: 0.5, contrast: 1.2)
        }
        // Neck and shoulder mass.
        p.ball(8, 6, 15 * k, 12 * k, c.dark(0.15), shine: 0.4)
        plates(p, 8, 6, 15 * k, 12 * k, n: 4, c.dark(0.15))
        // Lower jaw hinges open with speech.
        let hinge = CGPoint(x: 15, y: 13)
        let drop = 0.04 + f.mouth * 0.26
        p.ctx.saveGState()
        p.ctx.translateBy(x: hinge.x, y: hinge.y); p.ctx.rotate(by: -drop); p.ctx.translateBy(x: -hinge.x, y: -hinge.y)
        let jaw = p.poly([(12, 13), (36 * k - 2, 11), (39, 7.6), (35, 5), (14, 6.5)])
        p.fill(p.poly([(16, 12.8), (36, 11.2), (34, 9.6), (16, 10)]), RGB(0.30, 0.06, 0.12))
        p.solid(jaw, c.dark(0.1), contrast: 1.1)
        teeth(p, (18, 11.4), (36, 10.2), n: 7, len: 2.2, dir: 1)
        p.ctx.restoreGState()
        // Maw glow between the jaws.
        if f.mouth > 0.05 { p.glow(28, 12, 4 + f.mouth * 4, bio.alpha(0.45 * f.mouth + 0.2)) }
        // Skull.
        let skull = CGMutablePath()
        skull.move(to: CGPoint(x: 6, y: 18))
        skull.addCurve(to: CGPoint(x: 22, y: 31 * k), control1: CGPoint(x: 6, y: 27), control2: CGPoint(x: 13, y: 31 * k))
        skull.addCurve(to: CGPoint(x: 38, y: 17), control1: CGPoint(x: 30, y: 31 * k), control2: CGPoint(x: 35, y: 24))
        skull.addCurve(to: CGPoint(x: 37, y: 11.5), control1: CGPoint(x: 40, y: 15), control2: CGPoint(x: 39.5, y: 12))
        skull.addLine(to: CGPoint(x: 14, y: 12.5))
        skull.addCurve(to: CGPoint(x: 6, y: 18), control1: CGPoint(x: 9, y: 12.5), control2: CGPoint(x: 6, y: 14))
        skull.closeSubpath()
        p.solid(skull, c, contrast: 1.2)
        p.ctx.saveGState(); p.ctx.addPath(skull); p.ctx.clip()
        p.ball(19, 22, 15, 10, c, outline: nil, shine: 0.8)
        plates(p, 19, 22, 15, 10, n: 4, c)
        p.fill(p.ellipsePath(30, 13, 12, 3), c.dark(0.45).alpha(0.4))
        p.ctx.restoreGState()
        p.stroke(skull, Pen.ink, 0.75)
        teeth(p, (20, 12.6), (36.5, 11.8), n: 7, len: 2.0, dir: -1)
        marking(p, 14, 23, 3.4, 2.0, team)
        // Brow ridge and eyes.
        p.solid(p.poly([(21, 23.4), (31, 21.6), (32, 19.6), (22, 21.2)]), c.dark(0.35), lw: 0.4)
        beadEye(p, 27.6, 19.2, heavy ? 2.1 : 1.8, f)
        // Horn and tusk.
        let horn = CGMutablePath()
        horn.move(to: CGPoint(x: 31, y: 21)); horn.addQuadCurve(to: CGPoint(x: heavy ? 41 : 39, y: heavy ? 42 : 36), control: CGPoint(x: 39, y: 24))
        horn.addQuadCurve(to: CGPoint(x: 36.4, y: 17.6), control: CGPoint(x: 38, y: 24)); horn.closeSubpath()
        p.solid(horn, bone, lw: 0.6, contrast: 1.4)
        for i in 0..<3 { p.line((35 + CGFloat(i) * 0.9, 22 + CGFloat(i) * 3.5), (37.6 + CGFloat(i) * 0.5, 21.6 + CGFloat(i) * 3.6), bone.dark(0.35), 0.35) }
        p.solid(p.poly([(33, 12), (41, 7.5), (36.4, 13.8)]), bone.dark(0.08), lw: 0.5, contrast: 1.2)
    }

    /// Spinecaster / Needleback: low heads under a fan of quills tipped with venom glow.
    static func quillback(_ p: Pen, _ team: RGB, _ f: Pose, needles: Bool) {
        let c = needles ? shellHi : UnitArt.meat.dark(0.2)
        // Quills fanning up behind, rattling as it talks.
        let n = needles ? 11 : 7
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let base = (2 + t * 26, 18 + sin(t * .pi) * 4)
            let rattle = f.mouth * CGFloat(sin(f.t * 30 + Double(i))) * 0.6
            let tip = (base.0 + (needles ? 2 : 8) + rattle, base.1 + (needles ? 20 : 17) - abs(t - 0.5) * 6)
            p.capsule(base, tip, needles ? 0.55 : 0.9, 0.15, bone.mix(bio, needles ? 0.3 : CGFloat(i % 2) * 0.15))
            p.lamp(tip.0, tip.1, needles ? 0.35 : 0.45, bio)
        }
        p.ball(13, 8, 16, 11, c.dark(0.1), shine: 0.5)
        plates(p, 13, 8, 16, 11, n: 4, c.dark(0.1))
        marking(p, 9, 11, 3.6, 2, team)
        // Head, low and forward.
        p.ball(27, 14, 10, 8, needles ? shell : shell.light(0.05), shine: 0.8)
        plates(p, 27, 14, 10, 8, n: 3, shell)
        // Launcher maw: a puckered orifice that dilates.
        let mx: CGFloat = 35.4, my: CGFloat = 12
        p.ball(mx, my, 3.4, 3.2, meat.dark(0.15), shine: 0.4)
        let o = 0.5 + f.mouth * 1.6
        p.fill(p.ellipsePath(mx + 0.4, my, o * 0.8, o), RGB(0.2, 0.03, 0.08))
        if f.mouth > 0.05 { p.glow(mx + 0.4, my, 2 + f.mouth * 3, bio.alpha(0.7)) }
        for k in 0..<6 { let a = CGFloat(k) * .pi / 3; p.line((mx + 0.4 + cos(a) * o, my + sin(a) * o), (mx + 0.4 + cos(a) * 3, my + sin(a) * 2.9), meat.dark(0.45), 0.4) }
        p.solid(p.poly([(24, 20), (32, 18.6), (32.6, 17), (25, 18)]), shell.dark(0.35), lw: 0.4)
        beadEye(p, 30, 16.4, 1.8, f)
    }

    /// Glint: a floating luminous orb with one large eye.
    static func glint(_ p: Pen, _ team: RGB, _ f: Pose) {
        let bob = CGFloat(sin(f.t * 1.5)) * 0.8
        for k in 0..<5 {
            let x = 12 + CGFloat(k) * 4
            let sway = CGFloat(sin(f.t * 1.2 + Double(k) * 0.8)) * 2.4
            let t = CGMutablePath(); t.move(to: CGPoint(x: x, y: 12 + bob)); t.addQuadCurve(to: CGPoint(x: x - 2 + sway, y: -2), control: CGPoint(x: x + sway, y: 6))
            p.stroke(t, membrane.alpha(0.7), 1.0); p.stroke(t, bio.alpha(0.3), 2.4)
        }
        let pulse = 0.5 + 0.5 * CGFloat(sin(f.t * 2)) + f.mouth * 0.8
        p.glow(20, 21 + bob, 22, bio.alpha(0.35 + 0.15 * pulse))
        p.ball(20, 21 + bob, 15, 11.5, membrane.alpha(0.88), shine: 1)
        p.ball(18, 21.5 + bob, 7.5 + f.mouth * 0.8, 5.5 + f.mouth * 0.6, bio.light(0.3), outline: nil, shine: 0.5)
        for k in 0..<4 { let a = CGFloat(k) * 1.4 + CGFloat(f.t) * 0.3; p.line((18, 21.5 + bob), (18 + cos(a) * 12, 21.5 + bob + sin(a) * 8.5), bio.dark(0.3).alpha(0.35), 0.4) }
        marking(p, 11, 27 + bob, 1.8, 1.2, team)
        beadEye(p, 28.5, 22 + bob, 4.4, f)
    }

    /// Lifebinder / Sporewing: a great translucent bell with a pulsing core, tentacles trailing beneath.
    static func bell(_ p: Pen, _ team: RGB, _ f: Pose, spores: Bool) {
        let bob = CGFloat(sin(f.t * 1.3)) * 0.8
        for i in 0..<7 {
            let x = 6 + CGFloat(i) * 4.6
            let sway = CGFloat(sin(f.t * 1.1 + Double(i) * 0.7)) * 2.2
            let t = CGMutablePath(); t.move(to: CGPoint(x: x, y: 15 + bob)); t.addQuadCurve(to: CGPoint(x: x + sway, y: -2), control: CGPoint(x: x - sway, y: 7))
            p.stroke(t, Pen.ink, 2.2); p.stroke(t, meat.light(spores ? 0 : 0.25), 1.4)
        }
        let c = spores ? RGB(0.58, 0.38, 0.6) : membrane.alpha(0.9)
        let pulse = CGFloat(sin(f.t * 1.6)) * 0.4 + f.mouth * 1.0
        if !spores { p.glow(20, 25 + bob, 22, bio.alpha(0.4)) }
        p.ball(20, 26 + bob, 19 + pulse * 0.4, 14 + pulse * 0.3, c, shine: 0.9)
        plates(p, 20, 26 + bob, 19, 14, n: 5, c)
        if spores {
            for (x, y) in [(9, 30), (16, 35), (24, 34.5), (31, 29), (13, 22), (27, 21), (20, 27)] as [(CGFloat, CGFloat)] {
                p.lamp(x, y + bob, 0.9 + f.mouth * 0.4, bio)
            }
            // Underside maw.
            p.fill(p.ellipsePath(20, 13.4 + bob, 8 + f.mouth * 1.5, 1.2 + f.mouth * 2.2), RGB(0.18, 0.04, 0.1))
            if f.mouth > 0.05 { p.glow(20, 13.4 + bob, 4 + f.mouth * 4, bio.alpha(0.6)) }
            for (k, x) in stride(from: 14.0, through: 26.0, by: 4.0).enumerated() { beadEye(p, CGFloat(x), 16.6 + bob - CGFloat(abs(k - 1)) * 0.3, 1.0, f) }
        } else {
            // The nucleus: three lobes that brighten when it speaks; the bell's only "face".
            let glow = 0.6 + f.mouth * 0.4 + 0.1 * CGFloat(sin(f.t * 2.4))
            for (dx, dy) in [(-3.4, 0.0), (3.4, 0.0), (0.0, 3.6)] as [(CGFloat, CGFloat)] {
                p.ball(20 + dx + f.look.x * 1.2, 26 + dy + bob + f.look.y * 0.8, 3.4, 3.0, bio.light(0.35 * glow), outline: nil, shine: 0.6)
            }
            p.glow(20 + f.look.x * 1.2, 27 + bob, 8 * glow, RGB(1, 1, 0.8, 0.5 * glow * (1 - f.blink * 0.6)))
        }
        p.fill(p.ellipsePath(20, 14.6 + bob, 12, 1.6), team.alpha(0.85))
        p.glow(20, 14.6 + bob, 8, team.alpha(0.3))
    }

    /// Shadeling: a hood of shadow, two violet eyes, bone scythes crossed in front.
    static func shadeling(_ p: Pen, _ team: RGB, _ f: Pose) {
        let violet = RGB(0.95, 0.35, 1)
        for k in 0..<6 {
            let x = 4 + CGFloat(k) * 6.4
            let w = CGMutablePath(); w.move(to: CGPoint(x: x, y: 2))
            w.addQuadCurve(to: CGPoint(x: x + CGFloat(sin(f.t + Double(k))) * 3, y: 18), control: CGPoint(x: x + 4, y: 10))
            p.stroke(w, RGB(0.35, 0.12, 0.45, 0.25), 2.4)
        }
        p.glow(20, 22, 20, RGB(0.45, 0.12, 0.55, 0.45))
        let hood = p.poly([(2, -1), (8, 22), (20, 39), (32, 22), (38, -1), (28, 6), (20, 3), (12, 6)])
        p.solid(hood, RGB(0.18, 0.09, 0.24), contrast: 1.4)
        let face = CGMutablePath()
        face.move(to: CGPoint(x: 12, y: 12)); face.addQuadCurve(to: CGPoint(x: 20, y: 32), control: CGPoint(x: 11, y: 26))
        face.addQuadCurve(to: CGPoint(x: 28, y: 12), control: CGPoint(x: 29, y: 26)); face.addQuadCurve(to: CGPoint(x: 12, y: 12), control: CGPoint(x: 20, y: 9)); face.closeSubpath()
        p.fill(face, RGB(0.03, 0.01, 0.05))
        let flare = 1 + f.mouth * 0.6
        for side in [-1.0, 1.0] as [CGFloat] {
            let ex = 20 + side * 3.6 + f.look.x * 1.4, ey = 22 + f.look.y * 0.8
            let h = 0.9 * (1 - f.blink * 0.9)
            p.glow(ex, ey, 4 * flare, violet.alpha(0.6))
            p.ctx.saveGState(); p.ctx.translateBy(x: ex, y: ey); p.ctx.rotate(by: side * -0.3)
            p.fill(p.ellipsePath(0, 0, 1.8 * flare, max(0.15, h)), violet.light(0.4))
            p.ctx.restoreGState()
        }
        if f.mouth > 0.05 { p.fill(p.ellipsePath(20, 16, 2.2, 0.3 + f.mouth * 0.9), violet.alpha(0.5)) }
        p.line((14.6, 13.4), (25.4, 13.4), team, 1.0)
        for side in [-1.0, 1.0] as [CGFloat] {
            let s = CGFloat(sin(f.t * 0.8)) * 0.6
            p.solid(p.poly([(20 + side * 6, 4), (20 + side * 20, 30 + s), (20 + side * 12, 8)]), bone.dark(0.35), lw: 0.5, contrast: 1.3)
        }
    }

    /// Rupturer: a swollen bile sac and a stalk ending in a dilating launch orifice.
    static func rupturer(_ p: Pen, _ team: RGB, _ f: Pose) {
        p.ball(14, 5, 16, 9, meat.dark(0.2), shine: 0.4)
        marking(p, 8, 8, 3.6, 2, team)
        let pulse = CGFloat(sin(f.t * 1.4)) * 0.4 + f.mouth * 0.8
        p.glow(13, 20, 16, bio.alpha(0.4 + 0.1 * pulse))
        p.ball(13, 20, 13 + pulse * 0.5, 11 + pulse * 0.4, RGB(0.55, 0.85, 0.28, 0.95), shine: 0.9)
        for k in 0..<5 {
            let a = CGFloat(k) * 1.2 + 0.4
            let v = CGMutablePath(); v.move(to: CGPoint(x: 13, y: 20))
            v.addQuadCurve(to: CGPoint(x: 13 + cos(a) * 11, y: 20 + sin(a) * 9), control: CGPoint(x: 13 + cos(a + 0.4) * 6, y: 20 + sin(a + 0.4) * 6))
            p.stroke(v, RGB(0.3, 0.5, 0.12, 0.45), 0.5)
        }
        // Stalk swings with the gaze.
        let tip = CGPoint(x: 33 + f.look.x * 2, y: 31 + f.look.y * 1.5)
        p.capsule((24, 12), (tip.x - 1, tip.y - 1.5), 3.4, 2.2, shell)
        p.ball(tip.x, tip.y, 4.2, 3.8, meat, shine: 0.7)
        let o = 0.6 + f.mouth * 1.8
        p.fill(p.ellipsePath(tip.x + 1.4, tip.y + 0.4, o * 0.7, o), RGB(0.2, 0.03, 0.08))
        p.lamp(tip.x + 1.4, tip.y + 0.4, 0.5 + f.mouth * 0.9, bio)
        beadEye(p, 28.4, 14.4, 1.9, f)
    }

    /// Spore Seeder: a mushroom cap with glowing spores over a soft body and a vertical maw.
    static func seeder(_ p: Pen, _ team: RGB, _ f: Pose) {
        p.ball(20, 2, 12, 7, shell.dark(0.25), shine: 0.3)
        p.ball(20, 13, 10, 9, meat.dark(0.2), shine: 0.6)
        marking(p, 20, 3.4, 5, 1.2, team)
        let o = f.mouth
        p.fill(p.ellipsePath(20.6, 12, 0.8 + o * 1.4, 2.2 + o * 1.4), RGB(0.2, 0.03, 0.08))
        if o > 0.05 { p.glow(20.6, 12, 2 + o * 3, bio.alpha(0.6)) }
        teeth(p, (19.4, 14.4), (19.4, 9.8), n: 3, len: 0.9 + o * 0.5, dir: 1)
        beadEye(p, 16.2, 16.4, 1.6, f); beadEye(p, 25.2, 16.6, 1.6, f)
        let lift = CGFloat(sin(f.t * 1.2)) * 0.5 + f.mouth * 0.6
        let cap = p.poly([(-2, 24 + lift), (8, 34 + lift), (20, 40 + lift), (32, 34 + lift), (42, 24 + lift), (20, 19.4 + lift)])
        p.solid(cap, RGB(0.55, 0.30, 0.56), contrast: 1.3)
        p.solid(p.poly([(-2, 24 + lift), (20, 19.4 + lift), (42, 24 + lift), (20, 22.2 + lift)]), RGB(0.82, 0.62, 0.7), lw: 0.4)
        for k in 0..<9 { p.line((20, 19.8 + lift), (CGFloat(k) * 5, 23.4 + lift - abs(CGFloat(k) - 4) * 0.2), RGB(0.6, 0.4, 0.5, 0.6), 0.3) }
        for (k, pt) in [(5, 27), (12, 31), (20, 34), (28, 31), (35, 27), (16, 26), (24, 26)].enumerated() {
            p.lamp(CGFloat(pt.0), CGFloat(pt.1) + lift, 0.8 + 0.25 * CGFloat(sin(f.t * 2 + Double(k))), bio)
        }
    }

    /// Wisp: a dragonfly face, two great compound eyes and blurred wings.
    static func wisp(_ p: Pen, _ team: RGB, _ f: Pose) {
        for side in [-1.0, 1.0] as [CGFloat] {
            for k in 0..<2 {
                let flap = CGFloat(sin(f.t * 24 + Double(k) * 1.5)) * 4
                p.solid(p.poly([(20 + side * 6, 16), (20 + side * 22, 26 + CGFloat(k) * 8 + flap), (20 + side * 21, 18 + CGFloat(k) * 6 + flap)]), membrane.alpha(0.25), outline: membrane.dark(0.3).alpha(0.35), contrast: 0.4)
            }
        }
        p.capsule((20, -2), (20, 10), 5, 4.4, shellHi.light(0.15))
        marking(p, 20, 4, 2, 1.4, team)
        p.ball(20, 18, 9, 8.6, shellHi.light(0.1), shine: 0.7)
        compoundEye(p, 13.2, 22, 6.4, 7.4, f)
        compoundEye(p, 26.8, 22, 6.4, 7.4, f)
        let o = f.mouth * 0.5
        if f.mouth > 0.05 { p.fill(p.ellipsePath(20, 11.6, 1.4, 0.6 + f.mouth * 1.2), RGB(0.25, 0.05, 0.12)) }
        for side in [-1.0, 1.0] as [CGFloat] {
            p.solid(p.poly([(20 + side * 1.4, 14), (20 + side * (3.2 + o * 2), 9.6 - o), (20 + side * 0.3, 11)]), bone.dark(0.1), lw: 0.4)
        }
    }

    /// Blightwing: a hunched flier with one great eye between bat-like wings and a toothed maw.
    static func blightwing(_ p: Pen, _ team: RGB, _ f: Pose) {
        let flap = CGFloat(sin(f.t * 2.2)) * 2.4
        for side in [-1.0, 1.0] as [CGFloat] {
            let wing = p.poly([(20 + side * 6, 20), (20 + side * 21, 38 + flap), (20 + side * 19, 26 + flap), (20 + side * 22, 16 + flap), (20 + side * 8, 12)])
            p.solid(wing, shell.light(0.08), contrast: 1.2)
            p.line((20 + side * 7, 18), (20 + side * 20.5, 36 + flap), shell.dark(0.4), 0.6)
            p.line((20 + side * 7, 16), (20 + side * 21, 17 + flap), shell.dark(0.4), 0.6)
        }
        p.ball(20, 3, 10, 7, meat.dark(0.2), shine: 0.4)
        p.glow(20, 4, 8, bio.alpha(0.5))
        marking(p, 20, 6.5, 3, 1.4, team)
        let head = p.poly([(11, 14), (14, 26), (20, 33), (26, 26), (29, 14), (20, 9)])
        p.solid(head, shell.light(0.06), contrast: 1.3)
        plates(p, 20, 20, 9, 12, n: 3, shell)
        beadEye(p, 20, 22, 4.0, f)
        let o = f.mouth
        p.fill(p.ellipsePath(20, 13, 3.4, 0.6 + o * 2), RGB(0.22, 0.04, 0.1))
        if o > 0.05 { p.glow(20, 13, 3 + o * 3, bio.alpha(0.6)) }
        teeth(p, (16.8, 13.6), (23.2, 13.6), n: 5, len: 1.2 + o * 0.4, dir: -1)
        teeth(p, (17.4, 12.2 - o * 1.6), (22.6, 12.2 - o * 1.6), n: 4, len: 1.0, dir: 1)
    }
}
