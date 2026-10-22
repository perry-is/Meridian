import CoreGraphics

/// Terran Concord: practical combined-arms soldiers and armour. Olive and sand plating, steel,
/// amber visors and lamps; the team colour sits on shoulder pauldrons, helmet stripes and hull bands.
extension UnitArt {
    static let sand = RGB(0.66, 0.60, 0.44), fatigue = RGB(0.36, 0.40, 0.30), gunmetal = RGB(0.22, 0.23, 0.25)
    static let boot = RGB(0.20, 0.17, 0.14), glove = RGB(0.24, 0.22, 0.20), wood = RGB(0.52, 0.36, 0.20)

    // MARK: Soldier body (base layer)

    struct Trooper {
        var armor = UnitArt.olive
        var cloth = UnitArt.fatigue
        var helmet = UnitArt.olive.dark(0.1)
        var visor = UnitArt.amber
        var bulk: CGFloat = 1
        var pack: RGB? = UnitArt.fatigue.dark(0.15)
        var hood = false
    }

    /// Legs, torso, pack and helmeted head. The shoulder (arms, pauldron, weapon) is the upper layer.
    static func trooper(_ p: Pen, _ t: Trooper, _ tc: RGB) {
        let b = t.bulk
        func legPair(_ offset: CGFloat, _ shade: CGFloat) {
            let a = ang(offset)
            let hip: (CGFloat, CGFloat) = (19.6 + (offset > 0 ? -0.8 : 0.6), 13.2)
            let fx = hip.0 + sin(a) * 2.9, fy = 3.4 + max(0, cos(a)) * 1.5
            let knee: (CGFloat, CGFloat) = ((hip.0 + fx) / 2 + 1.3 + max(0, cos(a)) * 1.1, (hip.1 + fy) / 2 + 0.6)
            let cloth = t.cloth.dark(shade)
            p.capsule(hip, knee, 1.75 * b, 1.45 * b, cloth)
            p.capsule(knee, (fx, fy + 1.3), 1.45 * b, 1.15 * b, cloth.dark(0.05))
            p.ball(knee.0 + 0.3, knee.1, 1.15, 1.05, t.armor.dark(shade), lw: 0.5, shine: 0.3)              // knee pad
            p.solid(p.roundRectPath(fx - 1.4, fy - 0.2, 3.9, 1.9, 0.8), boot.dark(shade))                    // boot
        }
        legPair(0.5, 0.22)
        if let pk = t.pack {
            p.block(12.4, 14.2, 4.6, 8.6, depth: 1.6, pk)
            p.seam((12.8, 18.4), (16.6, 18.4), pk)
            p.solid(p.roundRectPath(13.2, 13.4, 3.2, 2, 0.8), pk.dark(0.15))                                 // bedroll
        }
        // Torso: armoured vest over fatigues.
        let torso = p.poly([(15.4, 13.4), (23.4, 13.4), (24.6, 21.8), (22.2, 24.4), (16.4, 24.4), (14.6, 20.2)])
        p.solid(torso, t.cloth)
        let vest = p.poly([(16.2, 15.2), (23.6, 15.2), (24.4, 21.4), (22, 23.6), (17, 23.6), (15.6, 19.6)])
        p.solid(vest, t.armor, contrast: 1.1)
        p.seam((17.2, 19.4), (23.9, 19.4), t.armor)
        p.solid(p.roundRectPath(22.2, 16.2, 2.4, 2.4, 0.6), t.armor.dark(0.18), lw: 0.5)                       // chest pouch
        p.solid(p.roundRectPath(15.2, 13.0, 9.2, 1.8, 0.6), gunmetal.light(0.1), lw: 0.5)                    // belt
        p.rivets([(17, 13.9), (20, 13.9), (23, 13.9)], gunmetal)
        legPair(0, 0)
        // Head.
        p.ball(21.9, 26.4, 2.1, 2.0, skin.dark(0.08), lw: 0.6, shine: 0.2)                                    // face
        if t.hood {
            p.solid(p.poly([(16.8, 25.2), (17.6, 30.6), (21.6, 31.6), (25.2, 29.4), (25.2, 26.6), (22, 27.4), (19.2, 24.6)]), t.helmet)
        } else {
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: 16.6, y: 26.2))
            dome.addCurve(to: CGPoint(x: 25.6, y: 27.0), control1: CGPoint(x: 16.8, y: 32.6), control2: CGPoint(x: 25.2, y: 32.4))
            dome.addLine(to: CGPoint(x: 26.0, y: 26.4)); dome.addLine(to: CGPoint(x: 16.4, y: 25.6)); dome.closeSubpath()
            p.solid(dome, t.helmet, contrast: 1.2)
            p.line((17.4, 28.6), (24.4, 29.6), tc, 0.9)                                                     // team stripe
        }
        p.solid(p.roundRectPath(21.6, 25.6, 4.0, 1.6, 0.7), gunmetal, lw: 0.5)
        p.lamp(24.2, 26.4, 0.55, t.visor)
        p.fill(p.roundRectPath(21.9, 25.9, 3.4, 0.55, 0.25), t.visor.alpha(0.9))
    }

    // MARK: Arms and weapons (upper layer). Shoulder pivot ≈ (20.8, 22).

    static let shoulder: (CGFloat, CGFloat) = (20.8, 22.0)

    /// Arm from the shoulder through an elbow to a gloved hand.
    static func arm(_ p: Pen, _ sleeve: RGB, elbow: (CGFloat, CGFloat), hand: (CGFloat, CGFloat), from s: (CGFloat, CGFloat) = UnitArt.shoulder, back: Bool = false) {
        let c = back ? sleeve.dark(0.25) : sleeve
        p.capsule(s, elbow, 1.45, 1.2, c, lw: 0.6)
        p.capsule(elbow, hand, 1.2, 1.0, c.dark(0.05), lw: 0.6)
        p.ball(hand.0, hand.1, 1.05, 0.95, glove.dark(back ? 0.2 : 0), lw: 0.5, shine: 0.2)
    }

    static func pauldron(_ p: Pen, _ tc: RGB, at s: (CGFloat, CGFloat) = UnitArt.shoulder) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: s.0 - 2.6, y: s.1 - 1.2))
        path.addCurve(to: CGPoint(x: s.0 + 2.8, y: s.1 - 1.0), control1: CGPoint(x: s.0 - 2.4, y: s.1 + 3.0), control2: CGPoint(x: s.0 + 2.8, y: s.1 + 2.6))
        path.closeSubpath()
        p.solid(path, tc, contrast: 1.1)
        p.line((s.0 - 2.0, s.1 - 0.6), (s.0 + 2.2, s.1 - 0.4), tc.dark(0.4), 0.45)
    }

    /// Long arm: stock at x0, muzzle at x1, bore height y.
    static func longGun(_ p: Pen, _ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, body: RGB = UnitArt.gunmetal, furniture: RGB = UnitArt.fatigue.dark(0.2), scope: Bool = false, mag: Bool = true, barrelR: CGFloat = 0.55) {
        let len = x1 - x0
        p.solid(p.poly([(x0, y - 1.6), (x0 + 0.6, y + 0.9), (x0 + len * 0.22, y + 0.7), (x0 + len * 0.22, y - 0.6)]), furniture, lw: 0.55)   // stock
        p.block(x0 + len * 0.2, y - 0.9, len * 0.36, 2.1, depth: 0.9, body, bevel: 0.4)                                  // receiver
        p.tube(x0 + len * 0.55, x1, y + 0.2, barrelR, body.light(0.1))
        p.solid(p.roundRectPath(x0 + len * 0.5, y - 0.7, len * 0.22, 1.5, 0.5), furniture, lw: 0.5)                     // handguard
        if mag { p.solid(p.poly([(x0 + len * 0.38, y - 0.9), (x0 + len * 0.47, y - 0.9), (x0 + len * 0.44, y - 3.6), (x0 + len * 0.35, y - 3.4)]), body.dark(0.1), lw: 0.5) }
        if scope {
            p.tube(x0 + len * 0.3, x0 + len * 0.55, y + 2.0, 0.6, body.dark(0.2), cap: false)
            p.dot(x0 + len * 0.55, y + 2.0, 0.45, RGB(0.5, 0.85, 1, 0.9))
        }
    }

    // MARK: Base and upper dispatch for Concord

    static func concordBase(_ id: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "h_engineer":
            trooper(p, Trooper(armor: sand.mix(RGB(0.8, 0.6, 0.2), 0.25), cloth: RGB(0.40, 0.36, 0.28), helmet: RGB(1.0, 0.70, 0.12), pack: nil), tc)
            // Welding rig on the back.
            p.block(12.0, 14.0, 4.8, 9.2, depth: 1.6, RGB(0.42, 0.40, 0.34))
            p.tube(12.6, 16.4, 22.4, 0.9, RGB(0.75, 0.25, 0.18), cap: false)
            p.solid(p.roundRectPath(15.0, 15.2, 1.8, 3.6, 0.6), steel, lw: 0.5)
        case "h_pathfinder":
            trooper(p, Trooper(armor: fatigue.mix(sand, 0.35), cloth: fatigue.mix(sand, 0.2), helmet: fatigue.dark(0.05), bulk: 0.9, pack: fatigue.dark(0.25)), tc)
            p.limb((13.6, 22.4), (12.2, 36.5), gunmetal, 0.6); p.lamp(12.2, 36.8, 0.6, RGB(1, 0.3, 0.25))
        case "h_ranger":
            trooper(p, Trooper(), tc)
        case "h_breacher":
            trooper(p, Trooper(armor: olive.dark(0.05), cloth: fatigue.dark(0.1), helmet: gunmetal.light(0.15), visor: RGB(1, 0.55, 0.2), bulk: 1.15, pack: nil), tc)
            // Heavy riot shield carried in front.
            let shield = p.poly([(26.2, 6.6), (32.6, 8.0), (33.4, 27.4), (26.6, 30.0)])
            p.solid(shield, steel.dark(0.12), contrast: 1.2)
            p.solid(p.poly([(26.2, 6.6), (27.2, 6.4), (27.6, 30.0), (26.6, 30.0)]), steel.dark(0.4), lw: 0.5)
            p.fill(p.roundRectPath(28.4, 21.2, 4.0, 1.4, 0.6), RGB(0.3, 0.55, 0.7, 0.85))                     // vision slit
            p.line((27.6, 12.6), (32.6, 13.2), tc, 1.3); p.line((27.6, 16.4), (32.8, 16.8), tc, 1.3)
            p.rivets([(28, 9), (32, 9.8), (28.2, 27.8), (32.6, 26.4)], steel)
        case "h_lancer":
            trooper(p, Trooper(pack: RGB(0.33, 0.38, 0.29)), tc)
            for k in 0..<2 { p.tube(12.6, 15.6, 15.5 + CGFloat(k) * 3.2, 1.2, RGB(0.36, 0.40, 0.30)) }       // spare rockets
        case "h_skyguard":
            trooper(p, Trooper(armor: olive.mix(steel, 0.35), cloth: fatigue.mix(steel, 0.2), helmet: steel.dark(0.1), pack: steel.dark(0.3)), tc)
            p.limb((13.8, 22.8), (14.4, 29.4), gunmetal, 0.5); p.ball(14.6, 30.0, 1.4, 0.8, steel, lw: 0.4)     // radar
        case "h_medic":
            trooper(p, Trooper(armor: RGB(0.88, 0.88, 0.84), cloth: RGB(0.62, 0.64, 0.6), helmet: RGB(0.92, 0.92, 0.9), visor: RGB(0.5, 1, 0.65), pack: RGB(0.9, 0.9, 0.86)), tc)
            p.fill(p.roundRectPath(13.6, 16.6, 1.6, 4.6, 0.3), RGB(0.85, 0.15, 0.15)); p.fill(p.roundRectPath(12.2, 18.1, 4.4, 1.6, 0.3), RGB(0.85, 0.15, 0.15))
            p.fill(p.roundRectPath(19.0, 19.6, 1.0, 2.6, 0.2), RGB(0.85, 0.15, 0.15)); p.fill(p.roundRectPath(18.2, 20.4, 2.6, 1.0, 0.2), RGB(0.85, 0.15, 0.15))
        case "h_ghost":
            trooper(p, Trooper(armor: RGB(0.18, 0.2, 0.24), cloth: RGB(0.13, 0.14, 0.17), helmet: RGB(0.12, 0.13, 0.16), visor: RGB(0.4, 1, 0.9), bulk: 0.9, pack: nil, hood: true), tc)
            let cloak = p.poly([(15.0, 23.6), (11.0, 8.6), (13.6, 10.4), (15.0, 8.8), (17.0, 13.2)])
            p.solid(cloak, RGB(0.15, 0.16, 0.2, 0.92), contrast: 0.6)
        case "h_buggy":
            for (x, back) in [(9.0, true), (30.0, false)] as [(CGFloat, Bool)] { offroadWheel(p, x, 6.6, 4.8, dim: back ? 0.1 : 0) }
            let hull = p.poly([(3.2, 9.0), (36.8, 9.0), (35.6, 14.6), (28.0, 18.4), (10.0, 18.4), (4.4, 14.4)])
            p.solid(hull, olive, contrast: 1.1)
            p.solid(p.poly([(10.0, 18.4), (28.0, 18.4), (30.0, 19.6), (12.0, 19.6)]), olive.light(0.25), contrast: 0.4)   // deck
            p.line((6.0, 12.0), (34.0, 12.0), tc, 1.6)
            p.seam((14.0, 10.0), (14.6, 17.8), olive); p.seam((26.0, 10.0), (25.6, 17.8), olive)
            // Roll cage and driver.
            p.limb((12.6, 19.0), (14.6, 24.6), gunmetal, 0.7); p.limb((14.6, 24.6), (21.6, 24.8), gunmetal, 0.7); p.limb((21.6, 24.8), (24.4, 19.2), gunmetal, 0.7)
            p.ball(17.6, 21.6, 1.8, 1.7, RGB(1.0, 0.7, 0.12), lw: 0.5)
            p.lamp(36.0, 11.6, 0.7, amber)
            p.rivets([(8, 10.6), (32, 10.6)], olive)
        case "h_bastion":
            tankTracks(p, 1.6, 2.6, 36.8, 9.6, olive.dark(0.25))
            let hull = p.poly([(2.4, 11.6), (34.0, 11.6), (38.2, 15.0), (36.6, 20.2), (4.6, 20.2)])
            p.solid(hull, olive, contrast: 1.1)
            p.solid(p.poly([(4.6, 20.2), (36.6, 20.2), (37.6, 21.4), (6.0, 21.4)]), olive.light(0.25), contrast: 0.4)
            p.solid(p.poly([(34.0, 11.6), (38.2, 15.0), (36.6, 20.2), (34.2, 20.2)]), olive.dark(0.15), contrast: 0.5)  // glacis
            p.line((5.0, 15.2), (33.0, 15.2), tc, 2.0)
            p.seam((12.0, 12.4), (12.0, 19.6), olive); p.seam((24.0, 12.4), (24.0, 19.6), olive)
            p.rivets([(6, 18.6), (10, 18.6), (28, 18.6), (32, 18.6)], olive)
            p.lamp(37.4, 17.4, 0.6, amber)
        case "h_mortar":
            tankTracks(p, 2.6, 2.6, 34.6, 9.0, olive.dark(0.25))
            p.block(3.4, 11.2, 31.0, 8.2, depth: 2.4, olive)
            p.line((5.6, 14.4), (32.4, 14.4), tc, 1.8)
            p.block(24.6, 19.4, 8.4, 3.0, depth: 1.4, gunmetal.light(0.2))                                       // ammo rack
            for k in 0..<4 { p.ball(26.0 + CGFloat(k) * 2.0, 23.6, 0.8, 1.3, RGB(0.66, 0.58, 0.32), lw: 0.4) }
            p.rivets([(6, 18), (12, 18), (18, 18)], olive)
        case "h_minelayer":
            tankTracks(p, 2.6, 2.6, 34.6, 9.0, olive.dark(0.25))
            p.block(3.4, 11.2, 31.0, 9.6, depth: 2.6, olive.mix(sand, 0.3))
            p.line((5.6, 15.0), (32.4, 15.0), tc, 1.8)
            for i in 0..<3 {
                let x = 8 + CGFloat(i) * 6
                p.ball(x, 22.4, 2.5, 1.3, RGB(0.26, 0.27, 0.22), lw: 0.5, shine: 0.3); p.lamp(x, 23.0, 0.35, RGB(1, 0.3, 0.2))
            }
        case "h_kestrel":
            jet(p, body: steel, wing: steel.dark(0.15), tc: tc, canopy: RGB(0.35, 0.6, 0.8), length: 36, sweep: 0.9)
        case "h_harrier":
            jet(p, body: gunmetal.light(0.25), wing: olive, tc: tc, canopy: RGB(0.35, 0.55, 0.65), length: 37, sweep: 0.55, heavy: true)
        case "h_dropship":
            p.solid(p.ellipsePath(20, 19.6, 15.6, 6.8), olive.mix(steel, 0.4), contrast: 1.1)
            p.solid(p.poly([(6.0, 22.0), (34.0, 22.0), (31.0, 25.6), (9.0, 25.6)]), olive.mix(steel, 0.2).light(0.15), contrast: 0.5)
            p.fill(p.roundRectPath(25.6, 19.4, 7.4, 3.2, 1.4), RGB(0.30, 0.55, 0.72, 0.95))                    // cockpit
            p.line((7.0, 16.6), (33.0, 16.6), tc, 2.0)
            p.seam((13, 13.4), (13, 22), steel); p.seam((20, 13), (20, 22.4), steel)
            for (cx, k) in [(6.6, 0), (33.4, 1)] as [(CGFloat, Int)] {
                p.block(cx - 4.2, 22.4, 8.4, 3.6, depth: 1.4, gunmetal)
                let a = CGFloat(phase + k * 3) * .pi / 4
                p.fill(p.ellipsePath(cx, 28.8, 8.6, 2.0), RGB(0.85, 0.88, 0.9, 0.18))
                p.line((cx - cos(a) * 8.4, 28.8 - sin(a) * 1.9), (cx + cos(a) * 8.4, 28.8 + sin(a) * 1.9), RGB(0.18, 0.18, 0.2, 0.85), 1.0)
                p.ball(cx, 28.8, 0.9, 0.6, steel, lw: 0.4)
            }
            p.lamp(4.6, 19.6, 0.5, RGB(1, 0.3, 0.25)); p.lamp(35.4, 19.6, 0.5, RGB(0.3, 1, 0.45))
        default: return false
        }
        return true
    }

    static func concordUpper(_ id: String, _ v: String, _ p: Pen, _ tc: RGB) -> Bool {
        switch id {
        case "h_engineer":
            let sl = RGB(0.40, 0.36, 0.28)
            switch v {
            case "wood":
                arm(p, sl, elbow: (22.6, 24.6), hand: (24.8, 25.6), back: true)
                p.capsule((23.0, 24.0), (31.4, 30.2), 0.55, 0.55, wood)
                p.solid(p.poly([(29.6, 31.6), (33.6, 27.8), (35.2, 31.2), (32.4, 33.4)]), steel.light(0.15), contrast: 1.3)
                p.line((33.8, 28.4), (35.0, 31.0), RGB(1, 1, 1, 0.8), 0.5)
                arm(p, sl, elbow: (23.6, 23.2), hand: (26.4, 26.8))
            case "ore":
                arm(p, sl, elbow: (22.6, 24.6), hand: (24.8, 25.6), back: true)
                p.capsule((23.0, 24.0), (31.0, 30.0), 0.55, 0.55, wood)
                p.capsule((27.6, 33.0), (34.6, 26.6), 0.75, 0.45, steel)
                arm(p, sl, elbow: (23.6, 23.2), hand: (26.4, 26.8))
            case "build":
                arm(p, sl, elbow: (22.8, 23.4), hand: (25.4, 24.4), back: true)
                p.capsule((24.6, 23.6), (30.2, 27.6), 0.5, 0.5, wood)
                p.block(28.6, 27.0, 4.2, 2.6, depth: 1.0, gunmetal.light(0.25))
                arm(p, sl, elbow: (23.4, 22.4), hand: (26.6, 25.2))
            default:
                arm(p, sl, elbow: (22.0, 18.0), hand: (24.6, 17.0), back: true)
                p.capsule((24.4, 17.0), (30.2, 14.8), 0.75, 0.75, steel)
                p.stroke(p.ellipsePath(31.2, 14.4, 1.5, 1.5), steel.dark(0.1), 1.0)
                arm(p, sl, elbow: (22.6, 17.8), hand: (25.8, 17.4))
            }
            pauldron(p, tc)
        case "h_pathfinder":
            let sl = fatigue.mix(sand, 0.2)
            arm(p, sl, elbow: (22.0, 18.6), hand: (24.6, 19.6), back: true)
            longGun(p, 20.0, 32.4, 20.0, scope: false, barrelR: 0.45)
            p.solid(p.roundRectPath(25.6, 21.0, 2.6, 1.0, 0.4), gunmetal, lw: 0.4)
            arm(p, sl, elbow: (23.0, 18.6), hand: (27.6, 19.6))
            pauldron(p, tc)
        case "h_ranger":
            arm(p, fatigue, elbow: (22.0, 18.4), hand: (24.8, 19.4), back: true)
            longGun(p, 19.0, 35.8, 19.8, scope: true)
            arm(p, fatigue, elbow: (23.4, 18.2), hand: (29.0, 19.4))
            pauldron(p, tc)
        case "h_breacher":
            arm(p, fatigue.dark(0.1), elbow: (22.4, 18.0), hand: (25.0, 18.6), back: true)
            longGun(p, 20.4, 35.6, 18.8, furniture: wood.dark(0.1), mag: false, barrelR: 0.9)
            p.solid(p.roundRectPath(29.0, 16.6, 4.6, 1.6, 0.6), wood, lw: 0.5)                                  // pump
            arm(p, fatigue.dark(0.1), elbow: (24.0, 17.6), hand: (31.0, 17.4))
            pauldron(p, tc)
        case "h_lancer":
            let s: (CGFloat, CGFloat) = (20.2, 23.2)
            arm(p, fatigue, elbow: (22.4, 21.0), hand: (24.0, 22.4), from: s, back: true)
            p.tube(8.0, 36.4, 25.0, 2.6, RGB(0.36, 0.40, 0.30))
            p.solid(p.roundRectPath(8.0, 22.6, 3.6, 4.8, 1.0), gunmetal, lw: 0.5)                              // exhaust
            p.block(23.0, 27.4, 4.0, 1.8, depth: 0.8, gunmetal)                                                  // sight
            p.line((11.0, 25.0), (16.0, 25.0), tc, 1.2)
            p.fill(p.ellipsePath(36.2, 25.0, 1.4, 2.2), RGB(0.6, 0.15, 0.1))                                     // warhead
            arm(p, fatigue, elbow: (23.0, 20.4), hand: (25.8, 22.4), from: s)
            pauldron(p, tc, at: s)
        case "h_skyguard":
            let sl = fatigue.mix(steel, 0.2); let s: (CGFloat, CGFloat) = (20.2, 22.6)
            arm(p, sl, elbow: (22.0, 21.0), hand: (23.0, 24.0), from: s, back: true)
            let pod = p.poly([(11.6, 19.6), (23.6, 33.6), (29.6, 29.6), (17.6, 15.8)])
            p.solid(pod, RGB(0.32, 0.36, 0.30), contrast: 1.1)
            for k in 0..<3 {
                let t = CGFloat(k) / 2
                let x = 21.4 + t * 3.2, y = 29.4 - t * 2.6
                p.ball(x + 2.0, y + 2.4, 1.1, 1.1, RGB(0.1, 0.1, 0.1), lw: 0.4, shine: 0); p.dot(x + 2.0, y + 2.4, 0.5, RGB(1, 0.4, 0.2))
            }
            p.line((14.0, 20.0), (19.0, 17.4), tc, 1.0)
            arm(p, sl, elbow: (22.6, 20.2), hand: (24.6, 23.0), from: s)
            pauldron(p, tc, at: s)
        case "h_medic":
            let sl = RGB(0.62, 0.64, 0.6)
            arm(p, sl, elbow: (22.0, 18.0), hand: (24.0, 18.8), back: true)
            p.block(24.0, 17.8, 6.0, 2.2, depth: 0.8, gunmetal.light(0.15))
            p.tube(29.0, 31.4, 19.0, 0.5, steel)
            p.lamp(31.6, 19.0, 0.5, RGB(0.4, 1, 0.55))
            arm(p, sl, elbow: (23.0, 18.0), hand: (26.4, 18.8))
            pauldron(p, tc)
        case "h_ghost":
            let sl = RGB(0.13, 0.14, 0.17)
            arm(p, sl, elbow: (22.0, 18.6), hand: (24.8, 19.8), back: true)
            longGun(p, 19.0, 38.6, 20.0, body: RGB(0.15, 0.15, 0.18), furniture: RGB(0.1, 0.1, 0.12), scope: true, barrelR: 0.45)
            p.lamp(30.6, 22.0, 0.35, RGB(0.4, 1, 0.9))
            arm(p, sl, elbow: (23.6, 18.6), hand: (30.0, 19.6))
            pauldron(p, tc.dark(0.3))
        case "h_buggy":
            p.limb((22.0, 19.6), (22.0, 21.6), gunmetal, 0.8)
            p.block(18.4, 20.4, 8.4, 3.6, depth: 1.4, gunmetal.light(0.1))
            p.tube(25.6, 36.6, 23.2, 0.55, gunmetal.light(0.15)); p.tube(25.6, 36.6, 21.4, 0.55, gunmetal.light(0.15))
            p.solid(p.roundRectPath(18.0, 18.6, 2.6, 3.2, 0.5), RGB(0.55, 0.45, 0.25), lw: 0.4)                 // ammo can
            p.lamp(20.0, 24.4, 0.4, amber)
        case "h_bastion":
            let turret = p.poly([(10.6, 20.8), (28.6, 20.8), (30.6, 24.4), (27.4, 28.8), (13.6, 28.8), (10.0, 25.6)])
            p.solid(turret, olive.light(0.04), contrast: 1.15)
            p.solid(p.poly([(13.6, 28.8), (27.4, 28.8), (28.4, 29.8), (14.8, 29.8)]), olive.light(0.3), contrast: 0.4)
            p.tube(29.0, 39.6, 24.6, 1.25, gunmetal.light(0.1))
            p.block(36.4, 23.2, 3.4, 2.8, depth: 0.8, gunmetal)                                                 // muzzle brake
            p.ball(16.4, 29.8, 2.2, 0.9, olive.dark(0.15), lw: 0.5)                                            // hatch
            p.limb((13.0, 28.6), (11.4, 36.4), gunmetal, 0.4)
            p.line((12.6, 24.0), (28.0, 24.0), tc, 1.4)
            p.seam((20.0, 21.4), (20.0, 28.2), olive)
            p.lamp(25.6, 27.0, 0.45, amber)
        case "h_mortar":
            p.block(13.0, 17.6, 9.6, 4.2, depth: 1.4, gunmetal.light(0.15))
            p.tube(15.0, 31.8, 20.8, 2.2, darkSteel)
            p.solid(p.roundRectPath(17.2, 18.2, 3.0, 5.2, 0.8), gunmetal, lw: 0.5)                              // band
            p.line((22.0, 20.8), (27.0, 20.8), tc, 1.0)
        case "h_minelayer":
            p.block(22.0, 19.6, 6.6, 3.6, depth: 1.2, gunmetal.light(0.1))
            p.tube(27.6, 37.8, 21.6, 0.6, gunmetal.light(0.15))
        default: return false
        }
        return true
    }

    // MARK: Concord vehicle parts

    static func offroadWheel(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, dim: CGFloat = 0) {
        p.ball(x, y, r, r, RGB(0.10, 0.10, 0.11).dark(dim), lw: 0.6, shine: 0.15)
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * .pi * 2 + CGFloat(phase) * .pi / 16
            p.line((x + cos(a) * r * 0.78, y + sin(a) * r * 0.78), (x + cos(a) * r * 0.98, y + sin(a) * r * 0.98), RGB(0.3, 0.3, 0.32), 0.8)
        }
        p.ball(x, y, r * 0.48, r * 0.48, RGB(0.55, 0.55, 0.52).dark(dim), lw: 0.5, shine: 0.4)
        let a = CGFloat(phase) * .pi / 8
        for k in 0..<3 { let b = a + CGFloat(k) * 2.094; p.dot(x + cos(b) * r * 0.28, y + sin(b) * r * 0.28, 0.35, RGB(0.25, 0.25, 0.25)) }
    }

    /// Track assembly: belt, road wheels and an armoured side skirt with the hull colour.
    static func tankTracks(_ p: Pen, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ skirt: RGB) {
        p.solid(p.roundRectPath(x, y, w, h, h / 2), RGB(0.14, 0.14, 0.15), contrast: 0.6)
        let step: CGFloat = 2.4
        for i in 0..<Int(w / step) {
            let tx = x + 1.2 + (CGFloat(i) * step + CGFloat(phase) * step / 8).truncatingRemainder(dividingBy: w - 2.4)
            p.line((tx, y + 0.3), (tx, y + 1.2), RGB(0.38, 0.38, 0.4), 0.8)
        }
        let n = max(3, Int(w / 6.4))
        for k in 0..<n { offroadWheel(p, x + h * 0.5 + CGFloat(k) * (w - h) / CGFloat(n - 1), y + h * 0.45, h * 0.3) }
        p.solid(p.poly([(x + 1.0, y + h * 0.62), (x + w - 1.0, y + h * 0.62), (x + w - 2.4, y + h + 0.6), (x + 2.4, y + h + 0.6)]), skirt, contrast: 0.7)
        p.rivets(stride(from: x + 4, to: x + w - 3, by: 5).map { ($0, y + h * 0.82) }, skirt)
    }

    /// Fast jet seen from above at an angle (nose to the right).
    static func jet(_ p: Pen, body: RGB, wing: RGB, tc: RGB, canopy: RGB, length: CGFloat, sweep: CGFloat, heavy: Bool = false) {
        let x0 = (40 - length) / 2, x1 = x0 + length
        p.solid(p.poly([(x0 + 10, 21.6), (x0 + 22, 21.6), (x0 + 22 - 12 * sweep, 36.0), (x0 + 15 - 10 * sweep, 36.0)]), wing.dark(0.12), contrast: 0.8)   // far wing
        p.solid(p.poly([(x0, 18.2), (x0 + 4, 16.2), (x1 - 8, 16.6), (x1, 20.0), (x1 - 8, 23.4), (x0 + 4, 23.6), (x0, 21.6)]), body, contrast: 1.2)
        p.solid(p.poly([(x0 + 10, 18.6), (x0 + 23, 18.6), (x0 + 23 - 13 * sweep, 3.6), (x0 + 15 - 11 * sweep, 3.6)]), wing, contrast: 1.0)        // near wing
        p.solid(p.poly([(x0 + 1, 21.4), (x0 + 6, 21.4), (x0 + 2.4, 28.6), (x0 + 0.2, 28.6)]), wing.dark(0.05), contrast: 0.8)                      // tail fin
        p.fill(p.roundRectPath(x1 - 13, 19.4, 6.4, 2.4, 1.2), canopy.alpha(0.95)); p.line((x1 - 12.4, 21.2), (x1 - 8, 21.4), RGB(1, 1, 1, 0.6), 0.4)
        p.line((x0 + 6, 20.2), (x1 - 14, 20.2), tc, 1.4)
        p.line((x0 + 15 - 10 * sweep, 6.6), (x0 + 22 - 12 * sweep, 6.6), tc, 1.0)
        if heavy { for k in 0..<2 { p.ball(x0 + 16 - CGFloat(k) * 4 * sweep, 10.4 - CGFloat(k) * 3, 2.0, 1.3, gunmetal, lw: 0.5) } }
        p.lamp(x0 + 0.4, 20.0, 1.0, RGB(1, 0.6, 0.25))
    }
}
