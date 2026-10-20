import CoreGraphics
import MeridianCore

/// Original procedural unit sprites. Every unit is drawn facing right in a 40x40 design grid that
/// is scaled to the unit's footprint. Factions share a visual grammar:
///  - Concord (humans): olive/steel plating, angular shapes, amber visors, team-coloured stripes.
///  - Lattice (machines): gunmetal and chrome, hexagonal forms, cyan energy cores.
///  - Brood (aliens): chitin and flesh, curves and spines, bio-green glow.
enum UnitArt {
    static let olive = RGB(0.40, 0.45, 0.36), steel = RGB(0.58, 0.61, 0.62), amber = RGB(1.0, 0.75, 0.25)
    static let skin = RGB(0.86, 0.68, 0.55), darkSteel = RGB(0.28, 0.30, 0.31)
    static let gun = RGB(0.26, 0.28, 0.33), chrome = RGB(0.70, 0.74, 0.80), cyan = RGB(0.35, 0.95, 1.0)
    static let chitin = RGB(0.40, 0.24, 0.42), flesh = RGB(0.78, 0.45, 0.55), bio = RGB(0.55, 1.0, 0.35), bone = RGB(0.88, 0.84, 0.72)

    static func canvasSize(_ d: UnitDef) -> CGFloat { 26 + CGFloat(d.radius) * 68 }

    /// Animation frame (0-3) used by legs, wheels, treads and engines while drawing.
    nonisolated(unsafe) static var phase = 0
    nonisolated(unsafe) static var legIndex = 0
    static let frameCount = 4

    static func render(_ d: UnitDef, team: RGB, frame: Int = 0) -> CGImage {
        let S = canvasSize(d)
        phase = frame
        legIndex = 0
        let img = Pen.image(S, S) { p in
            let s = S / 40
            p.ctx.scaleBy(x: s, y: s)
            if d.domain == .ground { p.fill(p.ellipsePath(20, 4.5, 9 * min(1.6, 0.6 + CGFloat(d.radius)), 2.4), RGB(0.05, 0.04, 0.10, 0.35)) }  // contact occlusion
            draw(d.id, p, team)
            if d.domain == .air { engineFlicker(p, frame) }
        }
        return Pen.lit(img, offset: 1.4)
    }

    /// Walking leg: the foot swings forward/back with alternating phase per leg.
    static func leg(_ p: Pen, _ foot: (CGFloat, CGFloat), _ hip: (CGFloat, CGFloat), _ c: RGB, _ lw: CGFloat) {
        let swing: [CGFloat] = [0, 2.2, 0, -2.2]
        let lift: [CGFloat] = [0, 0.8, 0, 0]
        let k = (phase + (legIndex % 2) * 2) % 4
        legIndex += 1
        p.limb((foot.0 + swing[k], foot.1 + lift[k]), hip, c, lw)
    }

