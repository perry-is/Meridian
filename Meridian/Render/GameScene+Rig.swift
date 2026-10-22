import SpriteKit
import MeridianCore

/// Drives the upper rig part of each unit: weapons and turrets track their target and recoil along the barrel,
/// artillery lifts to fire, melee limbs wind up and strike, emitters pulse, and workers swing the right tool
/// for the job (axe on timber, pick on ore, hammer on construction; Lattice cutting beams; Brood bites).
extension GameScene {

    /// Weapon tip in the entity root's coordinate space (for flashes, beams and charge glows).
    func rigMuzzleLocal(_ v: EntityView) -> CGPoint {
        guard let up = v.upper else { return .zero }
        let k = v.canvas / 40
        let dx = (v.rig.muzzle.x - v.rig.pivot.x) * k, dy = (v.rig.muzzle.y - v.rig.pivot.y) * k
        let a = up.zRotation
        let lx = up.position.x + dx * cos(a) - dy * sin(a)
        let ly = up.position.y + dx * sin(a) + dy * cos(a)
        // Into the body's space (mirrored by facing), then the root's.
        return CGPoint(x: v.body.position.x + lx * v.body.xScale, y: v.body.position.y + ly * v.body.yScale)
    }

    func animateRig(_ e: Entity, _ v: EntityView, _ up: SKSpriteNode, _ t: Double, _ seed: Double) {
        let r = v.rig
        let k = v.canvas / 40
        let base = CGPoint(x: (r.pivot.x / 40 - 0.5) * v.canvas, y: (r.pivot.y / 40 - 0.12) * v.canvas)
        let sinceFire = t - e.lastFireTime
        var want = r.rest
        var rate: CGFloat = 0.18
        var push: CGFloat = 0          // along the barrel (negative = recoil)
        var lift: CGFloat = 0
        var variant = ""
        let tg = world.entity(e.target)

        func pitchTo(_ tg: Entity) -> CGFloat {
            let tp = Iso.scene(tg.x, tg.y)
            let dx = abs(tp.x - v.root.position.x)
            let dy = (tp.y + (tg.isAir ? 38 : 10)) - (v.root.position.y + base.y)
            return CGFloat(atan2(dy, max(8, dx)))
        }

        switch r.kind {
        case .gun, .turret, .emitter, .head:
            if let tg = tg {
                want = min(r.aimUp, max(-r.aimDown, pitchTo(tg)))
                rate = r.kind == .turret ? 0.1 : 0.22
            } else if e.moving {
                want = r.kind == .gun ? -0.22 : 0                          // weapon carried low on the march
                if r.kind == .gun { want += CGFloat(sin(v.gait * 2 * .pi)) * 0.05 }
            } else if r.kind == .head || (r.kind == .turret && (e.order == .patrol || e.order == .hold)) {
                want = CGFloat(sin(t * 0.7 + seed)) * 0.22                 // scanning
                rate = 0.05
            } else {
                want = r.rest + CGFloat(sin(t * 1.3 + seed)) * 0.025       // breathing
            }
            if sinceFire < 0.16 { push = -r.kick * CGFloat(1 - sinceFire / 0.16) }
            if r.kind == .emitter {
                let p = sinceFire < 0.3 ? CGFloat(1 - sinceFire / 0.3) : 0
                up.setScale(1 + p * 0.25 + 0.03 * CGFloat(sin(t * 4 + seed)))
            }
        case .artillery:
            // Raised to fire; settles back after each shot with a heavy kick.
            want = tg != nil ? min(r.aimUp, r.rest + 0.25 + pitchTo(tg!) * 0.3) : (e.moving ? r.rest * 0.4 : r.rest)
            rate = 0.06
            if sinceFire < 0.3 { push = -r.kick * CGFloat(1 - sinceFire / 0.3); want -= 0.12 * CGFloat(1 - sinceFire / 0.3) }
        case .melee:
            // Wind up as the next blow comes due, strike on the hit, then recover.
            if sinceFire < 0.12 { want = -0.65; rate = 0.6; push = 2.2 * CGFloat(1 - sinceFire / 0.12) }
            else if sinceFire < 0.4 { want = -0.3; rate = 0.15 }
            else if tg != nil && e.cooldown < 0.35 { want = 0.75; rate = 0.18; push = -0.8 }
            else if e.moving { want = 0.2 + CGFloat(sin(v.gait * 2 * .pi)) * 0.1 }
            else { want = 0.1 + CGFloat(sin(t * 1.6 + seed)) * 0.06 }
        case .tool, .beamTool, .biteTool:
            let job = workTarget(e)
            if let (node, kind) = job {
                variant = kind
                let period = kind == "build" ? 0.55 : 0.8
                let u = (t / period + seed * 0.13).truncatingRemainder(dividingBy: 1)
                let cycle = Int(t / period + seed * 0.13)
                switch r.kind {
                case .tool:
                    // Slow raise, fast strike.
                    if u < 0.68 { let q = CGFloat(u / 0.68); want = -0.5 + 1.45 * q * q * (3 - 2 * q) }
                    else { let q = CGFloat((u - 0.68) / 0.32); want = 0.95 - 1.5 * min(1, q * 1.8) }
                    rate = 1
                case .beamTool:
                    want = -0.15 + CGFloat(sin(t * 9 + seed)) * 0.06; rate = 0.3
                case .biteTool:
                    push = u < 0.25 ? CGFloat(sin(u / 0.25 * .pi)) * 2.2 : 0
                    want = u < 0.25 ? -0.25 : 0.05; rate = 0.4
                default: break
                }
                // The blow lands: chips fly and the target shivers.
                if u > 0.86 && cycle != v.strikeCycle {
                    v.strikeCycle = cycle
                    if let nv = views[node.id] { nv.shake = 1 }
                    if detail && onScreen(v.root.position) {
                        let p = (views[node.id]?.root.position ?? Iso.scene(node.x, node.y)) + CGPoint(x: 0, y: node.isBuilding ? 14 : 12)
                        let col = node.isResource ? GameScene.resourceColor(ResourceKind(rawValue: node.type)!) : SKColor(red: 1, green: 0.85, blue: 0.45, alpha: 1)
                        for c in 0..<3 {
                            puff(kind == "wood" ? "pixel" : "spark", at: CGPoint(x: p.x + CGFloat(c * 6 - 6), y: p.y), size: CGSize(width: 4, height: 4),
                                 color: col, blend: kind == "wood" ? .alpha : .add, z: 456, life: 0.45, rise: CGFloat(10 + c * 4), drift: CGFloat(c - 1) * 12)
                        }
                    }
                }
                if r.kind == .beamTool { cuttingBeam(v, to: node, t: t) }
            } else {
                want = e.moving ? -0.1 + CGFloat(sin(v.gait * 2 * .pi)) * 0.06 : CGFloat(sin(t * 1.4 + seed)) * 0.04
                v.beam?.isHidden = true
            }
            if r.kind != .beamTool && job == nil { v.beam?.isHidden = true }
        case .none:
            break
        }
        // Swap the tool to suit the job.
        if variant != v.tool {
            v.tool = variant
            let owner = max(0, e.owner)
            up.texture = bank.upper[owner][e.type][variant] ?? bank.upper[owner][e.type][""]
        }
        v.aim += (want - v.aim) * rate
        up.zRotation = v.aim
        let along = push * k
        up.position = CGPoint(x: base.x + along * cos(v.aim), y: base.y + along * sin(v.aim) + lift)
        up.color = v.body.color; up.colorBlendFactor = v.body.colorBlendFactor
    }

