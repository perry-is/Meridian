import SpriteKit
import MeridianCore

/// Working buildings: moving parts that show what each structure does and whether it is busy.
/// Parts are a handful of child sprites per building, created on completion; most motion is a few
/// trig calls per frame. Motion speeds up while the building is producing and stops when it is idle,
/// so animation stays purposeful rather than constant.
extension GameScene {

    /// Local offset (relative to the footprint centre) of an art-space point P(u, v, z) for a footprint of n tiles.
    @inline(__always) func loc(_ u: CGFloat, _ v: CGFloat, _ z: CGFloat, _ n: CGFloat) -> CGPoint {
        let p = WorldArt.P(u, v, z, n)
        return CGPoint(x: p.0 - 32 * n, y: p.1 - 16 * n)
    }

    func part(_ v: EntityView, _ key: String, _ make: () -> SKSpriteNode) -> SKSpriteNode {
        if let p = v.parts[key] { return p }
        let p = make()
        v.root.addChild(p)
        v.parts[key] = p
        return p
    }

    func glowDot(_ c: SKColor, _ size: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(texture: bank.fx["glow"], size: CGSize(width: size, height: size))
        s.blendMode = .add; s.colorBlendFactor = 1; s.color = c
        return s
    }

    func animateParts(_ e: Entity, _ v: EntityView, _ d: BuildingDef, _ t: Double, busy: Bool) {
        // Moving parts are placed to match the procedural drawings; 3D Concord and Lattice buildings skip them
        // (their beacons still pulse via BuildingArt.lights). Brood breathing is generic and stays.
        if d.faction != .aliens && BuildingModels.meta(d.id) != nil { return }
        let n = CGFloat(d.size)
        let seed = Double(e.id % 17)
        let near = zoom < 2.4 && onScreen(v.root.position)
        v.partT -= 1.0 / 60
        switch (d.faction, d.kind) {

        // MARK: Concord
        case (.humans, .hq), (.humans, .research):
            // Radar sweeps continuously (faster when the building is working).
            let at = d.kind == .hq ? loc(n * 0.5, n * 0.5, 78, n) + CGPoint(x: 12, y: -4) : loc(n - 0.5, n - 0.5, 18, n)
            let dish = part(v, "dish") {
                let s = SKSpriteNode(texture: bank.fx["dish"]); s.anchorPoint = CGPoint(x: 0.5, y: 0.07); s.zPosition = 0.2
                s.setScale(d.kind == .hq ? 0.85 : 0.75)
                return s
            }
            dish.position = at
            let a = t * (busy ? 1.6 : 0.8) + seed
            let c = CGFloat(cos(a))
            dish.xScale = (d.kind == .hq ? 0.85 : 0.75) * (abs(c) < 0.2 ? (c < 0 ? -0.2 : 0.2) : c)
            if d.kind == .research && busy && near && v.partT <= 0 {
                // Telescope survey flashes while researching.
                v.partT = 1.1
                let tip = loc(n * 0.48, n * 0.5, 18, n) + CGPoint(x: 14, y: 44)
                puff("glow", at: v.root.position + tip, size: CGSize(width: 16, height: 16), color: SKColor(red: 0.55, green: 0.9, blue: 1, alpha: 1), z: 456, life: 0.5, grow: 2)
            }
        case (.humans, .infantry):
            // The team flag streams downwind.
            let pole = loc(n - 0.5, n - 0.5, 0, n)
            let f = part(v, "flag") {
                let s = SKSpriteNode(texture: bank.fx["flag"]); s.anchorPoint = CGPoint(x: 0.5, y: 0); s.zPosition = 0.2
                s.color = TeamColor.sk(e.owner); s.colorBlendFactor = 1
                Sway.apply(s, speed: 7, phase: Float(seed), amplitude: 0.16, tint: TeamColor.sk(e.owner), tintAmount: 1)
                return s
            }
            let windRight = (biome.wind.x + biome.wind.y) >= 0
            f.zRotation = windRight ? -.pi / 2 : .pi / 2
            f.position = CGPoint(x: pole.x, y: pole.y + 56)
        case (.humans, .heavy):
            // Gantry crane trolley shuttles while vehicles are being built.
            let c0 = loc(n - 0.6, n - 0.6, 34, n)
            let a0 = CGPoint(x: c0.x - 6, y: c0.y + 35.5), a1 = CGPoint(x: c0.x - 46, y: c0.y + 30.3)
            let trolley = part(v, "trolley") {
                let s = SKSpriteNode(texture: bank.fx["pixel"], color: SKColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1), size: CGSize(width: 6, height: 4))
                s.colorBlendFactor = 1; s.zPosition = 0.25
                let cable = SKSpriteNode(texture: bank.fx["pixel"], color: SKColor(white: 0.15, alpha: 1), size: CGSize(width: 1, height: 14))
                cable.colorBlendFactor = 1; cable.anchorPoint = CGPoint(x: 0.5, y: 1); cable.position = CGPoint(x: 0, y: -1)
                let hook = SKSpriteNode(texture: bank.fx["pixel"], color: SKColor(red: 0.95, green: 0.72, blue: 0.15, alpha: 1), size: CGSize(width: 5, height: 4))
                hook.colorBlendFactor = 1; hook.position = CGPoint(x: 0, y: -15)
                s.addChild(cable); s.addChild(hook)
                return s
            }
            if busy { v.phase += 1.0 / 60 * 0.35 }
            let k = CGFloat(0.5 - 0.5 * cos(v.phase * .pi * 2))
            trolley.position = CGPoint(x: a0.x + (a1.x - a0.x) * k, y: a0.y + (a1.y - a0.y) * k)
            if busy && near && v.partT <= 0 {
                // Exhaust from the stack.
                v.partT = 0.55
                let stack = loc(0.6, n - 0.5, 34, n) + CGPoint(x: 0, y: 20)
                puff("smoke", at: v.root.position + stack, size: CGSize(width: 12, height: 12), color: SKColor(white: 0.55, alpha: 1), alpha: 0.5, blend: .alpha, z: 458, life: 1.6, rise: 36, grow: 2.6, drift: CGFloat(biome.wind.x) * 10)
            }
        case (.humans, .air):
            // Pad landing lights chase around the circle; the tower beacon turns.
            let pad = loc(n * 0.3, n * 0.36, 1, n)
            for k in 0..<8 {
                let l = part(v, "pad\(k)") { let s = glowDot(SKColor(red: 0.45, green: 1, blue: 0.55, alpha: 1), 8); s.zPosition = 0.15; return s }
                let a = CGFloat(k) / 8 * .pi * 2
                l.position = CGPoint(x: pad.x + cos(a) * 30, y: pad.y + sin(a) * 15)
                let lead = Int(t * (busy ? 10 : 4)) % 8
                l.alpha = k == lead ? 1 : 0.15
            }
            let tw = loc(0.45, n - 0.5, 0, n) + CGPoint(x: 0, y: 51)
            let beam = part(v, "beacon") {
                let s = SKSpriteNode(texture: bank.fx["cone"]); s.anchorPoint = CGPoint(x: 0.04, y: 0.5); s.size = CGSize(width: 70, height: 26)
                s.blendMode = .add; s.colorBlendFactor = 1; s.color = SKColor(red: 0.7, green: 0.95, blue: 1, alpha: 1)
                return s
            }
            beam.position = tw
            let a = t * 1.8 + seed
            beam.zRotation = CGFloat(a.truncatingRemainder(dividingBy: .pi * 2))
            beam.yScale = 0.5 + 0.5 * abs(CGFloat(sin(a)))
            beam.alpha = 0.12 + 0.4 * night
            if night > 0.05 { liftLight(beam, in: v, by: 1) } else { beam.zPosition = 0.3 }
        case (.humans, .tower), (.humans, .forward):
            // Searchlight: sweeps the approach after dark.
            let at = d.kind == .tower ? CGPoint(x: -14, y: 84) : CGPoint(x: -26, y: 36)
            let s = part(v, "search") {
                let s = SKSpriteNode(texture: bank.fx["cone"]); s.anchorPoint = CGPoint(x: 0.03, y: 0.5)
                s.blendMode = .add; s.colorBlendFactor = 1; s.color = SKColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
                s.size = CGSize(width: d.kind == .tower ? 150 : 110, height: 46)
                return s
            }
            s.isHidden = night < 0.1
            if !s.isHidden {
                s.position = at
                s.zRotation = CGFloat(-.pi / 2 + sin(t * 0.45 + seed) * 1.2)
                s.alpha = night * 0.3
                liftLight(s, in: v, by: 0.5)
            }
        case (.humans, .depot):
            if near && v.partT <= 0 {
                // The silo vents a little steam now and then.
                v.partT = 2.6 + Double(hnoise(e.id, world.tick, 1)) * 2
                let top = loc(n * 0.82, n * 0.6, 0, n) + CGPoint(x: 0, y: 42)
                puff("smoke", at: v.root.position + top, size: CGSize(width: 10, height: 10), color: SKColor(white: 0.92, alpha: 1), alpha: 0.4, blend: .alpha, z: 458, life: 1.4, rise: 22, grow: 2.4, drift: CGFloat(biome.wind.x) * 8)
            }

        // MARK: Lattice
        case (.machines, .hq), (.machines, .air), (.machines, .tower), (.machines, .forward):
            // Energy nodes orbit the rings; faster under load.
            var rings: [(CGPoint, CGFloat, CGFloat, Double)] = []
            switch d.kind {
            case .hq: rings = [(CGPoint(x: 0, y: 128), 26, 8, 1.6), (CGPoint(x: 0, y: 128), 26, 8, 1.6 + .pi)]
            case .air: rings = [(CGPoint(x: 0, y: 30), 24, 8, 2.4), (CGPoint(x: 0, y: 50), 19, 6.3, -3.2), (CGPoint(x: 0, y: 70), 14, 4.6, 4.0)]
            case .tower: rings = [(CGPoint(x: 0, y: 100), 18, 6, 2.2)]
            default: rings = [(CGPoint(x: 0, y: 104), 20, 6, 2.6), (CGPoint(x: 0, y: 104), 30, 9, -1.8)]
            }
            let mul = busy ? 2.0 : 1.0
            for (k, r) in rings.enumerated() {
                let dot = part(v, "orbit\(k)") { let s = glowDot(SKColor(red: 0.5, green: 1, blue: 1, alpha: 1), 12); s.zPosition = 0.35; return s }
                let a = t * abs(r.3) * mul * (r.3 < 0 ? -1 : 1) + (d.kind == .hq ? r.3 : seed)
                dot.position = CGPoint(x: r.0.x + CGFloat(cos(a)) * r.1, y: r.0.y + CGFloat(sin(a)) * r.2)
                // Behind the spire on the far half of the orbit.
                dot.zPosition = sin(a) > 0 ? -0.05 : 0.35
                dot.alpha = sin(a) > 0 ? 0.5 : 1
            }
            if d.kind == .hq { conduitPulse(v, [loc(0.4, 0.4, 10, n), loc(n - 0.4, 0.4, 10, n), loc(n - 0.4, n - 0.4, 10, n)], t, speed: busy ? 0.9 : 0.45) }
        case (.machines, .infantry):
            conduitPulse(v, [loc(0.3, n * 0.55, 28, n), loc(n - 0.3, n * 0.55, 28, n)], t, speed: busy ? 1.2 : 0.4)
            if busy && near && v.partT <= 0 {
                // Welding at the assembly arm.
                v.partT = 0.18 + Double(hnoise(e.id, world.tick, 2)) * 0.25
                let tip = loc(n * 0.6, n * 0.45, 36, n) + CGPoint(x: 30, y: 13)
                puff("spark", at: v.root.position + tip, size: CGSize(width: 12, height: 12), color: SKColor(red: 0.7, green: 0.95, blue: 1, alpha: 1), z: 456, life: 0.15, grow: 1.6)
            }
        case (.machines, .heavy):
            conduitPulse(v, [loc(n - 0.2, 0.3, 20, n), loc(n - 0.2, n - 0.3, 20, n)], t, speed: busy ? 1.0 : 0.35)
            let g0 = loc(n * 0.25, 0.2, 2, n), g1 = loc(n * 0.75, 0.2, 2, n)
            let forge = part(v, "forge") {
                let s = glowDot(SKColor(red: 1, green: 0.5, blue: 0.15, alpha: 1), 60); s.size = CGSize(width: 70, height: 40); s.zPosition = 0.2
                return s
            }
            forge.position = CGPoint(x: (g0.x + g1.x) / 2, y: g0.y + 12)
            forge.alpha = busy ? 0.55 + 0.3 * CGFloat(sin(t * 9 + seed)) * CGFloat(sin(t * 3.1)) : 0.12
            if night > 0.05 { liftLight(forge, in: v, by: 0.2) } else { forge.zPosition = 0.2 }
        case (.machines, .research):
            if busy && near && v.partT <= 0 {
                // Lightning jumps between the research cores.
                v.partT = 0.45 + Double(hnoise(e.id, world.tick, 3)) * 0.6
                let cores = [(0.3, 0.3, 40.0), (0.3, 0.7, 30.0), (0.7, 0.3, 34.0), (0.7, 0.7, 52.0)].map { loc(CGFloat($0.0) * n, CGFloat($0.1) * n, 12, n) + CGPoint(x: 0, y: CGFloat($0.2) + 10) }
                let i = Int(hnoise(e.id, world.tick, 4) * 4) % 4, j = (i + 1 + Int(hnoise(e.id, world.tick, 5) * 3)) % 4
                let a = v.root.position + cores[i], b = v.root.position + cores[j]
                if let s = fx() {
                    s.texture = bank.lightning[world.tick % 3]; s.anchorPoint = CGPoint(x: 0, y: 0.5)
                    s.size = CGSize(width: hypot(b.x - a.x, b.y - a.y), height: 12); s.position = a; s.zRotation = atan2(b.y - a.y, b.x - a.x)
                    s.color = SKColor(red: 0.5, green: 0.95, blue: 1, alpha: 1); s.zPosition = 456
                    s.run(.fadeOut(withDuration: 0.16)); s.run(recycle(s, after: 0.18))
                }
            }
        case (.machines, .depot):
            if near && v.partT <= 0 {
                v.partT = 0.8
                for u in [0.35, 0.7] as [CGFloat] {
                    let top = loc(u * n, n * 0.62, 16, n) + CGPoint(x: 0, y: 32)
                    puff("glow", at: v.root.position + top, size: CGSize(width: 9, height: 9), color: SKColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), alpha: 0.6, z: 456, life: 0.9, rise: 18, grow: 0.3)
                }
            }

