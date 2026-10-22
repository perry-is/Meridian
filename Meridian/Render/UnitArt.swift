import CoreGraphics
import MeridianCore

/// Original procedural unit sprites, drawn as a two-part rig so units can move like machines and creatures
/// rather than flat stickers:
///  - **base**: legs / wheels / treads / hull / torso and head, in 8 gait frames;
///  - **upper**: the part that acts — arms and weapon, a turret, a launcher, a striking head or a worker's
///    tool — drawn in the same canvas and rotated at runtime around `Rig.pivot` to aim, recoil, swing and strike.
/// Every unit faces right in a 40×40 design grid scaled to the unit's footprint; the renderer mirrors it.
/// Factions share a visual grammar:
///  - Concord (humans): olive/steel plating, angular shapes, amber visors, team-coloured stripes.
///  - Lattice (machines): gunmetal and chrome, hexagonal forms, cyan energy cores.
///  - Brood (aliens): chitin and flesh, curves and spines, bio-green glow.
enum UnitArt {
    static let olive = RGB(0.40, 0.45, 0.36), steel = RGB(0.58, 0.61, 0.62), amber = RGB(1.0, 0.75, 0.25)
    static let skin = RGB(0.86, 0.68, 0.55), darkSteel = RGB(0.28, 0.30, 0.31)
    static let gun = RGB(0.26, 0.28, 0.33), chrome = RGB(0.70, 0.74, 0.80), cyan = RGB(0.35, 0.95, 1.0)
    static let chitin = RGB(0.40, 0.24, 0.42), flesh = RGB(0.78, 0.45, 0.55), bio = RGB(0.55, 1.0, 0.35), bone = RGB(0.88, 0.84, 0.72)
    static let black = RGB(0.10, 0.10, 0.12)

    static func canvasSize(_ d: UnitDef) -> CGFloat { 26 + CGFloat(d.radius) * 68 }

    /// Gait frame (0-7) used by legs, wheels, treads and engines while drawing.
    nonisolated(unsafe) static var phase = 0
    static let frameCount = 8

    // MARK: Rig description

    struct Rig {
        enum Kind { case none, gun, turret, artillery, melee, head, tool, beamTool, biteTool, emitter }
        var kind: Kind = .none
        /// Rotation centre of the upper part, design grid.
        var pivot = CGPoint(x: 20, y: 20)
        /// Weapon tip at rest, design grid (for muzzle flashes and beams).
        var muzzle = CGPoint(x: 34, y: 20)
        var aimUp: CGFloat = 0.55
        var aimDown: CGFloat = 0.35
        /// Resting elevation when not engaged (artillery is carried raised).
        var rest: CGFloat = 0
        /// Recoil distance in design units.
        var kick: CGFloat = 1.6
        /// Ground covered per full gait cycle (tiles), so feet don't slide.
        var stride: Double = 0.6
        /// Worker tool variants that have their own upper texture.
        var tools: [String] = []
    }

    static func rig(_ id: String) -> Rig {
        var r = Rig()
        switch id {
        // Concord
        case "h_engineer": r.kind = .tool; r.pivot = CGPoint(x: 20.5, y: 20.5); r.muzzle = CGPoint(x: 31, y: 15); r.tools = ["wood", "ore", "build"]
        case "h_pathfinder": r.kind = .gun; r.pivot = CGPoint(x: 20.5, y: 20.5); r.muzzle = CGPoint(x: 33, y: 19.5); r.kick = 1
        case "h_ranger": r.kind = .gun; r.pivot = CGPoint(x: 20.5, y: 20.5); r.muzzle = CGPoint(x: 36, y: 19.6)
        case "h_breacher": r.kind = .gun; r.pivot = CGPoint(x: 21, y: 20); r.muzzle = CGPoint(x: 36.5, y: 18.6); r.kick = 2.6; r.stride = 0.55
        case "h_lancer": r.kind = .gun; r.pivot = CGPoint(x: 20, y: 23); r.muzzle = CGPoint(x: 37, y: 25); r.kick = 2.4; r.aimUp = 0.7
        case "h_skyguard": r.kind = .gun; r.pivot = CGPoint(x: 20, y: 22); r.muzzle = CGPoint(x: 32, y: 32); r.aimUp = 0.5; r.aimDown = 0.9; r.kick = 1.6
        case "h_medic": r.kind = .gun; r.pivot = CGPoint(x: 20.5, y: 20.5); r.muzzle = CGPoint(x: 31, y: 18.5); r.kick = 0.6
        case "h_ghost": r.kind = .gun; r.pivot = CGPoint(x: 20.5, y: 20.5); r.muzzle = CGPoint(x: 38.5, y: 20); r.kick = 2.2; r.stride = 0.7
        case "h_buggy": r.kind = .turret; r.pivot = CGPoint(x: 22, y: 21); r.muzzle = CGPoint(x: 36.5, y: 22.5); r.kick = 1.2; r.stride = 1.1
        case "h_bastion": r.kind = .turret; r.pivot = CGPoint(x: 20, y: 23.5); r.muzzle = CGPoint(x: 40, y: 25); r.kick = 3.2; r.aimUp = 0.3; r.aimDown = 0.2; r.stride = 1.2
        case "h_mortar": r.kind = .artillery; r.pivot = CGPoint(x: 18, y: 20); r.muzzle = CGPoint(x: 31, y: 21); r.rest = 0.75; r.aimUp = 1.1; r.aimDown = -0.4; r.kick = 3; r.stride = 1.2
        case "h_minelayer": r.kind = .turret; r.pivot = CGPoint(x: 27, y: 21); r.muzzle = CGPoint(x: 37.5, y: 21.5); r.kick = 1; r.stride = 1.2
        // Lattice
        case "m_fabricator": r.kind = .beamTool; r.pivot = CGPoint(x: 20, y: 17); r.muzzle = CGPoint(x: 33, y: 11); r.tools = ["wood", "ore", "build"]; r.stride = 0.9
        case "m_arc": r.kind = .emitter; r.pivot = CGPoint(x: 20, y: 24); r.muzzle = CGPoint(x: 20, y: 32); r.kick = 1; r.stride = 0.6
        case "m_shockframe": r.kind = .turret; r.pivot = CGPoint(x: 20, y: 22); r.muzzle = CGPoint(x: 37, y: 16); r.kick = 2; r.stride = 0.7
        case "m_piercer": r.kind = .turret; r.pivot = CGPoint(x: 16, y: 18); r.muzzle = CGPoint(x: 40.5, y: 19); r.kick = 3.4; r.aimUp = 0.3; r.aimDown = 0.25; r.stride = 0.8
        case "m_flak": r.kind = .turret; r.pivot = CGPoint(x: 20, y: 17); r.muzzle = CGPoint(x: 26, y: 32); r.aimUp = 0.4; r.aimDown = 0.8; r.kick = 1.6; r.stride = 1
        case "m_jammer": r.kind = .head; r.pivot = CGPoint(x: 20, y: 22); r.muzzle = CGPoint(x: 20, y: 34); r.stride = 0.6
        case "m_runner": r.kind = .turret; r.pivot = CGPoint(x: 22, y: 16); r.muzzle = CGPoint(x: 38.5, y: 17); r.kick = 1.2; r.stride = 1.2
        case "m_bulwark": r.kind = .turret; r.pivot = CGPoint(x: 20, y: 21); r.muzzle = CGPoint(x: 40, y: 21); r.kick = 2.6; r.aimUp = 0.3; r.aimDown = 0.25; r.stride = 0.9
        case "m_coil": r.kind = .artillery; r.pivot = CGPoint(x: 13, y: 17); r.muzzle = CGPoint(x: 39.5, y: 27); r.rest = 0.15; r.aimUp = 0.75; r.aimDown = -0.05; r.kick = 3.4; r.stride = 1.1
        case "m_suppress": r.kind = .emitter; r.pivot = CGPoint(x: 20, y: 22); r.muzzle = CGPoint(x: 20, y: 25); r.aimUp = 0; r.aimDown = 0; r.stride = 0.7
        // Brood
        case "a_weaver": r.kind = .biteTool; r.pivot = CGPoint(x: 26, y: 14); r.muzzle = CGPoint(x: 33.5, y: 14.5); r.tools = ["wood", "ore", "build"]; r.stride = 0.7
        case "a_mantis": r.kind = .melee; r.pivot = CGPoint(x: 20, y: 18); r.muzzle = CGPoint(x: 35, y: 26); r.stride = 0.7
        case "a_ravager": r.kind = .melee; r.pivot = CGPoint(x: 28, y: 15); r.muzzle = CGPoint(x: 40, y: 9); r.stride = 1
        case "a_spinecaster": r.kind = .gun; r.pivot = CGPoint(x: 17, y: 19); r.muzzle = CGPoint(x: 30, y: 31); r.aimUp = 0.5; r.aimDown = 0.5; r.kick = 1.6; r.stride = 0.8
        case "a_needleback": r.kind = .gun; r.pivot = CGPoint(x: 20, y: 18); r.muzzle = CGPoint(x: 23, y: 35); r.aimUp = 0.3; r.aimDown = 0.6; r.kick = 1.4; r.stride = 0.8
        case "a_skitter": r.kind = .melee; r.pivot = CGPoint(x: 26, y: 13); r.muzzle = CGPoint(x: 34, y: 13); r.stride = 0.9
        case "a_colossus": r.kind = .melee; r.pivot = CGPoint(x: 30, y: 17); r.muzzle = CGPoint(x: 40, y: 10); r.stride = 1.3
        case "a_rupturer": r.kind = .artillery; r.pivot = CGPoint(x: 24, y: 21); r.muzzle = CGPoint(x: 37, y: 31); r.rest = 0.2; r.aimUp = 0.6; r.aimDown = 0.1; r.kick = 2.4; r.stride = 1
        case "a_seeder": r.kind = .emitter; r.pivot = CGPoint(x: 20, y: 18); r.muzzle = CGPoint(x: 20, y: 30); r.aimUp = 0; r.aimDown = 0; r.stride = 0.7
        default: r.kind = .none
        }
        return r
    }