    static func engineFlicker(_ p: Pen, _ frame: Int) {
        // Subtle shimmer under aircraft so idle flyers feel alive.
        let a: CGFloat = [0.25, 0.4, 0.3, 0.45][frame % 4]
        p.glow(20, 12, 9, RGB(1, 0.9, 0.7, a * 0.5))
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    static func draw(_ id: String, _ p: Pen, _ tc: RGB) {
        switch id {
        // MARK: Humans
        case "h_engineer":
            soldierBase(p, body: RGB(0.62, 0.55, 0.35), tc: tc, helmet: RGB(1.0, 0.68, 0.1))
            p.box(8, 14, 7, 10, RGB(0.45, 0.42, 0.35))                     // backpack
            p.limb((25, 17), (32, 22), steel, 2.2); p.dot(32.5, 22.5, 2, steel) // wrench
        case "h_pathfinder":
            p.limb((14, 30), (12, 38), darkSteel, 1)                          // antenna
            p.dot(12, 38.5, 1.2, RGB(1, 0.3, 0.3))
            soldierBase(p, body: olive.mix(RGB(0.5, 0.55, 0.4), 0.4), tc: tc, helmet: olive.dark(0.1), slim: true)
            p.limb((22, 18), (34, 19), darkSteel, 1.6)
        case "h_ranger":
            soldierBase(p, body: olive, tc: tc, helmet: olive.dark(0.15))
            p.limb((18, 18), (35, 19), darkSteel, 2.2); p.box(20, 16, 6, 4, darkSteel, r: 0.5)
        case "h_breacher":
            soldierBase(p, body: olive.dark(0.1), tc: tc, helmet: darkSteel, bulky: true)
            p.shape([(26, 8), (33, 10), (33, 27), (26, 29)], steel.dark(0.1))   // shield
            p.line((27, 12), (32, 13), tc, 1.5); p.line((27, 24), (32, 24), tc, 1.5)
            p.limb((22, 15), (36, 14), darkSteel, 3)
        case "h_lancer":
            soldierBase(p, body: olive, tc: tc, helmet: olive.dark(0.15))
            p.box(8, 24, 26, 6, RGB(0.35, 0.40, 0.30), r: 3)                   // launcher tube
            p.fill(p.ellipsePath(34, 27, 2, 3), RGB(0.1, 0.1, 0.1)); p.line((10, 30), (16, 30), tc, 1.5)
        case "h_skyguard":
            soldierBase(p, body: olive.mix(steel, 0.3), tc: tc, helmet: steel)
            p.shape([(10, 20), (22, 34), (28, 30), (16, 17)], RGB(0.32, 0.36, 0.3)) // angled pod
            p.dot(24, 32, 1.5, RGB(1, 0.4, 0.2)); p.dot(20, 28, 1.5, RGB(1, 0.4, 0.2))
        case "h_medic":
            soldierBase(p, body: RGB(0.88, 0.88, 0.85), tc: tc, helmet: RGB(0.9, 0.9, 0.9))
            p.box(8, 15, 8, 9, RGB(0.9, 0.9, 0.9)); p.box(10.5, 17, 3, 5, RGB(0.2, 0.75, 0.3), r: 0.3); p.box(9.5, 18, 5, 3, RGB(0.2, 0.75, 0.3), r: 0.3)
        case "h_ghost":
            soldierBase(p, body: RGB(0.18, 0.2, 0.24), tc: tc, helmet: RGB(0.12, 0.13, 0.16), slim: true, visor: RGB(0.4, 1, 0.9))
            p.limb((18, 19), (37, 21), RGB(0.15, 0.15, 0.18), 1.6); p.box(31, 20, 3, 2, darkSteel, r: 0.3)
        case "h_buggy":
            wheel(p, 10, 7, 4); wheel(p, 30, 7, 4)
            p.shape([(4, 9), (36, 9), (34, 17), (24, 20), (10, 20), (5, 15)], olive)
            p.line((8, 12), (32, 12), tc, 2)
            p.box(18, 19, 8, 5, darkSteel); p.limb((24, 22), (36, 23), darkSteel, 1.5); p.limb((24, 20.5), (36, 21), darkSteel, 1.5)
        case "h_bastion":
            tracks(p, 2, 4, 36, 9)
            p.shape([(3, 12), (37, 12), (35, 20), (6, 20)], olive)
            p.line((6, 15), (34, 15), tc, 2.2)
            p.shape([(12, 20), (28, 20), (27, 27), (14, 28)], olive.light(0.08))
            p.limb((26, 24), (40, 25), darkSteel, 3.2)
            p.dot(17, 26, 1.2, amber)
        case "h_mortar":
            tracks(p, 3, 4, 34, 8)
            p.box(4, 11, 30, 9, olive)
            p.line((6, 14), (32, 14), tc, 2)
            p.limb((18, 20), (27, 33), darkSteel, 4)
            p.box(8, 20, 8, 5, steel.dark(0.2))
        case "h_minelayer":
            tracks(p, 3, 4, 34, 8)
            p.box(4, 11, 30, 11, olive.mix(RGB(0.6, 0.5, 0.2), 0.3))
            for i in 0..<3 { p.ellipse(10 + CGFloat(i) * 7, 24, 3, 1.6, RGB(0.25, 0.25, 0.2)) }
            p.line((6, 15), (32, 15), tc, 2); p.limb((28, 18), (37, 19), darkSteel, 1.5)
        case "h_kestrel":
            p.shape([(4, 18), (38, 20), (6, 24)], steel)                       // fuselage
            p.shape([(14, 21), (24, 21), (10, 34)], steel.dark(0.1))           // wing
            p.shape([(14, 19), (24, 19), (10, 8)], steel.dark(0.2))
            p.line((12, 21), (28, 20.5), tc, 1.8)
            p.dot(31, 20.5, 1.6, cyan.mix(amber, 0.7)); p.glow(4, 21, 5, RGB(1, 0.6, 0.2, 0.8))
        case "h_harrier":
            p.shape([(2, 17), (36, 19), (38, 22), (3, 24)], darkSteel.light(0.15))
            p.shape([(12, 22), (26, 22), (16, 38)], olive)
            p.shape([(12, 18), (26, 18), (16, 2)], olive.dark(0.15))
            p.ellipse(18, 31, 3, 2, darkSteel); p.ellipse(18, 9, 3, 2, darkSteel)
            p.line((8, 20.5), (30, 20.5), tc, 2.2); p.glow(3, 20, 6, RGB(1, 0.5, 0.2, 0.7))
        case "h_dropship":
            p.ellipse(20, 20, 15, 7, olive.mix(steel, 0.4))
            p.box(4, 22, 9, 6, darkSteel, r: 3); p.box(27, 22, 9, 6, darkSteel, r: 3)
            p.stroke(p.ellipsePath(8.5, 29, 7, 1.5), RGB(0.8, 0.8, 0.8, 0.6), 1); p.stroke(p.ellipsePath(31.5, 29, 7, 1.5), RGB(0.8, 0.8, 0.8, 0.6), 1)
            p.line((9, 17), (31, 17), tc, 2.2); p.ellipse(30, 21, 3, 2, cyan.mix(RGB(0.2, 0.3, 0.4), 0.5))

        // MARK: Machines
        case "m_fabricator":
            p.glow(20, 7, 8, cyan.alpha(0.6))
            p.ellipse(20, 17, 9, 8, gun)
            p.fill(p.ellipsePath(20, 18, 5, 4), tc.alpha(0.9))
            p.dot(23, 19, 2, cyan)
            p.limb((27, 15), (34, 10), chrome, 1.6); p.limb((13, 15), (8, 10), chrome, 1.6)
        case "m_recon":
            p.ellipse(20, 20, 13, 4, gun)
            p.ellipse(20, 22, 6, 4, chrome)
            p.dot(22, 22, 2.4, cyan); p.dot(22, 22, 1, RGB(1, 1, 1))
            p.line((8, 20), (32, 20), tc, 1.5)
        case "m_arc":
            leg(p, (16, 4), (17, 14), gun, 2.2); leg(p, (24, 4), (23, 14), gun, 2.2)
            p.shape([(12, 13), (28, 13), (26, 24), (14, 24)], chrome.dark(0.1))
            p.line((15, 17), (25, 17), tc, 2)
            p.limb((20, 24), (20, 30), gun, 1.5)
            p.ellipse(20, 32, 4, 4, chrome); p.glow(20, 32, 8, cyan.alpha(0.9)); p.dot(20, 32, 1.6, RGB(1, 1, 1))
        case "m_shockframe":
            leg(p, (14, 3), (15, 12), gun, 3.2); leg(p, (26, 3), (25, 12), gun, 3.2)
            p.shape([(8, 12), (32, 12), (30, 28), (10, 28)], gun.light(0.1))
            p.shape([(12, 22), (28, 22), (26, 28), (14, 28)], tc.dark(0.2))
            p.ellipse(33, 15, 5, 5, chrome); p.ellipse(7, 15, 5, 5, chrome)
            p.glow(33, 15, 6, cyan.alpha(0.6)); p.dot(20, 25, 1.5, cyan)
        case "m_piercer":
            for x in [8, 14, 24, 30] as [CGFloat] { leg(p, (x, 3), (x + 2, 10), gun, 1.8) }
            p.shape([(6, 10), (32, 10), (30, 18), (8, 18)], gun)
            p.limb((14, 17), (40, 19), chrome, 2.5); p.limb((14, 17), (40, 19), cyan.alpha(0.5), 0.8)
            p.line((9, 13), (29, 13), tc, 1.8)
        case "m_flak":
            p.glow(20, 5, 9, cyan.alpha(0.5))
            p.shape([(8, 9), (32, 9), (28, 17), (12, 17)], gun)
            p.line((11, 12), (29, 12), tc, 1.8)
            for i in 0..<3 { p.limb((15 + CGFloat(i) * 4, 17), (19 + CGFloat(i) * 4, 31), chrome, 1.8) }
        case "m_repair":
            p.ellipse(20, 20, 7, 5, chrome)
            p.limb((13, 20), (5, 24), gun, 2); p.limb((27, 20), (35, 24), gun, 2)
            p.dot(5, 24, 2.5, gun); p.dot(35, 24, 2.5, gun)
            p.box(18.5, 17, 3, 7, RGB(0.3, 1, 0.5), r: 0.3); p.box(16.5, 19, 7, 3, RGB(0.3, 1, 0.5), r: 0.3)
            p.line((14, 16), (26, 16), tc, 1.5)
        case "m_jammer":
            leg(p, (14, 3), (18, 14), gun, 1.8); leg(p, (26, 3), (22, 14), gun, 1.8)
            p.box(15, 13, 10, 9, gun)
            p.limb((20, 22), (20, 28), chrome, 1.5)
            p.shape([(12, 34), (28, 34), (24, 28), (16, 28)], chrome)
            p.line((16, 17), (24, 17), tc, 1.5)
            for r in [6, 9] as [CGFloat] { p.stroke(p.ellipsePath(20, 34, r, r * 0.5), RGB(0.6, 0.4, 1, 0.6), 1) }
        case "m_runner":
            wheel(p, 9, 6, 3.5); wheel(p, 20, 6, 3.5); wheel(p, 31, 6, 3.5)
            p.shape([(3, 8), (37, 9), (30, 18), (8, 17)], chrome.dark(0.15))
            p.line((7, 11), (32, 12), tc, 2)
            p.limb((22, 16), (38, 17), gun, 1.5); p.dot(15, 15, 1.4, cyan)
        case "m_bulwark":
            leg(p, (13, 2), (14, 13), gun, 4.5); leg(p, (27, 2), (26, 13), gun, 4.5)
            p.shape([(6, 13), (34, 13), (36, 26), (4, 26)], gun.light(0.12))
            p.shape([(13, 26), (27, 26), (24, 33), (16, 33)], chrome)
            p.dot(23, 30, 1.6, cyan)
            p.box(0, 18, 7, 5, chrome.dark(0.2)); p.box(33, 18, 7, 5, chrome.dark(0.2))
            p.limb((34, 21), (40, 21), gun, 2); p.limb((6, 21), (0, 21), gun, 2)
            p.line((8, 16), (32, 16), tc, 2.5)
        case "m_coil":
            tracks(p, 4, 3, 30, 7)
            p.box(6, 10, 24, 8, gun)
            p.limb((12, 17), (39, 27), chrome.dark(0.2), 3)
            for i in 0..<4 { let t = CGFloat(i) / 4; p.stroke(p.ellipsePath(16 + t * 18, 18.5 + t * 6.7, 1.6, 3), cyan, 1.2) }
            p.line((8, 13), (28, 13), tc, 2)
        case "m_suppress":
            leg(p, (10, 2), (17, 14), gun, 1.8); leg(p, (30, 2), (23, 14), gun, 1.8); leg(p, (20, 1), (20, 14), gun, 1.8)
            p.ellipse(20, 17, 7, 5, gun.light(0.1))
            p.stroke(p.ellipsePath(20, 25, 13, 5), cyan.alpha(0.85), 2)
            p.glow(20, 25, 12, cyan.alpha(0.35))
            p.line((15, 17), (25, 17), tc, 1.6)
        case "m_vector":
            p.shape([(3, 14), (39, 20), (3, 26), (9, 20)], chrome.dark(0.1))
            p.shape([(12, 20), (24, 20), (6, 33)], gun); p.shape([(12, 20), (24, 20), (6, 7)], gun.dark(0.1))
            p.line((10, 20), (32, 20), tc, 1.8); p.glow(4, 20, 5, cyan)
        case "m_quake":
            p.shape([(6, 18), (12, 28), (28, 28), (34, 18), (28, 10), (12, 10)], gun.light(0.1))
            p.shape([(12, 18), (15, 23), (25, 23), (28, 18), (25, 14), (15, 14)], tc.dark(0.15))
            p.limb((20, 10), (20, 3), chrome, 3)
            p.glow(20, 18, 6, cyan.alpha(0.8))
        case "m_carrier":
            p.shape([(3, 18), (37, 18), (33, 25), (7, 25)], gun.light(0.08))
            for x in [6, 34] as [CGFloat] { p.stroke(p.ellipsePath(x, 27, 5, 1.6), chrome.alpha(0.7), 1.2) }
            p.box(11, 24, 18, 5, chrome)
            p.line((7, 21), (33, 21), tc, 2.2); p.dot(20, 26.5, 1.5, cyan)

        // MARK: Aliens
        case "a_weaver":
            bugLegs(p, 20, 9, 4, 8)
            p.ellipse(20, 13, 10, 6, chitin.light(0.15))
            p.ellipse(29, 15, 4, 3.5, chitin)
            p.dot(31, 16, 1, bio); p.fill(p.ellipsePath(18, 16, 5, 2), tc.alpha(0.8))
            p.glow(10, 13, 4, bio.alpha(0.7))
        case "a_glint":
            p.glow(20, 16, 12, bio.alpha(0.8))
            p.ellipse(20, 16, 6, 4, RGB(0.6, 0.9, 0.4))
            p.shape([(17, 18), (10, 27), (21, 20)], RGB(0.8, 1, 0.8, 0.6))
            p.dot(24, 17, 1.2, tc)
        case "a_mantis":
            leg(p, (16, 3), (18, 12), chitin, 2); leg(p, (24, 3), (22, 12), chitin, 2)
            p.ellipse(20, 15, 5, 6, chitin.light(0.1))
            p.ellipse(21, 25, 4, 6, chitin)
            p.ellipse(25, 32, 3.5, 3, chitin.light(0.15)); p.dot(27, 33, 0.9, bio)
            p.shape([(22, 28), (35, 33), (33, 20), (31, 30)], bone)  // scythe
            p.fill(p.ellipsePath(20, 16, 3, 3), tc.alpha(0.85))
        case "a_ravager":
            for x in [9, 15, 25, 31] as [CGFloat] { leg(p, (x, 2), (x, 10), chitin.dark(0.2), 2.5) }
            p.ellipse(20, 15, 15, 8, chitin.light(0.05))
            p.shape([(8, 20), (14, 28), (20, 21), (26, 29), (31, 20)], bone)    // dorsal plates
            p.ellipse(33, 14, 5, 5, chitin)
            p.shape([(34, 10), (40, 6), (38, 14)], bone)
            p.fill(p.ellipsePath(20, 14, 6, 3), tc.alpha(0.8))
        case "a_spinecaster":
            for x in [12, 18, 26] as [CGFloat] { leg(p, (x, 2), (x + 1, 10), chitin.dark(0.2), 2) }
            p.ellipse(19, 15, 12, 7, flesh.dark(0.25))
            for i in 0..<5 { let x = 10 + CGFloat(i) * 4; p.limb((x, 19), (x + 9, 30), bone, 1.4) }
            p.ellipse(31, 15, 4, 4, chitin); p.dot(33, 16, 1, bio)
            p.fill(p.ellipsePath(17, 14, 5, 2.5), tc.alpha(0.8))
        case "a_needleback":
            for x in [11, 17, 25, 29] as [CGFloat] { leg(p, (x, 2), (x, 9), chitin.dark(0.2), 2) }
            p.ellipse(20, 14, 13, 8, chitin.light(0.1))
            for i in 0..<7 { let x = 9 + CGFloat(i) * 3.6; p.limb((x, 19), (x + 2, 34), bone.mix(bio, 0.3), 1.1) }
            p.fill(p.ellipsePath(20, 13, 6, 3), tc.alpha(0.8))
        case "a_lifebinder":
            p.glow(20, 20, 18, bio.alpha(0.5))
            for i in 0..<5 { let x = 12 + CGFloat(i) * 4; p.limb((x, 14), (x + (i % 2 == 0 ? -2 : 2), 2), flesh.light(0.2), 1.3) }
            p.ellipse(20, 20, 11, 9, RGB(0.55, 0.85, 0.55, 0.95))
            p.ellipse(20, 22, 6, 5, bio.light(0.3)); p.fill(p.ellipsePath(20, 16, 6, 2), tc.alpha(0.8))
        case "a_shadeling":
            p.glow(20, 15, 15, RGB(0.4, 0.1, 0.5, 0.6))
            p.shape([(8, 4), (14, 22), (20, 30), (27, 22), (32, 4), (20, 10)], RGB(0.16, 0.08, 0.22))
            p.shape([(26, 20), (38, 26), (30, 16)], bone.dark(0.3)); p.shape([(14, 20), (2, 26), (10, 16)], bone.dark(0.3))
            p.dot(17, 24, 1.3, RGB(0.9, 0.3, 1)); p.dot(23, 24, 1.3, RGB(0.9, 0.3, 1))
            p.line((15, 14), (25, 14), tc, 1.4)
        case "a_skitter":
            bugLegs(p, 20, 8, 5, 9)
            p.ellipse(20, 13, 9, 5.5, chitin.light(0.2))
            p.ellipse(28, 13, 4, 3.5, chitin); p.dot(30, 14, 1, RGB(1, 0.3, 0.3))
            p.fill(p.ellipsePath(18, 14, 5, 2.4), tc.alpha(0.85))
        case "a_colossus":
            for x in [8, 15, 25, 32] as [CGFloat] { leg(p, (x, 1), (x, 11), chitin.dark(0.25), 4) }
            p.ellipse(20, 18, 17, 11, chitin.light(0.05))
            p.shape([(6, 24), (12, 36), (18, 27), (24, 37), (30, 26), (34, 32), (36, 20)], bone.dark(0.05))
            p.ellipse(34, 16, 6, 6, chitin.dark(0.1))
            p.shape([(36, 12), (40, 4), (40, 14)], bone); p.dot(37, 18, 1.2, bio)
            p.fill(p.ellipsePath(20, 16, 9, 4), tc.alpha(0.75))
        case "a_rupturer":
            for x in [10, 17, 24, 30] as [CGFloat] { leg(p, (x, 1), (x, 9), chitin.dark(0.2), 2.5) }
            p.ellipse(18, 18, 14, 10, flesh.dark(0.15))
            p.ellipse(16, 21, 9, 7, RGB(0.6, 0.85, 0.3, 0.9)); p.glow(16, 21, 10, bio.alpha(0.5))
            p.limb((26, 22), (37, 31), chitin, 3.5)
            p.fill(p.ellipsePath(18, 12, 7, 2.5), tc.alpha(0.8))
        case "a_seeder":
            leg(p, (16, 2), (17, 10), chitin, 2); leg(p, (24, 2), (23, 10), chitin, 2)
            p.ellipse(20, 14, 7, 6, flesh.dark(0.2))
            p.shape([(6, 22), (20, 34), (34, 22), (20, 18)], RGB(0.55, 0.3, 0.55))   // cap
            for i in 0..<4 { p.dot(11 + CGFloat(i) * 6, 25 + CGFloat(i % 2) * 3, 1.6, bio) }
            p.fill(p.ellipsePath(20, 13, 4, 2), tc.alpha(0.85))
        case "a_wisp":
            p.glow(20, 20, 14, bio.alpha(0.6))
            p.shape([(20, 20), (6, 34), (2, 22)], RGB(0.7, 0.95, 0.6, 0.85)); p.shape([(20, 20), (6, 6), (2, 18)], RGB(0.6, 0.9, 0.5, 0.75))
            p.ellipse(22, 20, 6, 3, chitin.light(0.3)); p.dot(27, 20.5, 1, tc)
        case "a_blightwing":
            p.shape([(2, 24), (14, 20), (20, 36), (24, 20), (38, 26), (30, 16), (20, 12), (10, 16)], chitin.light(0.1))
            p.ellipse(20, 19, 6, 5, flesh.dark(0.2)); p.glow(20, 15, 7, bio.alpha(0.7))
            p.line((10, 19), (30, 19), tc, 1.6)
        case "a_sporewing":
            for i in 0..<6 { let x = 10 + CGFloat(i) * 4; p.limb((x, 16), (x + (i % 2 == 0 ? -1.5 : 1.5), 4), flesh, 1.2) }
            p.ellipse(20, 24, 15, 11, RGB(0.6, 0.4, 0.6))
            for (x, y) in [(13, 27), (20, 30), (27, 26), (17, 21), (25, 20)] as [(CGFloat, CGFloat)] { p.dot(x, y, 1.8, bio) }
            p.fill(p.ellipsePath(20, 16, 10, 2.6), tc.alpha(0.8))

        default:
            p.ellipse(20, 15, 10, 8, RGB(0.6, 0.6, 0.6))
        }
    }

    // MARK: Shared parts

    static func soldierBase(_ p: Pen, body: RGB, tc: RGB, helmet: RGB, slim: Bool = false, bulky: Bool = false, visor: RGB = amber) {
        let bw: CGFloat = bulky ? 7 : (slim ? 4.5 : 5.5)
        leg(p, (18, 3), (18.5, 11), darkSteel, slim ? 1.8 : 2.2); leg(p, (22, 3), (21.5, 11), darkSteel, slim ? 1.8 : 2.2)
        p.shade(p.roundRectPath(20 - bw, 10, bw * 2, 13, 2.5), body)
        p.fill(p.roundRectPath(20 - bw, 19, bw * 2, 3, 1), tc)                 // team chest band
        p.ellipse(20.5, 26, 4.2, 4, skin.dark(0.1))
        p.shade(p.poly([(15.6, 26), (16.5, 30.5), (21, 31.5), (25, 29.5), (25, 26.5)]), helmet)
        p.fill(p.roundRectPath(21, 25.2, 4.2, 1.8, 0.8), visor)
    }

    static func wheel(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        p.ellipse(x, y, r, r, RGB(0.12, 0.12, 0.13))
        let a = CGFloat(phase) * .pi / 4
        p.line((x - cos(a) * r * 0.7, y - sin(a) * r * 0.7), (x + cos(a) * r * 0.7, y + sin(a) * r * 0.7), RGB(0.45, 0.45, 0.47), 1)
        p.dot(x, y, r * 0.35, RGB(0.55, 0.55, 0.55))
    }

    static func tracks(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        p.box(x, y, w, h, RGB(0.14, 0.14, 0.15), r: h / 2)
        for i in 0..<Int(w / 4.5) { p.dot(x + 3 + CGFloat(i) * 4.5 + CGFloat(phase) * 1.1, y + h / 2, 1.3, RGB(0.4, 0.4, 0.42)) }
    }

    static func bugLegs(_ p: Pen, _ cx: CGFloat, _ cy: CGFloat, _ spread: CGFloat, _ len: CGFloat) {
        for i in 0..<3 {
            let o = CGFloat(i - 1) * spread
            let k = CGFloat([0, 1.6, 0, -1.6][(phase + i * 2) % 4])
            p.limb((cx + o, cy + 3), (cx + o - 3 + k, cy - len * 0.7), chitin.dark(0.3), 1.3)
            p.limb((cx + o, cy + 3), (cx + o + 3 - k, cy - len * 0.7), chitin.dark(0.3), 1.3)
        }
    }
}