        // MARK: Brood
        case (.aliens, _):
            // Squash-and-stretch breathing (volume-preserving), a heartbeat ripple across the creep,
            // and green motes rising while the organism regrows damage.
            let rate = busy ? 4.0 : 1.8
            let br = 0.022 * CGFloat(sin(t * rate + seed))
            v.body.yScale = 1 + br
            v.body.xScale = 1 - br * 0.5
            if near && v.partT <= 0 {
                v.partT = busy ? 1.6 : 3.4
                if let s = fx() {
                    s.texture = bank.fx["shockwave"]; s.size = CGSize(width: n * 20, height: n * 10); s.blendMode = .add
                    s.color = SKColor(red: 0.55, green: 1, blue: 0.4, alpha: 1); s.alpha = 0.35
                    s.position = v.root.position; s.zPosition = 5; s.setScale(0.6)
                    s.run(.group([.scale(to: 2.9, duration: 1.4), .fadeOut(withDuration: 1.4)])); s.run(recycle(s, after: 1.45))
                }
                if busy {
                    puff("orb", at: CGPoint(x: v.root.position.x, y: v.root.position.y + BuildingArt.visualHeight(d) * 0.55), size: CGSize(width: 7, height: 7),
                         color: SKColor(red: 0.8, green: 0.5, blue: 1, alpha: 1), alpha: 0.8, blend: .alpha, z: 457, life: 1.4, rise: 30, drift: 8)
                }
            }
            if e.hp < e.maxHp - 1 && world.time - e.lastHitTime > 3 && near && world.tick % 9 == e.id % 9 {
                let jx = (hnoise(e.id, world.tick, 7) - 0.5) * n * 40
                puff("glow", at: CGPoint(x: v.root.position.x + jx, y: v.root.position.y + 8), size: CGSize(width: 8, height: 8),
                     color: SKColor(red: 0.5, green: 1, blue: 0.4, alpha: 1), alpha: 0.9, z: 457, life: 1.1, rise: 34)
            }
        default: break
        }
    }

    /// A packet of light travelling along a conduit polyline (local coordinates).
    func conduitPulse(_ v: EntityView, _ pts: [CGPoint], _ t: Double, speed: Double) {
        guard pts.count >= 2 else { return }
        let dot = part(v, "pulse") { let s = glowDot(SKColor(red: 0.6, green: 1, blue: 1, alpha: 1), 14); s.zPosition = 0.3; return s }
        let segs = pts.count - 1
        let f = (t * speed).truncatingRemainder(dividingBy: 1) * Double(segs)
        let i = min(segs - 1, Int(f)), k = CGFloat(f - Double(i))
        dot.position = CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * k, y: pts[i].y + (pts[i + 1].y - pts[i].y) * k)
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}