    /// What a worker is working on right now, if it is standing at it: (node or structure, tool variant).
    func workTarget(_ e: Entity) -> (Entity, String)? {
        guard !e.moving else { return nil }
        switch e.order {
        case .gather:
            guard let n = world.entity(e.gatherNode), dist2(n.x, n.y, e.x, e.y) < 2.6 * 2.6 else { return nil }
            return (n, n.type == ResourceKind.wood.rawValue ? "wood" : "ore")
        case .build, .repair:
            guard let b = world.entity(e.orderTarget) else { return nil }
            let reach = Double(b.size) / 2 + 1.8
            guard dist2(b.x, b.y, e.x, e.y) < reach * reach else { return nil }
            return (b, "build")
        default: return nil
        }
    }

    /// Lattice fabricators cut and weld with a flickering beam from the emitter to the work.
    func cuttingBeam(_ v: EntityView, to node: Entity, t: Double) {
        if v.beam == nil {
            let b = SKSpriteNode(texture: bank.fx["beam"])
            b.anchorPoint = CGPoint(x: 0, y: 0.5); b.blendMode = .add; b.colorBlendFactor = 1
            b.color = SKColor(red: 0.45, green: 0.95, blue: 1, alpha: 1); b.zPosition = 0.5
            v.root.addChild(b); v.beam = b
        }
        guard let b = v.beam, let nv = views[node.id] else { return }
        let a = rigMuzzleLocal(v)
        let to = CGPoint(x: nv.root.position.x - v.root.position.x, y: nv.root.position.y - v.root.position.y + (node.isBuilding ? 16 : 12))
        b.isHidden = false
        b.position = a
        b.size = CGSize(width: hypot(to.x - a.x, to.y - a.y), height: 3 + 1.5 * CGFloat(sin(t * 37)))
        b.zRotation = atan2(to.y - a.y, to.x - a.x)
        b.alpha = 0.55 + 0.35 * CGFloat(sin(t * 23))
    }
}