    // MARK: Rendering

    static func renderBase(_ d: UnitDef, team: RGB, frame: Int) -> CGImage {
        let S = canvasSize(d)
        phase = frame
        let img = Pen.image(S, S) { p in
            p.ctx.scaleBy(x: S / 40, y: S / 40)
            if d.domain == .ground { p.fill(p.ellipsePath(20, 4.5, 9 * min(1.6, 0.6 + CGFloat(d.radius)), 2.4), RGB(0.05, 0.04, 0.10, 0.35)) }
            base(d.id, p, team)
            if d.domain == .air { engineFlicker(p, frame) }
        }
        return Pen.lit(img, offset: 1.4)
    }

    static func renderUpper(_ d: UnitDef, team: RGB, variant: String = "") -> CGImage? {
        guard rig(d.id).kind != .none else { return nil }
        let S = canvasSize(d)
        let img = Pen.image(S, S) { p in
            p.ctx.scaleBy(x: S / 40, y: S / 40)
            upper(d.id, variant, p, team)
        }
        return Pen.lit(img, offset: 1.4)
    }

    /// Whole unit in one image (portraits, icons, art sheet).
    static func render(_ d: UnitDef, team: RGB, frame: Int = 0) -> CGImage {
        let S = canvasSize(d)
        let b = renderBase(d, team: team, frame: frame)
        guard let u = renderUpper(d, team: team) else { return b }
        return Pen.image(S, S) { p in
            p.ctx.draw(b, in: CGRect(x: 0, y: 0, width: S, height: S))
            p.ctx.draw(u, in: CGRect(x: 0, y: 0, width: S, height: S))
        }
    }

    // MARK: Gait helpers

    /// Phase angle for a limb with a cycle offset (0…1).
    static func ang(_ offset: CGFloat) -> CGFloat { (CGFloat(phase) / 8 + offset) * 2 * .pi }

    /// Two-segment leg with a knee. The foot travels an ellipse: it lifts while swinging forward.
    static func leg(_ p: Pen, hip: (CGFloat, CGFloat), len: CGFloat, stride: CGFloat, lift: CGFloat, _ c: RGB, _ w: CGFloat, offset: CGFloat, knee: CGFloat = 1) {
        let a = ang(offset)
        let fx = hip.0 + sin(a) * stride
        let fy = hip.1 - len + max(0, cos(a)) * lift
        let bend = knee * (1.0 + max(0, cos(a)) * 1.4)
        let m = ((hip.0 + fx) / 2 + bend, (hip.1 + fy) / 2)
        p.limb(hip, m, c, w)
        p.limb(m, (fx, fy), c, w * 0.88)
        p.fill(p.roundRectPath(fx - w * 0.6, fy - w * 0.45, w * 1.9, w * 0.9, w * 0.4), c.dark(0.25))
    }

    /// Insect / beast legs: pairs alternate (tripod-style for 6 legs).
    static func beastLegs(_ p: Pen, xs: [CGFloat], hipY: CGFloat, len: CGFloat, stride: CGFloat, _ c: RGB, _ w: CGFloat) {
        for (i, x) in xs.enumerated() {
            let a = ang(CGFloat(i % 2) * 0.5)
            let fx = x + sin(a) * stride, fy = hipY - len + max(0, cos(a)) * 1.6
            let m = ((x + fx) / 2 - 1.2, hipY + 1.2)
            p.limb((x, hipY), m, c, w)
            p.limb(m, (fx, fy), c, w * 0.8)
        }
    }

