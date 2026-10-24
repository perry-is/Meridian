import CoreGraphics
import Foundation

/// Animated unit portraits for the selection panel: a head-and-shoulders bust, more detailed than the unit
/// sprite, that looks around, blinks and talks. Drawn every frame into a 40×40 design grid (origin bottom-left).
///  - Concord: people, each unit with its own headgear, face and kit (vehicles and aircraft show their crew).
///  - Lattice: machine heads with lenses that track and shutter, and grilles that light up as they speak.
///  - Brood: carapace heads with clusters of glossy eyes and mandibles that part to chitter.
enum PortraitArt {
    /// What the face is doing this frame.
    struct Pose {
        /// Where the eyes are looking (-1…1 each axis; +x is the viewer's right, +y up).
        var look = CGPoint.zero
        var blink: CGFloat = 0
        /// Mouth / mandible / grille opening (0…1).
        var mouth: CGFloat = 0
        var t: Double = 0
    }

    static func draw(_ p: Pen, unit id: String, team: RGB, pose: Pose) {
        switch id.first {
        case "m": lattice(p, id, team, pose)
        case "a": brood(p, id, team, pose)
        default: humanBackdrop(p, pose); human(p, humanSpec(id), team, pose)
        }
    }

    // MARK: Idle animation

    /// Deterministic hash in 0…1.
    static func hash(_ i: Int, _ s: Int) -> Double { Double(hnoise(i, s, 911)) }

    /// Eyes wander between held glances, easing between them; often back to centre.
    static func look(_ t: Double, seed: Int) -> CGPoint {
        let period = 2.1 + hash(seed, 3) * 0.8
        let u = t / period + hash(seed, 5) * 10
        let i = Int(floor(u)), f = u - floor(u)
        func target(_ k: Int) -> CGPoint {
            if hash(k, seed) < 0.35 { return .zero }
            return CGPoint(x: hash(k, seed &+ 1) * 2 - 1, y: (hash(k, seed &+ 2) * 2 - 1) * 0.6)
        }
        let a = target(i - 1), b = target(i)
        let e = CGFloat(min(1, f / 0.12)), s = e * e * (3 - 2 * e)
        return CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
    }

    /// A blink every few seconds (sometimes a double blink); `offset` staggers separate eyes.
    static func blink(_ t: Double, seed: Int, offset: Double = 0) -> CGFloat {
        let period = 3.4 + hash(seed, 7) * 1.4
        let u = (t + offset) / period
        let i = Int(floor(u))
        let at = hash(i, seed &+ 9) * 0.6
        let local = (u - floor(u) - at) * period
        func pulse(_ x: Double) -> CGFloat { x < 0 || x > 0.16 ? 0 : CGFloat(1 - abs(x - 0.08) / 0.08) }
        var b = pulse(local)
        if hash(i, seed &+ 11) < 0.25 { b = max(b, pulse(local - 0.24)) }
        return b
    }

    // MARK: - Concord

    enum Headgear { case hardhat, cap, helmet, heavy, scope, antenna, medic, hood, crewCap, earDefenders, pilot, pilotOpen, beret }
    struct HumanSpec {
        var skin: RGB
        var hair: RGB
        var gear: Headgear
        var uniform = UnitArt.olive
        var beard = false
        var scar = false
        var goggles = false
        var iris = RGB(0.30, 0.22, 0.14)
        var jaw: CGFloat = 1
        var prop: Prop = .none
    }
    /// The unit's signature kit in frame, so the face reads as that unit.
    enum Prop { case none, wrench, antenna, rifle, shield, rocket, launcher, sniper, rollbar, hatch, cockpit }

    static let skins = [RGB(0.95, 0.80, 0.68), RGB(0.87, 0.68, 0.54), RGB(0.74, 0.54, 0.40), RGB(0.56, 0.38, 0.27), RGB(0.40, 0.27, 0.20)]
    static let hairs = [RGB(0.16, 0.11, 0.08), RGB(0.42, 0.28, 0.15), RGB(0.70, 0.55, 0.32), RGB(0.10, 0.09, 0.09), RGB(0.55, 0.53, 0.50)]

