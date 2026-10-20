import SpriteKit
import MeridianCore

/// Combat presentation: projectiles, beams, impacts, explosions, deaths, building life and damage.
extension GameScene {

    static func styleColor(_ s: String) -> SKColor {
        switch s {
        case "bullet": return SKColor(red: 1, green: 0.88, blue: 0.5, alpha: 1)
        case "rocket", "missile": return SKColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        case "shell", "bomb", "mine": return SKColor(red: 1, green: 0.6, blue: 0.25, alpha: 1)
        case "arc", "pulse", "rail", "beam": return SKColor(red: 0.45, green: 0.95, blue: 1, alpha: 1)
        case "flak": return SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        case "quake": return SKColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        case "acid": return SKColor(red: 0.6, green: 1, blue: 0.3, alpha: 1)
        case "spine": return SKColor(red: 0.95, green: 0.95, blue: 0.8, alpha: 1)
        case "spore": return SKColor(red: 0.85, green: 0.5, blue: 1, alpha: 1)
        case "claw": return SKColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        default: return .white
        }
    }

    // MARK: Pooling

    func fx() -> SKSpriteNode? {
        guard fxBudget > 0 else { return nil }
        fxBudget -= 1
        let s = fxPool.popLast() ?? {
            let n = SKSpriteNode(texture: bank.fx["glow"])
            n.colorBlendFactor = 1
            return n
        }()
        s.removeAllActions()
        s.alpha = 1; s.setScale(1); s.zRotation = 0; s.blendMode = .add; s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        s.colorBlendFactor = 1; s.color = .white
        if s.parent == nil { worldNode.addChild(s) }
        return s
    }

    func recycle(_ s: SKSpriteNode, after d: TimeInterval) -> SKAction {
        .sequence([.wait(forDuration: d), .run { [weak self, weak s] in
            guard let s = s else { return }
            s.removeFromParent(); s.isHidden = false
            if (self?.fxPool.count ?? 999) < 400 { self?.fxPool.append(s) }
        }])
    }

    func visibleToMe(_ x: Double, _ y: Double) -> Bool { ctl.spectating || world.players[ctl.me].visible[world.tileIndex(x, y)] > 0 }

    func onScreen(_ p: CGPoint) -> Bool {
        let c = cam.position
        return abs(p.x - c.x) < size.width * zoom * 0.6 + 80 && abs(p.y - c.y) < size.height * zoom * 0.6 + 80
    }

    // MARK: Projectiles