    static func wheel(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        p.ellipse(x, y, r, r, black)
        p.stroke(p.ellipsePath(x, y, r * 0.95, r * 0.95), RGB(0.22, 0.22, 0.24), 0.8)
        for k in 0..<3 {
            let a = CGFloat(phase) * .pi / 6 + CGFloat(k) * .pi / 3
            p.line((x - cos(a) * r * 0.75, y - sin(a) * r * 0.75), (x + cos(a) * r * 0.75, y + sin(a) * r * 0.75), RGB(0.42, 0.42, 0.45), 0.9)
        }
        p.dot(x, y, r * 0.38, RGB(0.6, 0.6, 0.62))
    }

    static func tracks(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        p.shade(p.roundRectPath(x, y, w, h, h / 2), RGB(0.16, 0.16, 0.17), outline: RGB(0.05, 0.05, 0.06, 0.9), lw: 0.8)
        let step: CGFloat = 3.2
        for i in 0..<Int(w / step) + 1 {
            let tx = x + 1.6 + (CGFloat(i) * step + CGFloat(phase) * step / 8).truncatingRemainder(dividingBy: w - 3)
            p.line((tx, y + 0.6), (tx, y + 1.6), RGB(0.42, 0.42, 0.44), 1)
            p.line((tx, y + h - 1.6), (tx, y + h - 0.6), RGB(0.42, 0.42, 0.44), 1)
        }
        for k in 0..<Int(w / 7) { wheel(p, x + 3.5 + CGFloat(k) * 7, y + h / 2, h * 0.32) }
    }

    static func engineFlicker(_ p: Pen, _ frame: Int) {
        let a: CGFloat = [0.25, 0.4, 0.3, 0.45, 0.28, 0.42, 0.33, 0.4][frame % 8]
        p.glow(20, 12, 9, RGB(1, 0.9, 0.7, a * 0.5))
    }

    // MARK: Concord parts

    /// Soldier lower body, torso and helmeted head. Arms and weapon belong to the upper part.
    static func soldier(_ p: Pen, body: RGB, tc: RGB, helmet: RGB, visor: RGB = amber, slim: Bool = false, bulky: Bool = false, pack: RGB? = nil) {
        let bw: CGFloat = bulky ? 6.6 : (slim ? 4.4 : 5.4)
        let lw: CGFloat = slim ? 1.9 : (bulky ? 2.6 : 2.3)
        leg(p, hip: (19.2, 11.5), len: 8.5, stride: 2.6, lift: 1.5, darkSteel.dark(0.25), lw, offset: 0.5)
        if let pk = pack { p.shade(p.roundRectPath(20 - bw - 3.2, 12.5, 4.6, 9, 1.6), pk) }
        p.shade(p.roundRectPath(20 - bw, 10.5, bw * 2, 12.5, 2.6), body)
        p.fill(p.roundRectPath(20 - bw, 11.3, bw * 2, 1.5, 0.6), darkSteel)
        p.fill(p.roundRectPath(20 - bw, 19.3, bw * 2, 2.6, 0.9), tc)
        p.highlight(19, 17, bw * 0.6, 3)
        leg(p, hip: (20.8, 11.5), len: 8.5, stride: 2.6, lift: 1.5, darkSteel, lw, offset: 0)
        p.ellipse(20.6, 26.2, 4, 3.8, skin.dark(0.12))
        p.shade(p.poly([(15.8, 25.8), (16.6, 30.4), (21, 31.6), (25, 29.8), (25.2, 26.6)]), helmet)
        p.fill(p.roundRectPath(21.2, 25.3, 4.2, 1.8, 0.8), visor)
        p.glow(24.6, 26.2, 2.2, visor.alpha(0.6))
    }

    /// Two arms reaching from the shoulder to a weapon's grips.
    static func arms(_ p: Pen, _ sleeve: RGB, back: (CGFloat, CGFloat), shoulder: (CGFloat, CGFloat) = (20.5, 20.5)) {
        p.limb(shoulder, back, sleeve.dark(0.25), 2.1)
        p.dot(back.0, back.1, 1.1, skin.dark(0.2))
    }
    static func frontArm(_ p: Pen, _ sleeve: RGB, _ hand: (CGFloat, CGFloat), shoulder: (CGFloat, CGFloat) = (20.5, 20.5)) {
        p.limb(shoulder, hand, sleeve, 2.2)
        p.dot(hand.0, hand.1, 1.15, skin.dark(0.1))
    }

    static func rifle(_ p: Pen, from x0: CGFloat, to x1: CGFloat, y: CGFloat, _ c: RGB, thick: CGFloat = 2.2) {
        p.shade(p.poly([(x0, y - 1.2), (x0 + 3, y - 0.6), (x1, y - 0.5), (x1, y + 0.6), (x0 + 3, y + 1.0), (x0, y + 1.4)]), c, lw: 0.7)
        p.box(x0 + 4, y - 0.4, (x1 - x0) * 0.4, thick * 0.6, c.light(0.12), r: 0.4)
        p.limb((x0 + (x1 - x0) * 0.45, y - 0.4), (x0 + (x1 - x0) * 0.45, y - 3.2), c.dark(0.2), 1.2)   // magazine
    }

    // MARK: Base layer