    static func humanSpec(_ id: String) -> HumanSpec {
        switch id {
        case "h_engineer": return HumanSpec(skin: skins[1], hair: hairs[1], gear: .hardhat, uniform: RGB(0.55, 0.48, 0.30), beard: true, goggles: true, prop: .wrench)
        case "h_pathfinder": return HumanSpec(skin: skins[2], hair: hairs[0], gear: .cap, uniform: RGB(0.45, 0.47, 0.34), iris: RGB(0.25, 0.40, 0.25), prop: .antenna)
        case "h_ranger": return HumanSpec(skin: skins[0], hair: hairs[2], gear: .helmet, iris: RGB(0.28, 0.45, 0.65), prop: .rifle)
        case "h_breacher": return HumanSpec(skin: skins[3], hair: hairs[3], gear: .heavy, uniform: RGB(0.36, 0.38, 0.32), scar: true, jaw: 1.15, prop: .shield)
        case "h_lancer": return HumanSpec(skin: skins[1], hair: hairs[3], gear: .scope, uniform: RGB(0.40, 0.42, 0.33), prop: .rocket)
        case "h_skyguard": return HumanSpec(skin: skins[4], hair: hairs[3], gear: .antenna, uniform: RGB(0.38, 0.44, 0.40), prop: .launcher)
        case "h_medic": return HumanSpec(skin: skins[2], hair: hairs[1], gear: .medic, uniform: RGB(0.48, 0.52, 0.48), iris: RGB(0.35, 0.25, 0.15))
        case "h_ghost": return HumanSpec(skin: skins[0], hair: hairs[3], gear: .hood, uniform: RGB(0.18, 0.19, 0.20), prop: .sniper)
        case "h_buggy": return HumanSpec(skin: skins[3], hair: hairs[0], gear: .beret, uniform: RGB(0.50, 0.42, 0.30), goggles: true, prop: .rollbar)
        case "h_bastion": return HumanSpec(skin: skins[1], hair: hairs[4], gear: .crewCap, uniform: RGB(0.34, 0.36, 0.30), beard: true, scar: true, jaw: 1.1, prop: .hatch)
        case "h_mortar": return HumanSpec(skin: skins[4], hair: hairs[0], gear: .earDefenders, uniform: RGB(0.42, 0.44, 0.34), prop: .hatch)
        case "h_minelayer": return HumanSpec(skin: skins[2], hair: hairs[2], gear: .hardhat, uniform: RGB(0.46, 0.40, 0.28), iris: RGB(0.28, 0.42, 0.30), prop: .hatch)
        case "h_kestrel": return HumanSpec(skin: skins[0], hair: hairs[1], gear: .pilot, uniform: RGB(0.36, 0.40, 0.44), prop: .cockpit)
        case "h_harrier": return HumanSpec(skin: skins[3], hair: hairs[0], gear: .pilot, uniform: RGB(0.30, 0.33, 0.30), prop: .cockpit)
        case "h_dropship": return HumanSpec(skin: skins[1], hair: hairs[2], gear: .pilotOpen, uniform: RGB(0.40, 0.42, 0.44), beard: true, prop: .cockpit)
        default: return HumanSpec(skin: skins[1], hair: hairs[1], gear: .helmet)
        }
    }