    func syncProjectiles() {
        let ps = world.projectiles
        while projPool.count < ps.count {
            let s = SKSpriteNode(texture: bank.fx["bolt"])
            s.colorBlendFactor = 1
            s.zPosition = 400
            let halo = SKSpriteNode(texture: bank.fx["glow"])
            halo.blendMode = .add; halo.colorBlendFactor = 1; halo.zPosition = -0.01; halo.alpha = 0.8
            s.addChild(halo)
            worldNode.addChild(s)
            projPool.append(s)
        }
        trailTick &+= 1
        for (i, p) in ps.enumerated() {
            let s = projPool[i]
            let vis = visibleToMe(p.x, p.y)
            s.isHidden = !vis
            if !vis { continue }
            let pos = Iso.scene(p.x, p.y)
            let total = max(0.05, p.total)
            let t = min(1, p.age / total)
            let dstAlt: CGFloat = p.targetAir ? 38 : 9
            var alt: CGFloat = 16 + (dstAlt - 16) * CGFloat(t)
            let arcing = ["shell", "acid", "spore", "bomb"].contains(p.style)
            if arcing { alt += CGFloat(sin(t * .pi)) * CGFloat(min(110, total * 46)) }
            let point = CGPoint(x: pos.x, y: pos.y + alt)
            let sa = Iso.scene(p.sx, p.sy), ta = Iso.scene(p.tx, p.ty)
            var ang = atan2(ta.y - sa.y, ta.x - sa.x)
            if arcing { ang += CGFloat(cos(t * .pi)) * 0.6 * (ta.x >= sa.x ? 1 : -1) }
            s.position = point
            s.zRotation = ang
            let col = GameScene.styleColor(p.style)
            s.color = col
            let halo = s.children.first as? SKSpriteNode
            halo?.color = col
            switch p.style {
            case "shell", "bomb":
                s.texture = bank.fx["shell"]; s.size = CGSize(width: 8, height: 8); s.blendMode = .alpha; s.colorBlendFactor = 0.2
                halo?.size = CGSize(width: 14, height: 14); halo?.alpha = 0.5
            case "acid", "spore":
                s.texture = bank.fx["orb"]; s.size = CGSize(width: 12, height: 11); s.blendMode = .alpha; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 26, height: 26); halo?.alpha = 0.7
            case "flak", "pulse":
                s.texture = bank.fx["orb"]; s.size = CGSize(width: 10, height: 10); s.blendMode = .add; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 28, height: 28); halo?.alpha = 0.9
            case "rocket", "missile":
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: 13, height: 4); s.blendMode = .alpha; s.colorBlendFactor = 0.25
                halo?.size = CGSize(width: 16, height: 16); halo?.alpha = 0.9; halo?.position = CGPoint(x: -7, y: 0)
            case "spine":
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: 14, height: 2.5); s.blendMode = .alpha; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 10, height: 10); halo?.alpha = 0.3
            default: // tracers
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: 18, height: 2.6); s.blendMode = .add; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 14, height: 10); halo?.alpha = 0.5; halo?.position = .zero
            }
            if p.style != "rocket" && p.style != "missile" { halo?.position = .zero }
            // Trails: smoke behind missiles, drips behind acid, glitter behind shells.
            if (p.style == "rocket" || p.style == "missile" || p.style == "shell" || p.style == "acid") && (trailTick + i) % 2 == 0, onScreen(point), let puff = fx() {
                puff.texture = bank.fx["smoke"]; puff.blendMode = .alpha
                puff.size = CGSize(width: 9, height: 9)
                puff.color = p.style == "acid" ? SKColor(red: 0.5, green: 0.9, blue: 0.3, alpha: 1) : SKColor(white: 0.75, alpha: 1)
                puff.alpha = 0.55; puff.position = point; puff.zPosition = 399
                puff.run(.group([.scale(to: 2.2, duration: 0.5), .fadeOut(withDuration: 0.5)])); puff.run(recycle(puff, after: 0.52))
            }
        }
        for i in ps.count..<projPool.count { projPool[i].isHidden = true }
    }

    // MARK: Event consumption

    func consumeEvents() {
        for ev in world.events {
            switch ev {
            case .shot(let from, let fx0, let fy0, let tx, let ty, let style, _, let air):
                guard visibleToMe(fx0, fy0) || visibleToMe(tx, ty) else { continue }
                let srcAir = world.entity(from)?.isAir ?? false
                if style == "arc" { lightningFX(fx0, fy0, tx, ty, srcAir, air) }
                else if style == "rail" || style == "beam" { beam(fx0, fy0, tx, ty, style, srcAir, air) }
                if style == "claw" { slashFX(tx, ty, air) }
                else { muzzle(fx0, fy0, style, srcAir, toward: (tx, ty)) }
                sfx?.shot(style, at: Iso.scene(fx0, fy0))
            case .impact(let x, let y, let r, let style, let air):
                if ctl.spectating { hotspot.append((x, y)) }
                guard visibleToMe(x, y) else { continue }
                impact(x, y, radius: r, style: style, air: air)
            case .death(let x, let y, let big, _, let air, let building):
                guard visibleToMe(x, y) else { continue }
                let r = building ? 2.6 : (big ? 1.6 : 0.8)
                explosion(x, y, radius: r, air: air, big: true)
                if building || big { shake(building ? 7 : 4, at: Iso.scene(x, y)) }
                sfx?.explosion(big: building || big, at: Iso.scene(x, y))
            case .heal(let x, let y):
                guard visibleToMe(x, y), let s = fx() else { continue }
                s.texture = bank.fx["spark"]; s.size = CGSize(width: 14, height: 14)
                s.color = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1)
                let p = Iso.scene(x, y); s.position = CGPoint(x: p.x, y: p.y + 20); s.zPosition = 450
                s.run(.group([.moveBy(x: 0, y: 16, duration: 0.7), .fadeOut(withDuration: 0.7)]))
                s.run(recycle(s, after: 0.72))
            case .emp(let x, let y, let r):
                for k in 0..<2 {
                    guard let s = fx() else { break }
                    s.texture = bank.fx["shockwave"]; s.size = CGSize(width: 24, height: 12)
                    s.color = SKColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)
                    s.position = Iso.scene(x, y); s.zPosition = 455
                    s.run(.sequence([.wait(forDuration: Double(k) * 0.12), .group([.scale(to: CGFloat(r) * 7.5, duration: 0.45), .fadeOut(withDuration: 0.5)])]))
                    s.run(recycle(s, after: 0.65))
                }
                sfx?.play("emp", at: Iso.scene(x, y))
            case .built(let id):
                if let e = world.entity(id), e.owner == ctl.me { sfx?.play("built", at: nil) }
            case .produced(let id):
                if let e = world.entity(id), e.owner == ctl.me, world.time - lastProducedSound > 1.5 { lastProducedSound = world.time; sfx?.play("ready", at: nil) }
            case .captured(let site, let owner):
                sfx?.play(owner == ctl.me ? "capture" : "alert", at: nil)
                capturePillar(site, owner)
            default: break
            }
        }
        world.events.removeAll(keepingCapacity: true)
        if ctl.spectating {
            spectateTimer -= 1.0 / 60
            if spectateTimer <= 0 && !hotspot.isEmpty {
                spectateTimer = 3
                let hx = hotspot.reduce(0) { $0 + $1.0 } / Double(hotspot.count), hy = hotspot.reduce(0) { $0 + $1.1 } / Double(hotspot.count)
                cam.run(.move(to: Iso.scene(hx, hy), duration: 1.0))
                hotspot.removeAll()
            }
        }
        if let cp = ctl.commandPing {
            ctl.commandPing = nil
            for k in 0..<2 {
                guard let s = fx() else { break }
                s.texture = bank.fx["selectring"]; s.size = CGSize(width: 54, height: 27); s.blendMode = .alpha
                s.color = cp.2 ? SKColor(red: 1, green: 0.3, blue: 0.25, alpha: 1) : SKColor(red: 0.35, green: 1, blue: 0.45, alpha: 1)
                s.position = Iso.scene(cp.0, cp.1); s.zPosition = 5
                s.setScale(1.3 - CGFloat(k) * 0.4)
                s.run(.sequence([.wait(forDuration: Double(k) * 0.08), .group([.scale(to: 0.25, duration: 0.4), .fadeOut(withDuration: 0.4)])]))
                s.run(recycle(s, after: 0.5))
            }
            sfx?.play(cp.2 ? "attack" : "move", at: nil)
        }
        for c in world.clouds where visibleToMe(c.x, c.y) && world.tick % 5 == 0 {
            guard let s = fx() else { break }
            s.texture = bank.fx["smoke"]; s.blendMode = .alpha
            s.size = CGSize(width: CGFloat(c.radius) * 64, height: CGFloat(c.radius) * 32)
            s.color = c.slow < 1 ? SKColor(red: 0.72, green: 0.42, blue: 0.95, alpha: 1) : SKColor(red: 0.55, green: 0.95, blue: 0.3, alpha: 1)
            s.alpha = 0.45
            let jx = Double(hnoise(world.tick, Int(c.x * 10), 3) - 0.5) * c.radius
            let p = Iso.scene(c.x + jx, c.y); s.position = CGPoint(x: p.x, y: p.y + 6); s.zPosition = 90
            s.run(.group([.fadeOut(withDuration: 0.8), .scale(by: 1.25, duration: 0.8), .moveBy(x: 0, y: 8, duration: 0.8)]))
            s.run(recycle(s, after: 0.82))
        }
    }

    /// A column of team-coloured light and a ground shockwave when a site changes hands.
    func capturePillar(_ i: Int, _ owner: Int) {
        guard i < world.sites.count else { return }
        let st = world.sites[i]
        let p = Iso.scene(st.x, st.y)
        let col = TeamColor.sk(owner)
        if let b = fx() {
            b.texture = bank.fx["beam"]; b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.size = CGSize(width: 520, height: 46); b.zRotation = .pi / 2
            b.position = p; b.color = col; b.zPosition = 470; b.alpha = 0
            b.run(.sequence([.fadeAlpha(to: 0.95, duration: 0.15), .wait(forDuration: 0.5), .group([.fadeOut(withDuration: 1.2), .scaleY(to: 0.1, duration: 1.2)])]))
            b.run(recycle(b, after: 1.9))
        }
        for k in 0..<3 {
            guard let w = fx() else { break }
            w.texture = bank.fx["shockwave"]; w.size = CGSize(width: 60, height: 30); w.color = col
            w.position = p; w.zPosition = 7; w.setScale(0.4)
            w.run(.sequence([.wait(forDuration: Double(k) * 0.18), .group([.scale(to: 5.5, duration: 0.9), .fadeOut(withDuration: 0.9)])]))
            w.run(recycle(w, after: 1.5))
        }
        if let g = fx() {
            g.texture = bank.fx["glow"]; g.size = CGSize(width: 220, height: 160); g.color = col; g.position = CGPoint(x: p.x, y: p.y + 40); g.zPosition = 469
            g.run(.fadeOut(withDuration: 1.0)); g.run(recycle(g, after: 1.02))
        }
    }

    // MARK: Shot visuals

    func muzzle(_ x: Double, _ y: Double, _ style: String, _ air: Bool, toward: (Double, Double)) {
        let p = Iso.scene(x, y)
        guard onScreen(p), let s = fx() else { return }
        let tp = Iso.scene(toward.0, toward.1)
        let a = atan2(tp.y - p.y, tp.x - p.x)
        s.texture = bank.sparks[0]; s.size = CGSize(width: 18, height: 18)
        s.color = GameScene.styleColor(style)
        s.position = CGPoint(x: p.x + cos(a) * 12, y: p.y + (air ? 40 : 16) + sin(a) * 6); s.zPosition = 452
        s.run(.animate(with: Array(bank.sparks.prefix(2)), timePerFrame: 0.04)); s.run(recycle(s, after: 0.09))
    }

    func slashFX(_ x: Double, _ y: Double, _ air: Bool) {
        let p = Iso.scene(x, y)
        guard onScreen(p), let s = fx() else { return }
        s.texture = bank.fx["slash"]; s.size = CGSize(width: 26, height: 26)
        s.color = GameScene.styleColor("claw")
        s.position = CGPoint(x: p.x, y: p.y + (air ? 38 : 14)); s.zPosition = 455
        s.zRotation = CGFloat(hnoise(world.tick, Int(x * 7), 2)) * 6.28
        s.run(.group([.fadeOut(withDuration: 0.18), .scale(to: 1.35, duration: 0.18)])); s.run(recycle(s, after: 0.2))
    }

    func endpoints(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ srcAir: Bool, _ air: Bool) -> (CGPoint, CGPoint) {
        let a = Iso.scene(x0, y0), b = Iso.scene(x1, y1)
        return (CGPoint(x: a.x, y: a.y + (srcAir ? 40 : 18)), CGPoint(x: b.x, y: b.y + (air ? 38 : 10)))
    }

    func beam(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ style: String, _ srcAir: Bool, _ air: Bool) {
        let (pa, pb) = endpoints(x0, y0, x1, y1, srcAir, air)
        guard onScreen(pa) || onScreen(pb) else { return }
        let len = hypot(pb.x - pa.x, pb.y - pa.y), ang = atan2(pb.y - pa.y, pb.x - pa.x)
        let rail = style == "rail"
        for (w, life, a) in [(rail ? 10.0 : 6.0, rail ? 0.35 : 0.16, 0.4), (rail ? 3.5 : 2.2, rail ? 0.22 : 0.1, 1.0)] as [(CGFloat, Double, CGFloat)] {
            guard let s = fx() else { return }
            s.texture = bank.fx["beam"]; s.anchorPoint = CGPoint(x: 0, y: 0.5)
            s.size = CGSize(width: len, height: w); s.position = pa; s.zRotation = ang
            s.color = GameScene.styleColor(style); s.alpha = a; s.zPosition = 456
            s.run(.group([.fadeOut(withDuration: life), .scaleY(to: 0.2, duration: life)])); s.run(recycle(s, after: life + 0.02))
        }
    }

    func lightningFX(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ srcAir: Bool, _ air: Bool) {
        let (pa, pb) = endpoints(x0, y0, x1, y1, srcAir, air)
        guard onScreen(pa) || onScreen(pb), let s = fx() else { return }
        let len = hypot(pb.x - pa.x, pb.y - pa.y)
        s.texture = bank.lightning[Int(hnoise(world.tick, Int(x0 * 5), 1) * 3) % 3]
        s.anchorPoint = CGPoint(x: 0, y: 0.5)
        s.size = CGSize(width: len, height: min(22, 8 + len * 0.12)); s.position = pa; s.zRotation = atan2(pb.y - pa.y, pb.x - pa.x)
        s.color = GameScene.styleColor("arc"); s.zPosition = 457
        s.yScale = hnoise(world.tick, 3, 3) > 0.5 ? 1 : -1
        s.run(.sequence([.fadeAlpha(to: 0.3, duration: 0.04), .fadeAlpha(to: 1, duration: 0.03), .fadeOut(withDuration: 0.1)])); s.run(recycle(s, after: 0.19))
        if let g = fx() {
            g.texture = bank.fx["glow"]; g.size = CGSize(width: 22, height: 22); g.color = GameScene.styleColor("arc")
            g.position = pb; g.zPosition = 457
            g.run(.fadeOut(withDuration: 0.15)); g.run(recycle(g, after: 0.16))
        }
    }

    // MARK: Impacts & explosions

    func impact(_ x: Double, _ y: Double, radius: Double, style: String, air: Bool) {
        let p = Iso.scene(x, y)
        let base = CGPoint(x: p.x, y: p.y + (air ? 38 : 8))
        guard onScreen(base) else { return }
        let col = GameScene.styleColor(style)
        if radius > 0.6 || style == "shell" || style == "bomb" || style == "mine" {
            if ["acid", "spore"].contains(style) { splash(base, radius: radius, color: col) }
            else if ["pulse", "quake", "flak"].contains(style) { plasma(base, radius: radius, color: col, ring: style == "quake") }
            else { explosion(x, y, radius: radius, air: air, big: false) }
            if !air && radius > 1.1 && style != "flak" { decal(p, radius: radius, color: style == "acid" ? col : SKColor(white: 0.05, alpha: 1), splat: style == "acid") }
            return
        }
        guard let s = fx() else { return }
        s.texture = bank.sparks[0]; s.size = CGSize(width: 20, height: 20); s.color = col
        s.position = base; s.zPosition = 455
        s.run(.animate(with: bank.sparks, timePerFrame: 0.035)); s.run(recycle(s, after: 0.15))
    }

    func splash(_ at: CGPoint, radius: Double, color: SKColor) {
        let r = CGFloat(max(0.6, radius))
        for k in 0..<4 {
            guard let s = fx() else { break }
            s.texture = bank.fx["orb"]; s.blendMode = .alpha; s.size = CGSize(width: 7, height: 7); s.color = color
            s.position = at; s.zPosition = 455
            let a = CGFloat(k) * 1.57 + 0.4
            s.run(.group([.moveBy(x: cos(a) * 18 * r, y: sin(a) * 9 * r + 10, duration: 0.3), .fadeOut(withDuration: 0.3)])); s.run(recycle(s, after: 0.32))
        }
        if let g = fx() {
            g.texture = bank.fx["glow"]; g.size = CGSize(width: 34 * r, height: 20 * r); g.color = color; g.position = at; g.zPosition = 454
            g.run(.group([.scale(to: 1.3, duration: 0.25), .fadeOut(withDuration: 0.3)])); g.run(recycle(g, after: 0.32))
        }
    }

    func plasma(_ at: CGPoint, radius: Double, color: SKColor, ring: Bool) {
        let r = CGFloat(max(0.6, radius))
        if let g = fx() {
            g.texture = bank.fx["glow"]; g.size = CGSize(width: 40 * r, height: 30 * r); g.color = color; g.position = at; g.zPosition = 455
            g.setScale(0.4); g.run(.group([.scale(to: 1.2, duration: 0.18), .fadeOut(withDuration: 0.25)])); g.run(recycle(g, after: 0.27))
        }
        if ring, let w = fx() {
            w.texture = bank.fx["shockwave"]; w.size = CGSize(width: 30 * r, height: 15 * r); w.color = color; w.position = at; w.zPosition = 454
            w.setScale(0.3); w.run(.group([.scale(to: 1.3, duration: 0.35), .fadeOut(withDuration: 0.4)])); w.run(recycle(w, after: 0.42))
        }
    }

    func explosion(_ x: Double, _ y: Double, radius: Double, air: Bool, big: Bool) {
        let p = Iso.scene(x, y)
        let base = CGPoint(x: p.x, y: p.y + (air ? 38 : 10))
        guard onScreen(base) else { return }
        let r = CGFloat(max(0.5, radius))
        if let s = fx() {
            s.texture = bank.explosion[0]; s.blendMode = .alpha; s.colorBlendFactor = 0
            s.size = CGSize(width: 62 * r, height: 62 * r); s.position = CGPoint(x: base.x, y: base.y + 10 * r); s.zPosition = 460
            let tpf = big ? 0.06 : 0.045
            s.run(.animate(with: bank.explosion, timePerFrame: tpf)); s.run(recycle(s, after: tpf * 8 + 0.02))
        }
        if let f = fx() {
            f.texture = bank.fx["glow"]; f.size = CGSize(width: 90 * r, height: 60 * r)
            f.color = SKColor(red: 1, green: 0.7, blue: 0.35, alpha: 1); f.position = base; f.zPosition = 459
            f.alpha = 0.8; f.run(.fadeOut(withDuration: 0.25)); f.run(recycle(f, after: 0.27))
        }
        guard big || radius > 1.2 else { return }
        if !air, let w = fx() {
            w.texture = bank.fx["shockwave"]; w.size = CGSize(width: 50 * r, height: 25 * r)
            w.color = SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1); w.position = p; w.zPosition = 6
            w.setScale(0.3); w.run(.group([.scale(to: 1.4, duration: 0.4), .fadeOut(withDuration: 0.45)])); w.run(recycle(w, after: 0.47))
        }
        for k in 0..<(big ? 5 : 3) {
            guard let d = fx() else { break }
            d.texture = bank.shards[k % 2]; d.blendMode = .alpha; d.colorBlendFactor = 0
            d.size = CGSize(width: 7 + CGFloat(k % 3) * 2, height: 7 + CGFloat(k % 3) * 2)
            d.position = base; d.zPosition = 461
            let a = Double(k) * 2.1 + x * 3
            let dx = CGFloat(cos(a)) * 40 * r, up = 26 * r + CGFloat(k) * 4
            let arc = SKAction.customAction(withDuration: 0.6) { node, el in
                let t = el / 0.6
                node.position = CGPoint(x: base.x + dx * t, y: base.y + up * 4 * t * (1 - t) - (air ? 30 * t : 0))
            }
            d.run(.group([arc, .rotate(byAngle: 8, duration: 0.6), .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.15)])]))
            d.run(recycle(d, after: 0.62))
        }
        if !air && radius > 1.2 { decal(p, radius: radius, color: SKColor(white: 0.05, alpha: 1), splat: false) }
    }

    func decal(_ p: CGPoint, radius: Double, color: SKColor, splat: Bool) {
        guard let s = fx() else { return }
        s.texture = splat ? bank.splats[Int(p.x) & 1] : bank.fx["scorch"]; s.blendMode = .alpha
        let r = CGFloat(radius)
        s.size = CGSize(width: 54 * r, height: 27 * r); s.color = color; s.colorBlendFactor = 1
        s.alpha = splat ? 0.55 : 0.75; s.position = p; s.zPosition = 4
        s.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 3)])); s.run(recycle(s, after: 9.1))
    }

    func shake(_ amount: CGFloat, at p: CGPoint) {
        guard onScreen(p), shakeEnabled else { return }
        let a = amount * min(1.5, zoom)
        cam.run(.sequence([.moveBy(x: a, y: -a * 0.6, duration: 0.03), .moveBy(x: -a * 1.7, y: a, duration: 0.05),
                           .moveBy(x: a * 1.0, y: -a * 0.6, duration: 0.05), .moveBy(x: -a * 0.3, y: a * 0.2, duration: 0.04)]), withKey: "shake")
    }

    // MARK: Deaths

    func playDeath(_ e: Entity, _ v: EntityView) {
        let root = v.root
        let p = root.position
        guard onScreen(p) else { root.removeFromParent(); return }
        v.teamRing?.run(.fadeOut(withDuration: 0.2))
        v.ring?.removeFromParent()
        v.shadow?.run(.fadeOut(withDuration: 0.4))
        v.lights.forEach { $0.removeFromParent() }
        v.fire?.removeFromParent()
        if e.isResource {
            root.run(.sequence([.group([.fadeOut(withDuration: 0.6), .scale(to: 0.6, duration: 0.6)]), .removeFromParent()]))
            return
        }
        if e.isBuilding {
            v.body.run(.group([.moveBy(x: 0, y: -26, duration: 1.4), .scaleY(to: 0.55, duration: 1.4), .fadeOut(withDuration: 1.4)]))
            for k in 0..<4 {
                run(.sequence([.wait(forDuration: Double(k) * 0.22), .run { [weak self] in
                    self?.explosion(e.x + Double(k % 2) - 0.5, e.y + Double(k / 2) - 0.5, radius: 1.3, air: false, big: k == 0)
                }]))
            }
            let rubble = SKSpriteNode(texture: bank.fx["rubble"])
            rubble.size = CGSize(width: CGFloat(e.size) * 58, height: CGFloat(e.size) * 29)
            rubble.position = p; rubble.zPosition = 5
            worldNode.addChild(rubble)
            rubble.run(.sequence([.wait(forDuration: 35), .fadeOut(withDuration: 4), .removeFromParent()]))
            root.run(.sequence([.wait(forDuration: 1.5), .removeFromParent()]))
            return
        }
        let fac = world.players[max(0, e.owner)].faction
        let body = v.body
        let side: CGFloat = v.facingSign
        if e.isAir {
            body.run(.group([.moveBy(x: 30 * side, y: -40, duration: 0.7), .rotate(byAngle: -1.4 * side, duration: 0.7), .fadeOut(withDuration: 0.75)]))
            run(.sequence([.wait(forDuration: 0.65), .run { [weak self] in self?.explosion(e.x + 0.5, e.y - 0.5, radius: 1.0, air: false, big: false) }]))
        } else {
            switch fac {
            case .humans:
                body.anchorPoint = CGPoint(x: 0.5, y: 0.12)
                body.run(.group([.rotate(byAngle: -1.35 * side, duration: 0.35), .sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.8)])]))
            case .machines:
                body.color = SKColor(white: 0.15, alpha: 1); body.colorBlendFactor = 0.6
                body.run(.group([.scaleY(to: 0.35, duration: 0.5), .sequence([.wait(forDuration: 1.0), .fadeOut(withDuration: 0.8)])]))
                for k in 0..<3 { run(.sequence([.wait(forDuration: Double(k) * 0.15), .run { [weak self] in self?.impact(e.x, e.y, radius: 0, style: "arc", air: false) }])) }
                decal(p, radius: 0.9, color: SKColor(white: 0.02, alpha: 1), splat: true)
            case .aliens:
                body.color = SKColor(red: 0.5, green: 1, blue: 0.3, alpha: 1); body.colorBlendFactor = 0.5
                body.run(.group([.scaleX(to: 1.3 * side, duration: 0.6), .scaleY(to: 0.25, duration: 0.6), .fadeOut(withDuration: 0.7)]))
                decal(p, radius: 1.0, color: SKColor(red: 0.45, green: 0.85, blue: 0.25, alpha: 1), splat: true)
            }
        }
        root.run(.sequence([.wait(forDuration: 2.1), .removeFromParent()]))
    }

    // MARK: Building life, construction and damage

    func animateBuilding(_ e: Entity, _ v: EntityView, _ t: Double) {
        let d = world.bdef(e)
        let fac = d.faction
        if v.lights.isEmpty && e.complete {
            for pt in BuildingArt.lights(d) {
                let l = SKSpriteNode(texture: bank.fx["glow"])
                l.blendMode = .add; l.colorBlendFactor = 1
                l.color = fac == .humans ? SKColor(red: 1, green: 0.35, blue: 0.25, alpha: 1) : (fac == .machines ? SKColor(red: 0.4, green: 0.95, blue: 1, alpha: 1) : SKColor(red: 0.6, green: 1, blue: 0.4, alpha: 1))
                l.size = CGSize(width: 22, height: 22); l.position = pt; l.zPosition = 0.3
                v.root.addChild(l); v.lights.append(l)
            }
        }
        let busy = !e.queue.isEmpty
        let seed = Double(e.id % 13)
        for (k, l) in v.lights.enumerated() {
            switch fac {
            case .humans: l.alpha = (Int(t * 1.5 + seed) + k) % 2 == 0 ? 0.95 : 0.15
            case .machines: l.alpha = 0.55 + 0.4 * CGFloat(sin(t * (busy ? 6 : 2.5) + seed)); l.setScale(1 + 0.25 * CGFloat(sin(t * 3 + seed)))
            case .aliens: l.alpha = 0.5 + 0.45 * CGFloat(sin(t * (busy ? 5 : 2) + seed + Double(k)))
            }
        }
        // Construction: Concord scaffold grey-out, Lattice hologram, Brood growth.
        if !e.complete {
            let pr = CGFloat(e.buildProgress)
            switch fac {
            case .humans:
                v.body.alpha = 0.5 + 0.5 * pr; v.body.color = SKColor(white: 0.55, alpha: 1); v.body.colorBlendFactor = 0.6 * (1 - pr)
            case .machines:
                v.body.color = SKColor(red: 0.35, green: 0.9, blue: 1, alpha: 1); v.body.colorBlendFactor = 0.75 * (1 - pr) + 0.1
                v.body.alpha = 0.45 + 0.4 * pr + 0.1 * CGFloat(sin(t * 18))
            case .aliens:
                v.body.setScale(0.45 + 0.55 * pr + 0.03 * CGFloat(sin(t * 5)))
                v.body.alpha = 0.7 + 0.3 * pr
            }
            v.wasComplete = false
            if world.tick % 7 == Int(e.id % 7), let s = fx(), onScreen(v.root.position) {
                s.texture = fac == .humans ? bank.sparks[1] : bank.fx["glow"]; s.size = CGSize(width: 14, height: 14)
                s.color = fac == .humans ? SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1) : (fac == .machines ? SKColor(red: 0.4, green: 0.95, blue: 1, alpha: 1) : SKColor(red: 0.6, green: 1, blue: 0.4, alpha: 1))
                let h = BuildingArt.visualHeight(d) * pr
                s.position = CGPoint(x: v.root.position.x + CGFloat(hnoise(world.tick, e.id, 1) - 0.5) * 40, y: v.root.position.y + h * 0.6); s.zPosition = 455
                s.run(.group([.moveBy(x: 0, y: 12, duration: 0.4), .fadeOut(withDuration: 0.4)])); s.run(recycle(s, after: 0.42))
            }
            return
        }
        if !v.wasComplete {
            // Completion flourish.
            v.wasComplete = true
            v.body.setScale(1); v.body.alpha = 1; v.body.colorBlendFactor = 0
            v.body.run(.sequence([.scale(to: 1.06, duration: 0.12), .scale(to: 1, duration: 0.2)]))
            if let s = fx() {
                s.texture = bank.fx["shockwave"]; s.size = CGSize(width: CGFloat(e.size) * 50, height: CGFloat(e.size) * 25)
                s.color = .white; s.position = v.root.position; s.zPosition = 6
                s.setScale(0.5); s.run(.group([.scale(to: 1.3, duration: 0.5), .fadeOut(withDuration: 0.5)])); s.run(recycle(s, after: 0.52))
            }
        }
        if fac == .aliens { v.body.yScale = 1 + 0.018 * CGFloat(sin(t * (busy ? 4 : 1.8) + seed)) }
        if t - e.lastHitTime < 0.08 { v.body.colorBlendFactor = 0.35; v.body.color = SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 1) }
        else if e.disruptedUntil > t { v.body.colorBlendFactor = 0.4; v.body.color = SKColor(red: 0.4, green: 0.6, blue: 1, alpha: 1) }
        else { v.body.colorBlendFactor = 0 }
        // Damage: smoke under 50%, fire under 25%.
        let frac = e.hp / max(1, e.maxHp)
        let hgt = BuildingArt.visualHeight(d)
        if frac < 0.25 {
            if v.fire == nil {
                let f = SKSpriteNode(texture: bank.fx["glow"]); f.blendMode = .add; f.colorBlendFactor = 1
                f.color = SKColor(red: 1, green: 0.5, blue: 0.15, alpha: 1); f.size = CGSize(width: 46, height: 40)
                f.position = CGPoint(x: -8, y: hgt * 0.45); f.zPosition = 0.4
                f.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.12), .fadeAlpha(to: 0.95, duration: 0.15)])))
                v.root.addChild(f); v.fire = f
            }
        } else if v.fire != nil { v.fire?.removeFromParent(); v.fire = nil }
        v.fxTimer -= 1.0 / 60
        let smoky = frac < 0.5
        let producing = busy && (d.kind == .heavy || d.kind == .depot || d.kind == .infantry)
        if (smoky || producing) && v.fxTimer <= 0 && onScreen(v.root.position), let s = fx() {
            v.fxTimer = smoky ? (frac < 0.25 ? 0.12 : 0.3) : 0.7
            s.texture = bank.fx["smoke"]; s.blendMode = .alpha
            if smoky { s.color = SKColor(white: 0.12, alpha: 1); s.alpha = 0.7 }
            else {
                switch fac {
                case .humans: s.color = SKColor(white: 0.8, alpha: 1); s.alpha = 0.45
                case .machines: s.texture = bank.fx["glow"]; s.blendMode = .add; s.color = SKColor(red: 0.4, green: 0.95, blue: 1, alpha: 1); s.alpha = 0.6
                case .aliens: s.texture = bank.fx["orb"]; s.color = SKColor(red: 0.6, green: 1, blue: 0.4, alpha: 1); s.alpha = 0.6
                }
            }
            s.size = CGSize(width: 18, height: 18)
            s.position = CGPoint(x: v.root.position.x + CGFloat(hnoise(world.tick, e.id, 5) - 0.5) * 30, y: v.root.position.y + hgt * 0.7)
            s.zPosition = 458
            s.run(.group([.moveBy(x: 10, y: 40, duration: 1.6), .scale(to: 2.4, duration: 1.6), .fadeOut(withDuration: 1.6)])); s.run(recycle(s, after: 1.62))
        }
    }
}