    static func base(_ id: String, _ p: Pen, _ tc: RGB) {
        switch id {
        // MARK: Concord
        case "h_engineer": soldier(p, body: RGB(0.62, 0.55, 0.35), tc: tc, helmet: RGB(1.0, 0.68, 0.1), pack: RGB(0.45, 0.42, 0.35))
        case "h_pathfinder":
            soldier(p, body: olive.mix(RGB(0.5, 0.55, 0.4), 0.4), tc: tc, helmet: olive.dark(0.1), slim: true, pack: olive.dark(0.2))
            p.limb((13.5, 21), (11.5, 37), darkSteel, 0.9); p.dot(11.5, 37.5, 1.2, RGB(1, 0.3, 0.3))
        case "h_ranger": soldier(p, body: olive, tc: tc, helmet: olive.dark(0.15), pack: olive.dark(0.25))
        case "h_breacher":
            soldier(p, body: olive.dark(0.1), tc: tc, helmet: darkSteel, bulky: true)
            p.shade(p.poly([(26, 7), (33.5, 9), (33.5, 27), (26, 29.5)]), steel.dark(0.1))   // shield
            p.line((27, 12), (32.6, 13), tc, 1.5); p.line((27, 24), (32.6, 24), tc, 1.5)
            p.fill(p.roundRectPath(28, 17, 3.5, 2, 0.6), RGB(0.15, 0.2, 0.25, 0.9))           // view slit
        case "h_lancer": soldier(p, body: olive, tc: tc, helmet: olive.dark(0.15))
        case "h_skyguard": soldier(p, body: olive.mix(steel, 0.3), tc: tc, helmet: steel, pack: steel.dark(0.25))
        case "h_medic":
            soldier(p, body: RGB(0.88, 0.88, 0.85), tc: tc, helmet: RGB(0.9, 0.9, 0.9), pack: RGB(0.92, 0.92, 0.9))
            p.box(13.2, 16, 3, 5, RGB(0.2, 0.75, 0.3), r: 0.3); p.box(12.2, 17, 5, 3, RGB(0.2, 0.75, 0.3), r: 0.3)
        case "h_ghost":
            soldier(p, body: RGB(0.18, 0.2, 0.24), tc: tc, helmet: RGB(0.12, 0.13, 0.16), visor: RGB(0.4, 1, 0.9), slim: true)
            p.shape([(14.5, 22), (11, 9), (16, 12)], RGB(0.14, 0.15, 0.18, 0.9))               // cloak tail
        case "h_buggy":
            wheel(p, 9.5, 6.5, 4.4); wheel(p, 30.5, 6.5, 4.4)
            p.shade(p.poly([(3.5, 9), (36.5, 9), (35, 15.5), (27, 19.5), (11, 19.5), (5, 15.5)]), olive)
            p.line((7, 12), (33, 12), tc, 2)
            p.shade(p.poly([(14, 19.5), (24, 19.5), (21, 24), (16, 24)]), RGB(0.25, 0.32, 0.38, 0.85))   // windscreen
            p.dot(35, 12, 1.2, amber)
        case "h_bastion":
            tracks(p, 1.5, 3, 37, 9.5)
            p.shade(p.poly([(2.5, 12), (37.5, 12), (35, 20.5), (5.5, 20.5)]), olive)
            p.line((6, 15.5), (34, 15.5), tc, 2.2)
            for x in [8.0, 14, 20, 26, 32] as [CGFloat] { p.dot(x, 18.5, 0.6, darkSteel) }
        case "h_mortar":
            tracks(p, 3, 3, 34, 8.5)
            p.shade(p.roundRectPath(4, 11, 30, 9, 1.5), olive)
            p.line((6, 14), (32, 14), tc, 2)
            p.box(26, 15.5, 7, 4, steel.dark(0.2))
            for k in 0..<3 { p.ellipse(28 + CGFloat(k) * 2, 21, 0.9, 1.6, RGB(0.6, 0.55, 0.3)) }   // shells
        case "h_minelayer":
            tracks(p, 3, 3, 34, 8.5)
            p.shade(p.roundRectPath(4, 11, 30, 11, 1.5), olive.mix(RGB(0.6, 0.5, 0.2), 0.3))
            for i in 0..<3 { p.ellipse(9 + CGFloat(i) * 6, 23.5, 2.6, 1.4, RGB(0.25, 0.25, 0.2)); p.dot(9 + CGFloat(i) * 6, 24.3, 0.5, RGB(1, 0.3, 0.2)) }
            p.line((6, 15), (32, 15), tc, 2)
        case "h_kestrel":
            p.shade(p.poly([(3, 18.5), (24, 17.5), (39, 20.5), (24, 23), (5, 23)]), steel)
            p.shade(p.poly([(13, 21.5), (25, 21.5), (9, 35)]), steel.dark(0.1))
            p.shade(p.poly([(13, 18.5), (24, 18.5), (10, 7)]), steel.dark(0.22))
            p.shape([(3, 19), (7, 27), (9, 21)], steel.dark(0.15))
            p.line((12, 21), (30, 20.5), tc, 1.8)
            p.ellipse(28, 21.6, 3.6, 1.6, cyan.mix(RGB(0.2, 0.3, 0.4), 0.5)); p.glow(3, 21, 5, RGB(1, 0.6, 0.2, 0.8))
        case "h_harrier":
            p.shade(p.poly([(2, 17), (34, 18), (39, 21), (34, 24), (3, 24.5)]), darkSteel.light(0.15))
            p.shade(p.poly([(11, 22.5), (26, 22.5), (15, 38)]), olive)
            p.shade(p.poly([(11, 18.5), (26, 18.5), (15, 2)]), olive.dark(0.15))
            p.ellipse(17, 31, 3, 1.8, darkSteel); p.ellipse(17, 9, 3, 1.8, darkSteel)
            p.line((7, 20.5), (31, 20.5), tc, 2.2); p.glow(2.5, 20.5, 6, RGB(1, 0.5, 0.2, 0.7))
        case "h_dropship":
            p.shade(p.ellipsePath(20, 20, 15, 7), olive.mix(steel, 0.4))
            p.box(3, 22, 10, 6, darkSteel, r: 3); p.box(27, 22, 10, 6, darkSteel, r: 3)
            // Rotors blur through the gait frames.
            for (cx, k) in [(8.0, 0), (32.0, 1)] as [(CGFloat, Int)] {
                let a = CGFloat(phase + k * 3) * .pi / 4
                p.stroke(p.ellipsePath(cx, 29.5, 8, 1.8), RGB(0.8, 0.8, 0.8, 0.35), 1)
                p.line((cx - cos(a) * 8, 29.5 - sin(a) * 1.8), (cx + cos(a) * 8, 29.5 + sin(a) * 1.8), RGB(0.85, 0.85, 0.85, 0.7), 1.2)
            }
            p.line((9, 17), (31, 17), tc, 2.2); p.ellipse(30, 21, 3, 2, cyan.mix(RGB(0.2, 0.3, 0.4), 0.5))

        // MARK: Lattice
        case "m_fabricator":
            p.glow(20, 6, 8, cyan.alpha(0.6))
            p.shade(p.ellipsePath(20, 15.5, 9, 7.5), gun)
            p.fill(p.ellipsePath(20, 16.5, 5.5, 3.6), tc.alpha(0.9))
            p.dot(24, 18.5, 2.2, cyan); p.dot(24.5, 19, 0.8, RGB(1, 1, 1))
        case "m_recon":
            p.shade(p.ellipsePath(20, 20, 13, 4), gun)
            p.ellipse(20, 22, 6, 4, chrome)
            p.dot(22, 22, 2.4, cyan); p.dot(22, 22, 1, RGB(1, 1, 1))
            p.line((8, 20), (32, 20), tc, 1.5)
            for k in 0..<2 { let a = CGFloat(phase + k * 4) * .pi / 4; p.line((7 + cos(a) * 4, 21), (7 - cos(a) * 4, 21), chrome.alpha(0.6), 1); p.line((33 + cos(a) * 4, 21), (33 - cos(a) * 4, 21), chrome.alpha(0.6), 1) }
        case "m_arc":
            leg(p, hip: (17.5, 14), len: 10, stride: 2.4, lift: 1.4, gun.dark(0.2), 2.3, offset: 0.5, knee: -1)
            p.shade(p.poly([(12, 13), (28, 13), (26.5, 24.5), (13.5, 24.5)]), chrome.dark(0.1))
            p.line((15, 17), (25, 17), tc, 2)
            leg(p, hip: (22.5, 14), len: 10, stride: 2.4, lift: 1.4, gun, 2.3, offset: 0, knee: -1)
        case "m_shockframe":
            leg(p, hip: (15.5, 12.5), len: 9.5, stride: 2.6, lift: 1.4, gun.dark(0.2), 3.3, offset: 0.5, knee: -1)
            p.shade(p.poly([(8, 12), (32, 12), (30, 27), (10, 27)]), gun.light(0.1))
            p.shade(p.poly([(12, 21.5), (28, 21.5), (26, 27), (14, 27)]), tc.dark(0.2))
            p.dot(20, 24.5, 1.5, cyan)
            leg(p, hip: (24.5, 12.5), len: 9.5, stride: 2.6, lift: 1.4, gun, 3.3, offset: 0, knee: -1)
        case "m_piercer":
            beastLegs(p, xs: [8, 14, 24, 30], hipY: 11, len: 8, stride: 1.8, gun, 1.8)
            p.shade(p.poly([(6, 10), (32, 10), (30, 18), (8, 18)]), gun)
            p.line((9, 13), (29, 13), tc, 1.8)
        case "m_flak":
            p.glow(20, 5, 9, cyan.alpha(0.5 + 0.15 * sin(ang(0))))
            p.shade(p.poly([(7, 8.5), (33, 8.5), (29, 17), (11, 17)]), gun)
            p.line((10, 12), (30, 12), tc, 1.8)
        case "m_repair":
            p.shade(p.ellipsePath(20, 20, 7, 5), chrome)
            p.limb((13, 20), (5, 24), gun, 2); p.limb((27, 20), (35, 24), gun, 2)
            p.dot(5, 24, 2.5, gun); p.dot(35, 24, 2.5, gun)
            p.box(18.5, 17, 3, 7, RGB(0.3, 1, 0.5), r: 0.3); p.box(16.5, 19, 7, 3, RGB(0.3, 1, 0.5), r: 0.3)
            p.line((14, 16), (26, 16), tc, 1.5)
        case "m_jammer":
            leg(p, hip: (18.5, 14), len: 10.5, stride: 2.2, lift: 1.2, gun.dark(0.2), 1.8, offset: 0.5, knee: -1)
            p.shade(p.roundRectPath(14.5, 13, 11, 9, 1.5), gun)
            p.line((16, 17), (24, 17), tc, 1.5)
            leg(p, hip: (21.5, 14), len: 10.5, stride: 2.2, lift: 1.2, gun, 1.8, offset: 0, knee: -1)
        case "m_runner":
            wheel(p, 9, 6, 3.6); wheel(p, 20, 6, 3.6); wheel(p, 31, 6, 3.6)
            p.shade(p.poly([(3, 8), (37, 9), (31, 16.5), (8, 16)]), chrome.dark(0.15))
            p.line((7, 11), (32, 12), tc, 2)
            p.dot(14, 13.5, 1.3, cyan)
        case "m_bulwark":
            leg(p, hip: (14.5, 13), len: 11, stride: 2.4, lift: 1.4, gun.dark(0.25), 4.6, offset: 0.5, knee: -1)
            p.shade(p.poly([(6, 13), (34, 13), (36, 26), (4, 26)]), gun.light(0.12))
            p.shade(p.poly([(13, 26), (27, 26), (24, 32), (16, 32)]), chrome)
            p.dot(23, 29.5, 1.6, cyan)
            p.line((8, 16), (32, 16), tc, 2.5)
            leg(p, hip: (25.5, 13), len: 11, stride: 2.4, lift: 1.4, gun, 4.6, offset: 0, knee: -1)
        case "m_coil":
            tracks(p, 4, 3, 30, 7.5)
            p.shade(p.roundRectPath(5, 10, 26, 8, 1.4), gun)
            p.line((8, 13), (28, 13), tc, 2)
        case "m_suppress":
            beastLegs(p, xs: [12, 20, 28], hipY: 14, len: 12, stride: 1.8, gun, 1.8)
            p.shade(p.ellipsePath(20, 17, 7, 5), gun.light(0.1))
            p.line((15, 17), (25, 17), tc, 1.6)
        case "m_vector":
            p.shade(p.poly([(3, 14), (39, 20), (3, 26), (9, 20)]), chrome.dark(0.1))
            p.shade(p.poly([(12, 20), (24, 20), (6, 33)]), gun); p.shade(p.poly([(12, 20), (24, 20), (6, 7)]), gun.dark(0.1))
            p.line((10, 20), (32, 20), tc, 1.8); p.glow(4, 20, 5, cyan)
        case "m_quake":
            p.shade(p.poly([(6, 18), (12, 28), (28, 28), (34, 18), (28, 10), (12, 10)]), gun.light(0.1))
            p.shade(p.poly([(12, 18), (15, 23), (25, 23), (28, 18), (25, 14), (15, 14)]), tc.dark(0.15))
            p.limb((20, 10), (20, 3), chrome, 3)
            p.glow(20, 18, 6 + sin(ang(0)) * 1.2, cyan.alpha(0.8))
        case "m_carrier":
            p.shade(p.poly([(3, 18), (37, 18), (33, 25), (7, 25)]), gun.light(0.08))
            for x in [6, 34] as [CGFloat] { p.stroke(p.ellipsePath(x, 27, 5, 1.6), chrome.alpha(0.7), 1.2) }
            p.box(11, 24, 18, 5, chrome)
            p.line((7, 21), (33, 21), tc, 2.2); p.dot(20, 26.5, 1.5, cyan)

        // MARK: Brood
        case "a_weaver":
            beastLegs(p, xs: [13, 17, 21, 25], hipY: 10, len: 7, stride: 1.8, chitin.dark(0.3), 1.3)
            p.shade(p.ellipsePath(18, 13, 10, 6), chitin.light(0.15))
            p.fill(p.ellipsePath(16, 16, 5, 2), tc.alpha(0.8))
            p.glow(8.5, 13, 4, bio.alpha(0.7)); p.dot(8.5, 13, 1.2, bio.light(0.3))
        case "a_glint":
            p.glow(20, 16 + sin(ang(0)) * 1, 12, bio.alpha(0.8))
            p.ellipse(20, 16 + sin(ang(0)) * 1, 6, 4, RGB(0.6, 0.9, 0.4))
            p.shape([(17, 18), (10, 27 + sin(ang(0.25)) * 2), (21, 20)], RGB(0.8, 1, 0.8, 0.6))
            p.dot(24, 17, 1.2, tc)
        case "a_mantis":
            leg(p, hip: (17.5, 12), len: 9, stride: 2.4, lift: 1.6, chitin.dark(0.25), 2, offset: 0.5, knee: -1)
            p.shade(p.ellipsePath(17, 14.5, 6, 5), chitin.light(0.1))                       // abdomen
            p.fill(p.ellipsePath(16, 15, 3, 2.4), tc.alpha(0.85))
            leg(p, hip: (21.5, 12), len: 9, stride: 2.4, lift: 1.6, chitin, 2, offset: 0, knee: -1)
        case "a_ravager":
            beastLegs(p, xs: [9, 15, 24, 30], hipY: 11, len: 9, stride: 2.4, chitin.dark(0.2), 2.6)
            p.shade(p.ellipsePath(19, 15, 14, 7.5), chitin.light(0.05))
            p.shape([(8, 20), (13, 27), (18, 21), (23, 28), (28, 20)], bone)
            p.fill(p.ellipsePath(19, 14, 6, 3), tc.alpha(0.8))
        case "a_spinecaster":
            beastLegs(p, xs: [12, 18, 26], hipY: 10.5, len: 8, stride: 2, chitin.dark(0.2), 2)
            p.shade(p.ellipsePath(19, 15, 12, 7), flesh.dark(0.25))
            p.shade(p.ellipsePath(31, 15, 4, 4), chitin); p.dot(33, 16, 1, bio)
            p.fill(p.ellipsePath(18, 14, 5, 2.5), tc.alpha(0.8))
        case "a_needleback":
            beastLegs(p, xs: [11, 17, 25, 29], hipY: 10, len: 8, stride: 2, chitin.dark(0.2), 2)
            p.shade(p.ellipsePath(20, 14, 13, 8), chitin.light(0.1))
            p.fill(p.ellipsePath(20, 13, 6, 3), tc.alpha(0.8))
            p.shade(p.ellipsePath(32, 13, 3.5, 3), chitin); p.dot(33.5, 13.5, 0.9, bio)
        case "a_lifebinder":
            let bob = sin(ang(0)) * 1.2
            p.glow(20, 20 + bob, 18, bio.alpha(0.5))
            for i in 0..<5 { let x = 12 + CGFloat(i) * 4; p.limb((x, 14 + bob), (x + sin(ang(CGFloat(i) * 0.2)) * 2.2, 2), flesh.light(0.2), 1.3) }
            p.shade(p.ellipsePath(20, 20 + bob, 11, 9), RGB(0.55, 0.85, 0.55, 0.95))
            p.ellipse(20, 22 + bob, 6, 5, bio.light(0.3)); p.fill(p.ellipsePath(20, 16 + bob, 6, 2), tc.alpha(0.8))
        case "a_shadeling":
            let sway = sin(ang(0)) * 1.5
            p.glow(20, 15, 15, RGB(0.4, 0.1, 0.5, 0.6))
            p.shape([(8 + sway, 4), (14, 22), (20, 30), (27, 22), (32 + sway, 4), (20, 10)], RGB(0.16, 0.08, 0.22))
            p.shape([(26, 20), (38, 26 + sway), (30, 16)], bone.dark(0.3)); p.shape([(14, 20), (2, 26 - sway), (10, 16)], bone.dark(0.3))
            p.dot(17, 24, 1.3, RGB(0.9, 0.3, 1)); p.dot(23, 24, 1.3, RGB(0.9, 0.3, 1))
            p.line((15, 14), (25, 14), tc, 1.4)
        case "a_skitter":
            beastLegs(p, xs: [13, 17, 21, 25], hipY: 10, len: 8, stride: 2.4, chitin.dark(0.3), 1.4)
            p.shade(p.ellipsePath(19, 13, 9, 5.5), chitin.light(0.2))
            p.fill(p.ellipsePath(17, 14, 5, 2.4), tc.alpha(0.85))
        case "a_colossus":
            beastLegs(p, xs: [8, 15, 25, 32], hipY: 12, len: 11, stride: 2.4, chitin.dark(0.25), 4)
            p.shade(p.ellipsePath(19, 18, 16, 11), chitin.light(0.05))
            p.shape([(5, 24), (11, 35), (17, 27), (23, 36), (29, 26)], bone.dark(0.05))
            p.fill(p.ellipsePath(19, 16, 9, 4), tc.alpha(0.75))
        case "a_rupturer":
            beastLegs(p, xs: [10, 17, 24, 30], hipY: 10, len: 9, stride: 2, chitin.dark(0.2), 2.6)
            p.shade(p.ellipsePath(18, 18, 14, 10), flesh.dark(0.15))
            p.ellipse(16, 21, 9, 7, RGB(0.6, 0.85, 0.3, 0.9)); p.glow(16, 21, 10, bio.alpha(0.45 + 0.15 * sin(ang(0))))
            p.fill(p.ellipsePath(18, 12, 7, 2.5), tc.alpha(0.8))
        case "a_seeder":
            leg(p, hip: (17.5, 10), len: 8, stride: 2, lift: 1.2, chitin.dark(0.2), 2, offset: 0.5, knee: -1)
            p.shade(p.ellipsePath(20, 14, 7, 6), flesh.dark(0.2))
            p.fill(p.ellipsePath(20, 13, 4, 2), tc.alpha(0.85))
            leg(p, hip: (22.5, 10), len: 8, stride: 2, lift: 1.2, chitin, 2, offset: 0, knee: -1)
        case "a_wisp":
            let f = sin(ang(0)) * 3
            p.glow(20, 20, 14, bio.alpha(0.6))
            p.shape([(20, 20), (6, 34 - f), (2, 22)], RGB(0.7, 0.95, 0.6, 0.85)); p.shape([(20, 20), (6, 6 + f), (2, 18)], RGB(0.6, 0.9, 0.5, 0.75))
            p.ellipse(22, 20, 6, 3, chitin.light(0.3)); p.dot(27, 20.5, 1, tc)
        case "a_blightwing":
            let f = sin(ang(0)) * 3
            p.shade(p.poly([(2, 24 + f), (14, 20), (20, 36 - f * 0.5), (24, 20), (38, 26 + f), (30, 16), (20, 12), (10, 16)]), chitin.light(0.1))
            p.ellipse(20, 19, 6, 5, flesh.dark(0.2)); p.glow(20, 15, 7, bio.alpha(0.7))
            p.line((10, 19), (30, 19), tc, 1.6)
        case "a_sporewing":
            for i in 0..<6 { let x = 10 + CGFloat(i) * 4; p.limb((x, 16), (x + sin(ang(CGFloat(i) * 0.15)) * 2, 4), flesh, 1.2) }
            p.shade(p.ellipsePath(20, 24, 15, 11), RGB(0.6, 0.4, 0.6))
            for (x, y) in [(13, 27), (20, 30), (27, 26), (17, 21), (25, 20)] as [(CGFloat, CGFloat)] { p.dot(x, y, 1.8, bio) }
            p.fill(p.ellipsePath(20, 16, 10, 2.6), tc.alpha(0.8))
        default:
            p.ellipse(20, 15, 10, 8, RGB(0.6, 0.6, 0.6))
        }
    }