    static func human(_ p: Pen, _ s: HumanSpec, _ team: RGB, _ f: Pose) {
        let dx = f.look.x * 1.5, dy = f.look.y * 0.8
        let hx = 20 + dx * 0.35, hy = 22 + dy * 0.25
        let fx = 20 + dx, fy = 21.6 + dy
        let skin = s.skin, ink = Pen.ink

        // Shoulders, collar and kit.
        let u = s.uniform
        propBehind(p, s, team, f)
        p.solid(p.poly([(0, 0), (40, 0), (39, 6.5), (31, 11.5), (9, 11.5), (1, 6.5)]), u)
        p.solid(p.poly([(1, 6.5), (9, 11.5), (12, 10.5), (6, 4.5), (0.5, 3)]), u.light(0.12), contrast: 0.5)
        p.solid(p.poly([(39, 6.5), (31, 11.5), (28, 10.5), (34, 4.5), (39.5, 3)]), u.dark(0.12), contrast: 0.5)
        for (x, c) in [(5.0, team), (35.0, team.dark(0.2))] as [(CGFloat, RGB)] {
            p.ball(x, 7.6, 4.4, 2.8, c.dark(0.15), shine: 0.4)
            p.lamp(x + (x < 20 ? 1.0 : -1.0), 8.0, 0.55, RGB(0.95, 0.3, 0.85))
        }
        p.seam((13, 0), (14, 8), u); p.seam((27, 0), (26, 8), u)
        if s.gear == .pilot || s.gear == .pilotOpen {
            p.solid(p.roundRectPath(15, 2, 10, 4.5, 1.2), UnitArt.darkSteel)
            p.lamp(17.5, 4.2, 0.45, RGB(0.4, 1, 0.5)); p.lamp(20, 4.2, 0.45, UnitArt.amber)
        } else if s.gear == .medic {
            p.solid(p.roundRectPath(3, 2, 6.5, 4, 1), RGB(0.92, 0.92, 0.9))
            p.fill(p.poly([(5.6, 2.6), (6.9, 2.6), (6.9, 5.4), (5.6, 5.4)]), team); p.fill(p.poly([(4.2, 3.4), (8.3, 3.4), (8.3, 4.6), (4.2, 4.6)]), team)
        } else {
            p.solid(p.roundRectPath(29, 1.5, 6, 4, 1), u.dark(0.25))
            p.rivets([(30.2, 4.6), (33.8, 4.6)], u)
        }

        // Neck and ears.
        p.solid(p.roundRectPath(hx - 3.4, 10, 6.8, 6, 2.4), skin.dark(0.18), contrast: 0.6)
        p.solid(p.poly([(12.5, 11.4), (16.5, 13.6), (20, 11.6), (23.5, 13.6), (27.5, 11.4), (26, 10), (14, 10)]), u.dark(0.2))
        let earX = 7.6 * s.jaw
        if s.gear != .hood && s.gear != .pilot {
            p.ball(hx - earX - dx * 0.25, hy - 0.4, 1.3, 2.1, skin.dark(0.1), shine: 0)
            p.ball(hx + earX - dx * 0.25, hy - 0.4, 1.3, 2.1, skin.dark(0.2), shine: 0)
        }

        // Head.
        let head = CGMutablePath()
        let w = 7.6 * s.jaw
        head.move(to: CGPoint(x: hx - w, y: hy + 1))
        head.addCurve(to: CGPoint(x: hx, y: hy + 9.6), control1: CGPoint(x: hx - w, y: hy + 7), control2: CGPoint(x: hx - 4.5, y: hy + 9.6))
        head.addCurve(to: CGPoint(x: hx + w, y: hy + 1), control1: CGPoint(x: hx + 4.5, y: hy + 9.6), control2: CGPoint(x: hx + w, y: hy + 7))
        head.addCurve(to: CGPoint(x: hx + dx * 0.3, y: hy - 9.2), control1: CGPoint(x: hx + w, y: hy - 4.5), control2: CGPoint(x: hx + 4 + dx * 0.3, y: hy - 9.2))
        head.addCurve(to: CGPoint(x: hx - w, y: hy + 1), control1: CGPoint(x: hx - 4 + dx * 0.3, y: hy - 9.2), control2: CGPoint(x: hx - w, y: hy - 4.5))
        head.closeSubpath()
        p.ball(hx, hy, w, 9.4, skin, outline: nil, shine: 0.18)
        p.ctx.saveGState(); p.ctx.addPath(head); p.ctx.clip()
        p.ball(hx, hy, w + 0.4, 9.8, skin, outline: nil, shine: 0.2)
        p.fill(p.ellipsePath(fx - 4.6, fy - 2.4, 1.7, 1.0), RGB(0.9, 0.35, 0.3, 0.12))
        p.fill(p.ellipsePath(fx + 4.6, fy - 2.4, 1.7, 1.0), RGB(0.9, 0.35, 0.3, 0.12))
        p.fill(p.ellipsePath(hx + w * 0.9, hy - 1, 3, 9), skin.dark(0.35).alpha(0.35))
        if s.beard {
            let b = CGMutablePath()
            b.move(to: CGPoint(x: hx - w, y: hy - 0.5)); b.addLine(to: CGPoint(x: hx + w, y: hy - 0.5))
            b.addLine(to: CGPoint(x: hx + w, y: hy - 10)); b.addLine(to: CGPoint(x: hx - w, y: hy - 10)); b.closeSubpath()
            p.ctx.saveGState(); p.ctx.addPath(b); p.ctx.clip()
            p.fill(p.ellipsePath(fx, fy - 6, w * 0.95, 4.6), s.hair.alpha(0.8))
            p.fill(p.ellipsePath(fx, fy - 4.6, 2.6, 1.1), skin.dark(0.05))
            p.ctx.restoreGState()
        }
        p.ctx.restoreGState()
        p.stroke(head, ink, 0.75)

        // Hair visible below headgear.
        if s.gear != .hood && s.gear != .pilot {
            p.fill(p.poly([(hx - w + 0.2, hy + 2), (hx - w + 1.5, hy + 5.5), (hx - w + 2.6, hy + 2.6)]), s.hair)
            p.fill(p.poly([(hx + w - 0.2, hy + 2), (hx + w - 1.5, hy + 5.5), (hx + w - 2.6, hy + 2.6)]), s.hair)
        }

        // Face.
        let visor = s.gear == .pilot
        if !visor {
            let talkBrow = f.mouth * 0.4
            for side in [-1.0, 1.0] as [CGFloat] {
                let ex = fx + side * 3.2, ey = fy + 0.8
                eye(p, ex, ey, f, iris: s.iris, skin: skin)
                p.line((ex - 1.9, ey + 2.0 + talkBrow - (side < 0 ? 0 : 0.2)), (ex + 1.9, ey + 2.3 + talkBrow), s.hair.dark(0.2), 0.95)
            }
            if s.scar { p.line((fx + 4.4, fy + 3.4), (fx + 3.0, fy - 1.6), RGB(0.7, 0.35, 0.3, 0.7), 0.5) }
            if s.gear == .hood {
                // Tri-lens night goggles over the eyes and a breathing mask.
                p.solid(p.roundRectPath(fx - 6.4, fy - 0.8, 12.8, 3.6, 1.6), RGB(0.12, 0.12, 0.13))
                for (k, ox) in [-3.3, 3.3, 0].enumerated() {
                    let r: CGFloat = k == 2 ? 0.9 : 1.35
                    p.lamp(fx + CGFloat(ox) + f.look.x * 0.3, fy + 1 + (k == 2 ? 1.6 : 0), r * (1 - f.blink * 0.7), UnitArt.cyan)
                }
            }
        }

        // Nose.
        if !visor {
            p.fill(p.poly([(fx + 0.2, fy + 1.2), (fx + 1.4, fy - 2.2), (fx - 0.2, fy - 2.6)]), skin.dark(0.12).alpha(0.7))
            p.line((fx - 0.4, fy - 2.6), (fx + 1.3, fy - 2.4), skin.dark(0.4), 0.45)
        }

        // Mouth (or mask).
        let my = fy - 5.2
        if s.gear == .hood || visor {
            let mp = p.roundRectPath(fx - 3.6, my - 2.4, 7.2, 4.2, 1.8)
            p.solid(mp, RGB(0.16, 0.17, 0.19))
            for k in 0..<3 { p.line((fx - 1.8, my - 1.3 + CGFloat(k) * 0.9), (fx + 1.8, my - 1.3 + CGFloat(k) * 0.9), RGB(0.05, 0.05, 0.06), 0.4) }
            p.lamp(fx + 2.6, my + 0.6, 0.35 + f.mouth * 0.25, f.mouth > 0.1 ? RGB(0.4, 1, 0.5) : RGB(0.25, 0.5, 0.3))
        } else if f.mouth > 0.06 {
            let h = 0.35 + f.mouth * 1.5
            p.fill(p.ellipsePath(fx + 0.1, my, 2.0 + f.mouth * 0.3, h), RGB(0.28, 0.08, 0.08))
            p.ctx.saveGState(); p.ctx.addPath(p.ellipsePath(fx + 0.1, my, 2.0 + f.mouth * 0.3, h)); p.ctx.clip()
            p.fill(p.roundRectPath(fx - 1.6, my + h - 0.55, 3.4, 0.7, 0.3), RGB(0.95, 0.93, 0.88))
            p.ctx.restoreGState()
            p.stroke(p.ellipsePath(fx + 0.1, my, 2.0 + f.mouth * 0.3, h), skin.dark(0.45), 0.4)
        } else {
            let m = CGMutablePath()
            m.move(to: CGPoint(x: fx - 2.0, y: my + 0.15)); m.addQuadCurve(to: CGPoint(x: fx + 2.1, y: my + 0.25), control: CGPoint(x: fx, y: my - 0.45))
            p.stroke(m, skin.dark(0.5), 0.6)
        }

        headgear(p, s, team, hx: hx, hy: hy, fx: fx, fy: fy, w: w, f: f)
        propFront(p, s, team, f)
    }