    // MARK: Upper layer (rest pose: weapon level, facing right)

    static func upper(_ id: String, _ v: String, _ p: Pen, _ tc: RGB) {
        switch id {
        // MARK: Concord
        case "h_engineer":
            let sleeve = RGB(0.62, 0.55, 0.35)
            switch v {
            case "wood":   // felling axe
                arms(p, sleeve, back: (25, 22))
                p.limb((23, 20.5), (31, 27.5), RGB(0.55, 0.38, 0.2), 1.4)
                p.shade(p.poly([(29.5, 28.5), (33.8, 25), (35, 29), (32, 31)]), steel.light(0.1), lw: 0.7)
                frontArm(p, sleeve, (26.5, 22.6))
            case "ore":    // pick
                arms(p, sleeve, back: (25, 22))
                p.limb((23, 20.5), (31, 27.5), RGB(0.55, 0.38, 0.2), 1.4)
                p.limb((27.5, 30.5), (34.5, 24.5), steel, 1.6); p.dot(34.6, 24.4, 0.7, steel.light(0.3))
                frontArm(p, sleeve, (26.5, 22.6))
            case "build":  // hammer
                arms(p, sleeve, back: (25, 21))
                p.limb((24, 20.5), (30, 25.5), RGB(0.55, 0.38, 0.2), 1.4)
                p.shade(p.roundRectPath(28.2, 25, 4.4, 3.2, 0.6), darkSteel.light(0.2), lw: 0.6)
                frontArm(p, sleeve, (26, 21.8))
            default:       // wrench at the ready
                arms(p, sleeve, back: (24, 17.5))
                p.limb((24.5, 16.5), (30.5, 14), steel, 2.0); p.stroke(p.ellipsePath(31.4, 13.6, 1.8, 1.8), steel, 1.2)
                frontArm(p, sleeve, (25.6, 16.8))
            }
        case "h_pathfinder":
            let sl = olive.mix(RGB(0.5, 0.55, 0.4), 0.4)
            arms(p, sl, back: (25, 19))
            rifle(p, from: 21, to: 32.5, y: 19.5, darkSteel)
            frontArm(p, sl, (27.5, 19.2))
        case "h_ranger":
            arms(p, olive, back: (24.5, 19.2))
            rifle(p, from: 19, to: 35.5, y: 19.6, darkSteel)
            p.box(23, 20.4, 5, 1.6, darkSteel.light(0.2), r: 0.4)       // scope
            frontArm(p, olive, (29, 19.4))
        case "h_breacher":
            arms(p, olive.dark(0.1), back: (25, 18.8))
            p.shade(p.poly([(20, 17.2), (36, 17.6), (36, 19.8), (20, 20.4)]), darkSteel.dark(0.1), lw: 0.7)
            p.box(28, 15.8, 6, 1.6, RGB(0.45, 0.3, 0.18), r: 0.4)        // pump
            frontArm(p, olive.dark(0.1), (31, 17.4))
        case "h_lancer":
            arms(p, olive, back: (24, 21.5), shoulder: (20, 23))
            p.shade(p.roundRectPath(8, 22, 28, 6, 3), RGB(0.35, 0.40, 0.30), lw: 0.8)
            p.fill(p.ellipsePath(36, 25, 2, 3), black); p.line((10, 28), (17, 28), tc, 1.5)
            p.box(24, 27.5, 4, 2.4, darkSteel, r: 0.4)                    // sight
            frontArm(p, olive, (25.5, 22), shoulder: (20, 23))
        case "h_skyguard":
            let sl = olive.mix(steel, 0.3)
            arms(p, sl, back: (23, 24), shoulder: (20, 22))
            p.shade(p.poly([(11, 19.5), (24, 34), (30, 30), (17, 16.5)]), RGB(0.32, 0.36, 0.3), lw: 0.8)
            for (x, y) in [(25.5, 31.5), (22, 28), (19, 24.5)] as [(CGFloat, CGFloat)] { p.dot(x, y, 1.3, RGB(1, 0.4, 0.2)) }
            frontArm(p, sl, (24.5, 23), shoulder: (20, 22))
        case "h_medic":
            arms(p, RGB(0.88, 0.88, 0.85), back: (24, 18.5))
            p.box(24, 17.4, 6.4, 2.4, darkSteel.light(0.1), r: 0.6)
            p.glow(30.5, 18.6, 2.2, RGB(0.4, 1, 0.5, 0.8))
            frontArm(p, RGB(0.88, 0.88, 0.85), (26.5, 18.4))
        case "h_ghost":
            arms(p, RGB(0.18, 0.2, 0.24), back: (25, 19.4))
            rifle(p, from: 19, to: 38, y: 20, RGB(0.15, 0.15, 0.18), thick: 1.8)
            p.box(25, 21, 6, 1.5, RGB(0.1, 0.1, 0.12), r: 0.4); p.dot(31, 21.7, 0.6, RGB(0.4, 1, 0.9))
            frontArm(p, RGB(0.18, 0.2, 0.24), (30, 19.7))
        case "h_buggy":
            p.shade(p.roundRectPath(18, 19.5, 8, 4.5, 1.2), darkSteel)
            p.limb((24, 22.6), (36.5, 22.8), darkSteel.dark(0.2), 1.5); p.limb((24, 21.1), (36.5, 21.2), darkSteel.dark(0.2), 1.5)
            p.dot(22, 22, 0.8, amber)
        case "h_bastion":
            p.shade(p.poly([(11, 20.5), (29, 20.5), (27.5, 27.5), (13.5, 28.5)]), olive.light(0.08))
            p.shade(p.roundRectPath(27, 23.6, 13, 2.8, 1.2), darkSteel, lw: 0.8)
            p.box(36, 23.2, 3, 3.6, darkSteel.dark(0.2), r: 0.6)               // muzzle brake
            p.dot(17, 26, 1.2, amber); p.line((14, 24), (26, 24), tc, 1.4)
        case "h_mortar":
            p.box(14, 18, 8, 4.5, steel.dark(0.2))
            p.shade(p.roundRectPath(16, 18.6, 15, 4.6, 2), darkSteel, lw: 0.8)
            p.fill(p.ellipsePath(31, 20.9, 1.2, 2.3), black)
        case "h_minelayer":
            p.box(22, 19, 6, 4, darkSteel)
            p.limb((27, 21.4), (37.5, 21.5), darkSteel.dark(0.2), 1.5)

        // MARK: Lattice
        case "m_fabricator":
            // Manipulator arms with a cutting emitter.
            p.limb((14, 17), (8, 12), chrome, 1.6); p.dot(8, 12, 1.2, gun)
            p.limb((26, 17), (31, 12.5), chrome, 1.7); p.limb((31, 12.5), (33, 11), chrome.dark(0.15), 1.4)
            p.glow(33, 11, 2.4, cyan.alpha(0.9)); p.dot(33, 11, 0.8, RGB(1, 1, 1))
        case "m_arc":
            p.limb((20, 24.5), (20, 29.5), gun, 1.6)
            p.ellipse(20, 32, 4, 4, chrome); p.glow(20, 32, 8, cyan.alpha(0.9)); p.dot(20, 32, 1.6, RGB(1, 1, 1))
        case "m_shockframe":
            p.shade(p.ellipsePath(32, 15.5, 5, 5), chrome); p.shade(p.ellipsePath(8, 15.5, 5, 5), chrome.dark(0.15))
            p.limb((12, 18), (28, 18), gun.light(0.15), 2.4)
            p.glow(33, 15.5, 6, cyan.alpha(0.6)); p.dot(34, 15.5, 1.5, RGB(0.9, 1, 1))
        case "m_piercer":
            p.box(11, 16, 9, 4, gun.light(0.1), r: 0.8)
            p.limb((14, 18.2), (40, 19), chrome, 2.5); p.limb((14, 18.2), (40, 19), cyan.alpha(0.55), 0.8)
            for x in [24.0, 30, 36] as [CGFloat] { p.stroke(p.ellipsePath(x, 18.6, 0.8, 2), chrome.dark(0.2), 0.7) }
        case "m_flak":
            p.shade(p.roundRectPath(15, 16, 10, 4, 1), gun.light(0.1))
            for i in 0..<3 { p.limb((16 + CGFloat(i) * 4, 18), (21 + CGFloat(i) * 3, 32), chrome, 1.8); p.dot(21 + CGFloat(i) * 3, 32, 0.9, cyan) }
        case "m_jammer":
            p.limb((20, 22), (20, 28), chrome, 1.5)
            p.shade(p.poly([(12, 34), (28, 34), (24, 28), (16, 28)]), chrome)
            for r in [6, 9] as [CGFloat] { p.stroke(p.ellipsePath(20, 34, r, r * 0.5), RGB(0.6, 0.4, 1, 0.6), 1) }
        case "m_runner":
            p.shade(p.roundRectPath(18, 14.5, 7, 3.6, 1), gun)
            p.limb((22, 16.6), (38.5, 17), gun.dark(0.15), 1.5)
        case "m_bulwark":
            p.box(1, 18.5, 7, 5, chrome.dark(0.2)); p.box(32, 18.5, 7, 5, chrome.dark(0.2))
            p.limb((34, 21), (40, 21), gun, 2.2); p.limb((6, 21), (1, 21), gun, 2)
            p.glow(39.5, 21, 2.2, cyan.alpha(0.7))
        case "m_coil":
            p.limb((12, 17), (39, 27), chrome.dark(0.2), 3)
            for i in 0..<4 { let t = CGFloat(i) / 4; p.stroke(p.ellipsePath(16 + t * 18, 18.5 + t * 6.7, 1.6, 3), cyan, 1.2) }
            p.box(9, 14.5, 7, 5, gun.light(0.1), r: 1)
        case "m_suppress":
            p.stroke(p.ellipsePath(20, 25, 13, 5), cyan.alpha(0.85), 2)
            p.glow(20, 25, 12, cyan.alpha(0.35))
            p.limb((20, 20), (20, 24), chrome, 1.2)

        // MARK: Brood
        case "a_weaver":
            // Head with mandibles; spinneret glow while working.
            p.shade(p.ellipsePath(28.5, 15, 4.2, 3.6), chitin)
            p.dot(30.8, 16.4, 1, bio)
            p.limb((31, 14), (34, 12.5), bone, 1.1); p.limb((31, 15.6), (34, 16.4), bone, 1.1)
            if v == "build" || v == "ore" { p.glow(34, 14.5, 3, bio.alpha(0.6)) }
        case "a_mantis":
            p.shade(p.ellipsePath(21, 24, 4, 6), chitin)                                // thorax
            p.shade(p.ellipsePath(25, 31, 3.5, 3), chitin.light(0.15)); p.dot(27, 32, 0.9, bio)
            p.shade(p.poly([(22, 27), (35, 32), (33.5, 19.5), (31, 29)]), bone, lw: 0.8)    // scythe
            p.fill(p.ellipsePath(20.5, 22, 2.4, 2.4), tc.alpha(0.85))
        case "a_ravager":
            p.shade(p.ellipsePath(32, 14, 5, 5), chitin)
            p.shade(p.poly([(33, 10), (40, 6), (38, 14)]), bone, lw: 0.7)
            p.dot(34.5, 15.5, 1, bio)
        case "a_spinecaster":
            for i in 0..<5 { let x = 10 + CGFloat(i) * 3.6; p.limb((x, 19), (x + 9, 30), bone, 1.4); p.dot(x + 9, 30, 0.6, bone.light(0.3)) }
        case "a_needleback":
            for i in 0..<7 { let x = 9 + CGFloat(i) * 3.6; p.limb((x, 19), (x + 2, 34), bone.mix(bio, 0.3), 1.1) }
        case "a_skitter":
            p.shade(p.ellipsePath(28, 13, 4, 3.5), chitin)
            p.dot(30, 14, 1, RGB(1, 0.3, 0.3))
            p.limb((31, 12), (34, 11), bone, 0.9); p.limb((31, 13.6), (34, 14.4), bone, 0.9)
        case "a_colossus":
            p.shade(p.ellipsePath(34, 16, 6, 6), chitin.dark(0.1))
            p.shade(p.poly([(36, 12), (40, 4), (40, 14)]), bone, lw: 0.7); p.dot(37, 18, 1.2, bio)
            p.shade(p.poly([(37, 13), (41, 10), (39, 15)]), bone.dark(0.1), lw: 0.6)
        case "a_rupturer":
            p.limb((24, 21), (37, 31), chitin, 3.5)
            p.glow(37, 31, 3, bio.alpha(0.7)); p.dot(37, 31, 1.2, bio.light(0.3))
        case "a_seeder":
            p.shade(p.poly([(6, 22), (20, 34), (34, 22), (20, 18)]), RGB(0.55, 0.3, 0.55))
            for i in 0..<4 { p.dot(11 + CGFloat(i) * 6, 25 + CGFloat(i % 2) * 3, 1.6, bio) }
        default: break
        }
    }
}