    static func humanBackdrop(_ p: Pen, _ f: Pose) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [RGB(0.22, 0.25, 0.18).cg, RGB(0.05, 0.06, 0.05).cg] as CFArray, locations: [0, 1])!
        p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: 13, y: 30), startRadius: 0, endCenter: CGPoint(x: 20, y: 20), endRadius: 34, options: [.drawsAfterEndLocation])
        for k in 0..<9 { let x = CGFloat(k) * 5; p.line((x, 0), (x, 40), RGB(0.6, 0.7, 0.5, 0.05), 0.3); p.line((0, x), (40, x), RGB(0.6, 0.7, 0.5, 0.05), 0.3) }
    }

    static func propBehind(_ p: Pen, _ s: HumanSpec, _ team: RGB, _ f: Pose) {
        switch s.prop {
        case .antenna:
            p.solid(p.roundRectPath(1, 4, 7, 9, 1.2), s.uniform.dark(0.3))
            p.line((5, 12), (2.5, 39), UnitArt.darkSteel, 0.9)
            p.lamp(2.5, 39, 0.6, sin(f.t * 4) > 0.4 ? RGB(1, 0.3, 0.2) : RGB(0.4, 0.15, 0.1))
        case .rocket:
            p.ctx.saveGState(); p.ctx.translateBy(x: 20, y: 14); p.ctx.rotate(by: 0.36)
            p.tube(-26, 26, 0, 3.6, s.uniform.light(0.05), cap: false)
            p.line((-22, 1.2), (20, 1.2), team, 1.1)
            p.ball(26, 0, 2.2, 3.8, RGB(0.7, 0.15, 0.12), shine: 0.5)
            p.ctx.restoreGState()
        case .launcher:
            p.ctx.saveGState(); p.ctx.translateBy(x: 5, y: 10); p.ctx.rotate(by: 0.25)
            p.block(-4, 0, 9, 22, depth: 2.4, s.uniform.dark(0.1))
            p.line((-3, 4), (-3, 18), team, 1.1)
            for k in 0..<2 { p.lamp(-1.5 + CGFloat(k) * 3.6, 19.5, 0.7, RGB(1, 0.55, 0.15)) }
            p.ctx.restoreGState()
        case .rollbar:
            let bar = CGMutablePath()
            bar.move(to: CGPoint(x: 3, y: 6)); bar.addLine(to: CGPoint(x: 5, y: 33)); bar.addQuadCurve(to: CGPoint(x: 35, y: 33), control: CGPoint(x: 20, y: 38)); bar.addLine(to: CGPoint(x: 37, y: 6))
            p.stroke(bar, RGB(0.04, 0.04, 0.05), 3.2); p.stroke(bar, UnitArt.darkSteel.light(0.1), 2.0)
        default: break
        }
    }

    static func propFront(_ p: Pen, _ s: HumanSpec, _ team: RGB, _ f: Pose) {
        switch s.prop {
        case .wrench:
            p.capsule((31, -1), (36, 9), 1.0, 0.9, UnitArt.chrome.dark(0.1))
            p.solid(p.poly([(34.4, 8), (38.6, 9.4), (38.4, 12.6), (36.6, 11), (35.2, 12.2)]), UnitArt.chrome, lw: 0.5)
        case .rifle, .sniper:
            let L: CGFloat = s.prop == .sniper ? 48 : 44
            p.ctx.saveGState(); p.ctx.translateBy(x: 26, y: 1); p.ctx.rotate(by: 0.42)
            p.block(-4, -2, 12, 4, depth: 1.2, RGB(0.18, 0.18, 0.19))
            p.tube(6, L - 26, 0, 1.0, UnitArt.darkSteel)
            if s.prop == .sniper { p.tube(0, 8, 3, 1.0, RGB(0.12, 0.12, 0.13)); p.lamp(8, 3, 0.5, UnitArt.cyan) }
            p.ctx.restoreGState()
        case .shield:
            let sh = p.poly([(29, -1), (43, -1), (43, 31), (31, 27)])
            p.grad(sh, RGB(0.55, 0.65, 0.75, 0.55), RGB(0.30, 0.38, 0.48, 0.65), from: CGPoint(x: 30, y: 27), to: CGPoint(x: 42, y: 0))
            for y in [6.0, 20.0] as [CGFloat] { p.line((30, y), (43, y + 0.6), team, 1.4) }
            p.line((32, 25), (34, 2), RGB(1, 1, 1, 0.45), 0.6)
        case .hatch:
            p.stroke(p.ellipsePath(20, 3, 19, 4.4), RGB(0.04, 0.04, 0.05), 2.6)
            p.block(-2, -3, 44, 5.6, depth: 2.6, s.uniform.dark(0.18))
            p.line((-2, 0.4), (42, 0.4), team, 1.4)
            p.rivets([(4, 1.8), (12, 1.8), (28, 1.8), (36, 1.8)], s.uniform.dark(0.18))
        case .cockpit:
            p.solid(p.poly([(-1, -1), (41, -1), (41, 3.6), (-1, 3.6)]), RGB(0.10, 0.11, 0.12), lw: 0.4)
            for k in 0..<6 { p.lamp(6 + CGFloat(k) * 5.6, 1.4, 0.45, k % 2 == 0 ? UnitArt.cyan : UnitArt.amber) }
            p.solid(p.poly([(-1, 3), (3, 3), (9, 41), (4, 41)]), RGB(0.16, 0.17, 0.19), lw: 0.5)
            p.solid(p.poly([(41, 3), (37, 3), (31, 41), (36, 41)]), RGB(0.16, 0.17, 0.19), lw: 0.5)
            p.fill(p.poly([(6, 41), (12, 41), (30, 3), (24, 3)]), RGB(1, 1, 1, 0.07))
        case .rollbar:
            let ws = p.poly([(-1, -1), (41, -1), (41, 4), (-1, 4)])
            p.solid(ws, RGB(0.30, 0.26, 0.18), lw: 0.4)
            p.line((-1, 2.4), (41, 2.4), team, 1.3)
        default: break
        }
    }

    static func eye(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ f: Pose, iris: RGB, skin: RGB) {
        let open = 1 - f.blink
        let ew: CGFloat = 1.75, eh: CGFloat = 1.15 * open
        if open > 0.1 {
            let path = p.ellipsePath(x, y, ew, eh)
            p.fill(path, RGB(0.97, 0.96, 0.93))
            p.ctx.saveGState(); p.ctx.addPath(path); p.ctx.clip()
            let ix = x + f.look.x * 0.75, iy = y + f.look.y * 0.35
            p.dot(ix, iy, 0.95, iris)
            p.dot(ix, iy, 0.48, RGB(0.04, 0.04, 0.05))
            p.dot(ix - 0.32, iy + 0.35, 0.24, RGB(1, 1, 1, 0.9))
            p.fill(p.ellipsePath(x, y + eh * 0.9, ew * 1.2, eh * 0.45), skin.dark(0.3).alpha(0.35))
            p.ctx.restoreGState()
        } else {
            p.fill(p.ellipsePath(x, y, ew, 0.5), skin.dark(0.08))
        }
        let lid = CGMutablePath()
        lid.move(to: CGPoint(x: x - ew - 0.15, y: y - eh * 0.1))
        lid.addQuadCurve(to: CGPoint(x: x + ew + 0.15, y: y - eh * 0.05), control: CGPoint(x: x, y: y + eh * 1.9))
        p.stroke(lid, RGB(0.10, 0.06, 0.05, 0.9), 0.55)
    }

    /// Team band wrapped round a helmet, as on the unit sprites.
    static func helmetBand(_ p: Pen, hx: CGFloat, y: CGFloat, wid: CGFloat, lean: CGFloat, _ team: RGB) {
        let b = CGMutablePath()
        b.move(to: CGPoint(x: hx - wid + 0.4, y: y)); b.addQuadCurve(to: CGPoint(x: hx + wid - 0.4, y: y), control: CGPoint(x: hx + lean * 0.4, y: y + 1.6))
        p.stroke(b, RGB(0.03, 0.03, 0.05), 2.2); p.stroke(b, team, 1.5)
        let h = CGMutablePath()
        h.move(to: CGPoint(x: hx - wid + 1.6, y: y + 0.5)); h.addQuadCurve(to: CGPoint(x: hx + 1, y: y + 1.1), control: CGPoint(x: hx - wid * 0.4, y: y + 1.3))
        p.stroke(h, team.light(0.5).alpha(0.7), 0.4)
    }

    static func headgear(_ p: Pen, _ s: HumanSpec, _ team: RGB, hx: CGFloat, hy: CGFloat, fx: CGFloat, fy: CGFloat, w: CGFloat, f: Pose) {
        let lean = (fx - 20) * 0.4
        func dome(_ c: RGB, rim: CGFloat, top: CGFloat, width: CGFloat) {
            let d = CGMutablePath()
            d.move(to: CGPoint(x: hx - width, y: hy + rim))
            d.addCurve(to: CGPoint(x: hx + lean * 0.4, y: hy + top), control1: CGPoint(x: hx - width, y: hy + top - 1.5), control2: CGPoint(x: hx - width * 0.55 + lean * 0.4, y: hy + top))
            d.addCurve(to: CGPoint(x: hx + width, y: hy + rim), control1: CGPoint(x: hx + width * 0.55 + lean * 0.4, y: hy + top), control2: CGPoint(x: hx + width, y: hy + top - 1.5))
            d.closeSubpath()
            p.ctx.saveGState(); p.ctx.addPath(d); p.ctx.clip()
            p.ball(hx - 1 + lean * 0.3, hy + rim + 2.5, width * 1.1, (top - rim) * 1.15, c, outline: nil, shine: 0.6)
            p.ctx.restoreGState()
            p.stroke(d, Pen.ink, 0.75)
        }
        switch s.gear {
        case .hardhat:
            dome(RGB(0.95, 0.72, 0.18), rim: 4.2, top: 12.2, width: w + 1.2)
            p.solid(p.roundRectPath(hx - w - 2.8, hy + 3.4, (w + 2.8) * 2, 1.6, 0.8), RGB(0.95, 0.72, 0.18).dark(0.1))
            p.fill(p.roundRectPath(hx - 1 + lean * 0.4, hy + 5, 2, 6.5, 1), RGB(1, 0.85, 0.4, 0.6))
            helmetBand(p, hx: hx, y: hy + 6.0, wid: w + 1.2, lean: lean, team)
            if s.goggles {
                p.solid(p.roundRectPath(hx - 6 + lean, hy + 5.8, 12, 2.6, 1.2), RGB(0.2, 0.2, 0.22))
                p.ball(hx - 2.8 + lean, hy + 7.1, 1.9, 1.3, RGB(0.45, 0.75, 0.85), shine: 1)
                p.ball(hx + 2.8 + lean, hy + 7.1, 1.9, 1.3, RGB(0.45, 0.75, 0.85), shine: 1)
            }
        case .cap, .beret:
            if s.gear == .beret {
                p.ball(hx - 1 + lean * 0.5, hy + 8.4, w + 1.4, 3.2, team.dark(0.25), shine: 0.3)
                p.solid(p.roundRectPath(hx - w - 0.2, hy + 5.6, (w + 0.2) * 2, 1.6, 0.8), RGB(0.30, 0.22, 0.14))
                p.lamp(hx + w - 2.5, hy + 7.2, 0.5, UnitArt.amber)
            } else {
                dome(s.uniform.light(0.08), rim: 4.8, top: 10.8, width: w + 0.6)
                p.solid(p.poly([(hx - w + 1 + lean, hy + 5.2), (hx + w + 3.5 + lean, hy + 4.6), (hx + w + 3.2 + lean, hy + 3.4), (hx - w + 1.4 + lean, hy + 4.0)]), s.uniform.dark(0.15))
                p.fill(p.poly([(hx - 1.5 + lean * 0.5, hy + 8.2), (hx + 1.5 + lean * 0.5, hy + 8.2), (hx + 1.5 + lean * 0.5, hy + 9.3), (hx - 1.5 + lean * 0.5, hy + 9.3)]), team)
            }
            if s.goggles {
                p.solid(p.roundRectPath(hx - 6 + lean, hy + 5.2, 12, 2.6, 1.2), RGB(0.24, 0.18, 0.12))
                p.ball(hx - 2.8 + lean, hy + 6.5, 1.9, 1.3, RGB(0.85, 0.55, 0.25), shine: 1)
                p.ball(hx + 2.8 + lean, hy + 6.5, 1.9, 1.3, RGB(0.85, 0.55, 0.25), shine: 1)
            }
        case .helmet, .heavy, .scope, .antenna, .medic, .earDefenders:
            let c = s.gear == .medic ? RGB(0.86, 0.86, 0.82) : (s.gear == .heavy ? UnitArt.darkSteel.light(0.1) : s.uniform.light(0.06))
            let wid = w + (s.gear == .heavy ? 2.4 : 1.4)
            dome(c, rim: s.gear == .heavy ? 3.6 : 4.4, top: s.gear == .heavy ? 12.6 : 11.6, width: wid)
            p.solid(p.roundRectPath(hx - wid - 0.6, hy + (s.gear == .heavy ? 2.8 : 3.8), (wid + 0.6) * 2, 1.5, 0.75), c.dark(0.18))
            helmetBand(p, hx: hx, y: hy + (s.gear == .heavy ? 6.4 : 7.0), wid: wid, lean: lean, team)
            // Chin strap.
            p.line((hx - w + 0.4, hy + 3.8), (hx - w + 2.6, hy - 6.4), RGB(0.18, 0.16, 0.12), 0.55)
            p.line((hx + w - 0.4, hy + 3.8), (hx + w - 2.6, hy - 6.4), RGB(0.18, 0.16, 0.12), 0.55)
            switch s.gear {
            case .heavy:
                // Blast shield, raised.
                p.solid(p.roundRectPath(hx - 6.5 + lean, hy + 6.4, 13, 3.4, 1.4), RGB(0.30, 0.40, 0.46, 0.95))
                p.line((hx - 5 + lean, hy + 9), (hx + 3 + lean, hy + 9.2), RGB(1, 1, 1, 0.45), 0.5)
                p.rivets([(hx - wid + 1, hy + 4.6), (hx + wid - 1, hy + 4.6)], c)
            case .scope:
                p.solid(p.roundRectPath(hx + w - 0.5, hy + 0.6, 2.4, 6, 1), UnitArt.darkSteel)
                p.limb((hx + w + 0.6, hy + 2.2), (fx + 3.4, fy + 1.2), UnitArt.darkSteel, 0.5)
                p.ball(fx + 3.4, fy + 0.9, 2.1, 2.1, RGB(0.15, 0.15, 0.17), shine: 0)
                p.lamp(fx + 3.4 + f.look.x * 0.5, fy + 0.9 + f.look.y * 0.3, 1.0, RGB(1, 0.35, 0.25))
            case .antenna:
                p.line((hx - wid + 2, hy + 9), (hx - wid - 1.5, hy + 16.5), UnitArt.darkSteel, 0.6)
                p.lamp(hx - wid - 1.5, hy + 16.5, 0.45, sin(f.t * 5) > 0.6 ? RGB(1, 0.3, 0.2) : RGB(0.5, 0.2, 0.15))
                p.solid(p.roundRectPath(hx + w - 0.4, hy - 1.2, 2.2, 4.4, 1.1), UnitArt.darkSteel)
                p.limb((hx + w + 0.6, hy - 0.6), (fx + 2.8, fy - 5.4), UnitArt.darkSteel, 0.4)
                p.dot(fx + 2.8, fy - 5.4, 0.6, UnitArt.darkSteel)
            case .medic:
                let vz = p.roundRectPath(fx - 6.4, fy - 0.6, 12.8, 3.2, 1.5)
                p.fill(vz, RGB(0.3, 1, 0.5, 0.35)); p.stroke(vz, RGB(0.15, 0.3, 0.2), 0.5)
                p.line((fx - 5, fy + 1.9), (fx - 1, fy + 2.1), RGB(1, 1, 1, 0.5), 0.4)
                p.solid(p.roundRectPath(hx - 2.4 + lean * 0.5, hy + 7.4, 4.8, 3.2, 0.6), RGB(0.97, 0.97, 0.95))
                p.fill(p.poly([(hx - 0.5 + lean * 0.5, hy + 7.8), (hx + 0.5 + lean * 0.5, hy + 7.8), (hx + 0.5 + lean * 0.5, hy + 10.2), (hx - 0.5 + lean * 0.5, hy + 10.2)]), team)
                p.fill(p.poly([(hx - 1.7 + lean * 0.5, hy + 8.5), (hx + 1.7 + lean * 0.5, hy + 8.5), (hx + 1.7 + lean * 0.5, hy + 9.5), (hx - 1.7 + lean * 0.5, hy + 9.5)]), team)
            case .earDefenders:
                for side in [-1.0, 1.0] as [CGFloat] {
                    p.ball(hx + side * (w + 0.6), hy, 2.2, 3.0, RGB(0.85, 0.55, 0.15), shine: 0.5)
                }
                p.line((hx - w - 0.6, hy + 2.8), (hx - w + 0.4, hy + 5), RGB(0.2, 0.2, 0.2), 0.7)
            default: break
            }
        case .crewCap:
            p.ball(hx - 0.6 + lean * 0.5, hy + 7.2, w + 1.4, 4.6, RGB(0.22, 0.20, 0.16), shine: 0.25)
            for k in 0..<3 { p.line((hx - w + 1 + CGFloat(k) * 4.5 + lean * 0.4, hy + 4.2), (hx - w + 2 + CGFloat(k) * 4.5 + lean * 0.4, hy + 11), RGB(0.12, 0.11, 0.09), 0.5) }
            // Headset with a boom mic.
            for side in [-1.0, 1.0] as [CGFloat] { p.ball(hx + side * (w + 0.4), hy - 0.2, 1.9, 2.6, RGB(0.14, 0.14, 0.15), shine: 0.4) }
            p.limb((hx - w - 0.6, hy - 1.6), (fx - 2.8, fy - 5.6), RGB(0.14, 0.14, 0.15), 0.45)
            p.dot(fx - 2.8, fy - 5.6, 0.7, RGB(0.14, 0.14, 0.15))
            p.fill(p.poly([(hx + 2 + lean, hy + 8.4), (hx + 6 + lean, hy + 8), (hx + 6 + lean, hy + 9.2), (hx + 2 + lean, hy + 9.6)]), team)
        case .hood:
            let hood = CGMutablePath()
            hood.move(to: CGPoint(x: hx - w - 2.6, y: hy - 9))
            hood.addCurve(to: CGPoint(x: hx + lean * 0.4, y: hy + 12.4), control1: CGPoint(x: hx - w - 3.6, y: hy + 4), control2: CGPoint(x: hx - 6 + lean * 0.4, y: hy + 12.4))
            hood.addCurve(to: CGPoint(x: hx + w + 2.6, y: hy - 9), control1: CGPoint(x: hx + 6 + lean * 0.4, y: hy + 12.4), control2: CGPoint(x: hx + w + 3.6, y: hy + 4))
            hood.addLine(to: CGPoint(x: hx + w - 0.6, y: hy - 9))
            hood.addCurve(to: CGPoint(x: hx + lean * 0.4, y: hy + 8.6), control1: CGPoint(x: hx + w, y: hy + 3), control2: CGPoint(x: hx + 5 + lean * 0.4, y: hy + 8.6))
            hood.addCurve(to: CGPoint(x: hx - w + 0.6, y: hy - 9), control1: CGPoint(x: hx - 5 + lean * 0.4, y: hy + 8.6), control2: CGPoint(x: hx - w, y: hy + 3))
            hood.closeSubpath()
            p.solid(hood, RGB(0.20, 0.21, 0.23))
            p.line((hx - w - 1.6, hy - 2), (hx - w - 0.4, hy + 6), team.alpha(0.7), 0.5)
        case .pilot, .pilotOpen:
            let c = RGB(0.82, 0.84, 0.86)
            dome(c, rim: s.gear == .pilot ? -1.4 : 3.2, top: 12.4, width: w + 2.2)
            if s.gear == .pilot {
                // Visor down: the eyes are only a reflection.
                let v = p.roundRectPath(hx - w - 0.4 + lean, fy - 1.6, (w + 0.4) * 2, 5.4, 2.4)
                p.grad(v, RGB(0.15, 0.20, 0.35), RGB(0.55, 0.40, 0.65), from: CGPoint(x: hx, y: fy + 3.8), to: CGPoint(x: hx, y: fy - 1.6))
                p.line((hx - w + 1.5 + lean, fy + 2.6), (hx - 1 + lean, fy + 3.2), RGB(1, 1, 1, 0.55), 0.6)
                p.fill(p.ellipsePath(fx - 3 + f.look.x * 0.6, fy + 0.7, 1.4, 0.7 * (1 - f.blink)), UnitArt.amber.alpha(0.35))
                p.fill(p.ellipsePath(fx + 3 + f.look.x * 0.6, fy + 0.7, 1.4, 0.7 * (1 - f.blink)), UnitArt.amber.alpha(0.35))
                p.limb((fx - 3.6, fy - 6.8), (hx - w - 1.6, hy - 4), RGB(0.25, 0.25, 0.27), 0.7)
            } else {
                p.solid(p.roundRectPath(hx - w - 0.2 + lean, hy + 5.6, (w + 0.2) * 2, 3.4, 1.6), RGB(0.30, 0.25, 0.45, 0.95))
                p.line((hx - w + 1.5 + lean, hy + 8.2), (hx + lean, hy + 8.6), RGB(1, 1, 1, 0.5), 0.5)
            }
            p.fill(p.poly([(hx - w - 1.6, hy + 4), (hx - w + 0.4, hy + 10.2), (hx - w + 1.4, hy + 9.6), (hx - w - 0.6, hy + 3.4)]), team)
        }
    }

}
