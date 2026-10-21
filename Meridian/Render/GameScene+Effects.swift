import SpriteKit
import MeridianCore

/// Combat presentation: weapon families, projectiles, impacts scaled by power, artillery telegraphs,
/// unit motion and damage reactions, wrecks, controlled screen shake and adaptive effect quality.
extension GameScene {

    enum Family { case ballistic, energy, bio }

    static func family(_ s: String) -> Family {
        switch s {
        case "arc", "pulse", "rail", "beam", "flak", "quake": return .energy
        case "acid", "spine", "spore", "claw": return .bio
        default: return .ballistic
        }
    }

    static func styleColor(_ s: String) -> SKColor {
        switch s {
        case "bullet": return SKColor(red: 1, green: 0.86, blue: 0.48, alpha: 1)
        case "rocket", "missile": return SKColor(red: 1, green: 0.58, blue: 0.22, alpha: 1)
        case "shell", "bomb", "mine": return SKColor(red: 1, green: 0.62, blue: 0.25, alpha: 1)
        case "arc", "pulse", "beam": return SKColor(red: 0.45, green: 0.95, blue: 1, alpha: 1)
        case "rail": return SKColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        case "flak": return SKColor(red: 0.55, green: 0.9, blue: 1, alpha: 1)
        case "quake": return SKColor(red: 0.6, green: 0.8, blue: 1, alpha: 1)
        case "acid": return SKColor(red: 0.62, green: 1, blue: 0.3, alpha: 1)
        case "spine": return SKColor(red: 0.95, green: 0.92, blue: 0.78, alpha: 1)
        case "spore": return SKColor(red: 0.85, green: 0.5, blue: 1, alpha: 1)
        case "claw": return SKColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        default: return .white
        }
    }

    // MARK: Quality & pooling

    /// Adaptive effect quality: 2 = full, 1 = reduced trails/debris, 0 = essentials only (gameplay cues stay).
    func updateQuality(_ dt: Double) {
        let ms = dt * 1000
        frameEMA = frameEMA * 0.94 + ms * 0.06
        if let forced = forcedQuality { quality = forced; return }
        if CACurrentMediaTime() - sceneStart < 2.5 { return }      // ignore start-up hitches
        if frameEMA > 19.5 { slowTime += dt } else { slowTime = 0 }
        if frameEMA < 17.2 { fastTime += dt } else { fastTime = 0 }
        if slowTime > 1.2 && quality > 0 { quality -= 1; slowTime = 0; fastTime = 0 }
        if fastTime > 6 && quality < 2 { quality += 1; fastTime = 0 }
    }

    var fxBudgetForQuality: Int { [26, 50, 90][quality] }
    /// Zoomed far out, tiny cosmetic effects are skipped.
    var detail: Bool { zoom < 2.2 && quality >= 1 }

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
            if (self?.fxPool.count ?? 999) < 500 { self?.fxPool.append(s) }
        }])
    }

    func visibleToMe(_ x: Double, _ y: Double) -> Bool { ctl.spectating || world.players[ctl.me].visible[world.tileIndex(x, y)] > 0 }

    func onScreen(_ p: CGPoint) -> Bool {
        let c = cam.position
        return abs(p.x - c.x) < size.width * zoom * 0.6 + 80 && abs(p.y - c.y) < size.height * zoom * 0.6 + 80
    }

    /// Short-lived sprite helper.
    @discardableResult
    func puff(_ tex: String, at p: CGPoint, size: CGSize, color: SKColor, alpha: CGFloat = 1, blend: SKBlendMode = .add, z: CGFloat = 455,
              life: Double, rise: CGFloat = 0, grow: CGFloat = 1, drift: CGFloat = 0) -> SKSpriteNode? {
        guard let s = fx() else { return nil }
        s.texture = bank.fx[tex]; s.size = size; s.color = color; s.alpha = alpha; s.blendMode = blend
        s.position = p; s.zPosition = z
        s.run(.group([.moveBy(x: drift, y: rise, duration: life), .scale(to: grow, duration: life), .fadeOut(withDuration: life)]))
        s.run(recycle(s, after: life + 0.02))
        return s
    }

    // MARK: Screen shake (trauma model; offsets the world, not the camera, so tracking stays smooth)

    func addTrauma(_ amount: CGFloat, at p: CGPoint) {
        guard shakeEnabled, onScreen(p) else { return }
        trauma = min(1, trauma + amount)
    }

    func applyShake(_ dt: Double) {
        trauma = max(0, trauma - CGFloat(dt) * 1.8)
        let s = trauma * trauma * 10 * min(1.6, zoom)
        let t = CACurrentMediaTime()
        worldNode.position = CGPoint(x: s * CGFloat(sin(t * 47) + sin(t * 23) * 0.5), y: s * 0.6 * CGFloat(cos(t * 41) + sin(t * 17) * 0.5))
    }

    // MARK: Unit motion, aiming, damage reactions

    func animateUnit(_ e: Entity, _ v: EntityView, _ t: Double) {
        let d = world.udef(e)
        let sx = cos(e.facing) + sin(e.facing)
        if abs(sx) > 0.15 {
            let ns: CGFloat = sx < 0 ? -1 : 1
            if ns != v.facingSign { v.facingSign = ns; v.turnT = 0.14 }
        }
        let fac = world.players[e.owner].faction
        let seed = Double(e.id % 97)
        let speed = world.speed(e)
        if !v.frames.isEmpty {
            let rate = e.isAir ? 10.0 : 3.2 * max(1.5, speed)
            let fr = (e.moving || e.isAir) ? Int(t * rate + seed) % v.frames.count : 0
            if v.body.texture !== v.frames[fr] { v.body.texture = v.frames[fr] }
        }
        var y = v.bodyY
        var rot: CGFloat = 0
        var sy: CGFloat = 1
        if e.isAir {
            y += CGFloat(sin(t * 2.2 + seed)) * 2.5
            let target = CGFloat(-sx) * 0.14 * (e.moving ? 1 : 0.2)
            v.turn += (target - v.turn) * 0.1
            rot = v.turn
        } else if e.moving {
            switch fac {
            case .humans: y += CGFloat(abs(sin(t * 10 + seed))) * (v.vehicle ? 0.5 : 1.3)
            case .machines: rot = CGFloat(sin(t * 7 + seed)) * 0.025; y += CGFloat(abs(sin(t * 7 + seed))) * 0.8
            case .aliens: sy = 1 + CGFloat(sin(t * 12 + seed)) * 0.05; rot = CGFloat(sin(t * 6 + seed)) * 0.05
            }
        } else if fac == .aliens {
            sy = 1 + CGFloat(sin(t * 2.5 + seed)) * 0.03
        }
        // Weapon recoil, scaled by the gun's punch; vehicles pitch up a touch when firing.
        let sinceFire = t - e.lastFireTime
        var kick: CGFloat = 0
        if sinceFire < 0.14, let w = world.weapon(e) {
            let f = CGFloat(1 - sinceFire / 0.14)
            kick = f * min(6, 1.2 + CGFloat(w.damage) / 11)
            if v.vehicle || v.heavy { rot += f * 0.06 }
        }
        // Damage reaction: a jolt that decays.
        if e.lastHitTime > v.lastHit { v.lastHit = e.lastHitTime; v.jolt = min(3.5, v.jolt + 1.6) }
        v.jolt = max(0, v.jolt - 0.25)
        let joltX = v.jolt * CGFloat(sin(t * 70 + seed))
        // Turning: a quick squash through the profile instead of an instant mirror.
        var xMag: CGFloat = 1
        if v.turnT > 0 { v.turnT -= 1.0 / 60; xMag = max(0.2, abs(CGFloat(cos((0.14 - v.turnT) / 0.14 * .pi)))) }
        v.body.position = CGPoint(x: -v.facingSign * kick + joltX, y: y)
        v.body.zRotation = rot * v.facingSign
        v.body.xScale = v.facingSign * xMag
        v.body.yScale = sy
        v.body.alpha = world.isCloaked(e) ? 0.4 + 0.1 * CGFloat(sin(t * 6)) : 1
        let hpFrac = e.hp / max(1, e.maxHp)
        if t - e.lastHitTime < 0.08 {
            v.body.colorBlendFactor = 0.6; v.body.color = SKColor(red: 1, green: 0.95, blue: 0.9, alpha: 1)
        } else if e.disruptedUntil > t {
            v.body.colorBlendFactor = 0.35; v.body.color = SKColor(red: 0.4, green: 0.6, blue: 1, alpha: 1)
        } else { v.body.colorBlendFactor = 0 }
        // Team ring: stronger when zoomed out; critical units pulse red.
        if let ring = v.teamRing {
            let far = zoom > 1.8
            ring.setScale(far ? 1.18 : 1)
            if hpFrac < 0.3 {
                let pulse = CGFloat(0.5 + 0.5 * sin(t * 12 + seed))
                ring.color = TeamColor.sk(e.owner).blend(SKColor(red: 1, green: 0.15, blue: 0.1, alpha: 1), pulse * 0.8)
                ring.alpha = 0.95
            } else {
                ring.color = TeamColor.sk(e.owner)
                ring.alpha = (e.isAir ? 0.55 : 0.78) + (far ? 0.17 : 0) + (fac == .machines && e.linked ? 0.15 * CGFloat(sin(t * 4 + seed)) : 0)
            }
        }
        unitLights(e, v, fac, t, seed)
        layTracks(e, v)
        if world.traits[e.type].worker { workerLife(e, v, t, seed) }
        // Ambient motion effects (budgeted, skipped when zoomed far out).
        v.dustT -= 1.0 / 60
        guard detail, v.dustT <= 0, onScreen(v.root.position) else { return }
        let p = v.root.position
        if hpFrac < 0.3 {
            v.dustT = 0.3
            switch fac {
            case .aliens: puff("orb", at: CGPoint(x: p.x, y: p.y + v.body.size.height * 0.4), size: CGSize(width: 5, height: 6), color: SKColor(red: 0.5, green: 0.9, blue: 0.25, alpha: 1), blend: .alpha, life: 0.6, rise: -10)
            default: puff("smoke", at: CGPoint(x: p.x, y: p.y + v.body.size.height * 0.55 + (e.isAir ? 38 : 0)), size: CGSize(width: 12, height: 12), color: SKColor(white: 0.15, alpha: 1), alpha: 0.7, blend: .alpha, life: 1.0, rise: 26, grow: 2.2, drift: 6)
                if fac == .machines && Int(t * 3 + seed) % 2 == 0 { puff("spark", at: CGPoint(x: p.x, y: p.y + v.body.size.height * 0.5), size: CGSize(width: 10, height: 10), color: SKColor(red: 0.5, green: 0.9, blue: 1, alpha: 1), life: 0.2) }
            }
        } else if e.moving && quality == 2 {
            if e.isAir {
                v.dustT = 0.12
                puff("glow", at: CGPoint(x: p.x - v.facingSign * v.body.size.width * 0.35, y: p.y + v.bodyY), size: CGSize(width: 9, height: 6),
                     color: fac == .aliens ? SKColor(red: 0.6, green: 1, blue: 0.5, alpha: 1) : SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1), alpha: 0.6, life: 0.35, grow: 0.3)
            } else if v.vehicle || v.heavy || d.tags.contains("massive") {
                v.dustT = 0.22
                puff("smoke", at: CGPoint(x: p.x - v.facingSign * v.body.size.width * 0.3, y: p.y + 3), size: CGSize(width: 14, height: 9),
                     color: SKColor(red: 0.62, green: 0.54, blue: 0.42, alpha: 1), alpha: 0.45, blend: .alpha, z: 95, life: 0.8, rise: 6, grow: 2.0)
            }
        }
    }

    static func resourceColor(_ k: ResourceKind) -> SKColor {
        switch k {
        case .iron: return SKColor(red: 0.72, green: 0.8, blue: 0.9, alpha: 1)
        case .gold: return SKColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        case .wood: return SKColor(red: 0.72, green: 0.5, blue: 0.3, alpha: 1)
        }
    }

    /// Economy readability: chips fly while harvesting, workers visibly carry their load, deliveries pop
    /// a "+N", and idle workers wear a small amber marker so they are easy to spot.
    func workerLife(_ e: Entity, _ v: EntityView, _ t: Double, _ seed: Double) {
        let mine = e.owner == ctl.me || ctl.spectating
        // Harvest tick: cargo grew.
        if e.carryAmount > v.lastCarry, let node = world.entity(e.gatherNode), let nv = views[node.id], onScreen(v.root.position) {
            nv.shake = 1
            let p = nv.root.position
            let col = GameScene.resourceColor(e.carryKind)
            if detail {
                for k in 0..<2 {
                    puff(e.carryKind == .wood ? "pixel" : "spark", at: CGPoint(x: p.x + CGFloat(k * 8 - 4), y: p.y + 14), size: CGSize(width: 4, height: 4),
                         color: col, blend: .alpha, z: 456, life: 0.45, rise: 14, drift: CGFloat(k * 2 - 1) * 12)
                }
            }
        }
        // Delivery: cargo emptied.
        if e.carryAmount == 0 && v.lastCarry > 0 && mine && e.owner == ctl.me && zoom < 2.2 && onScreen(v.root.position) {
            floatLabel("+\(v.lastCarry)", at: CGPoint(x: v.root.position.x, y: v.root.position.y + v.body.size.height + 4), color: GameScene.resourceColor(e.carryKind))
        }
        v.lastCarry = e.carryAmount
        // Carried load.
        if e.carryAmount > 0 {
            if v.cargo == nil {
                let c = SKSpriteNode(texture: bank.shards[0], size: CGSize(width: 9, height: 9))
                c.colorBlendFactor = 0.85; c.zPosition = 0.2
                v.root.addChild(c); v.cargo = c
            }
            v.cargo!.isHidden = false
            v.cargo!.color = GameScene.resourceColor(e.carryKind)
            v.cargo!.position = CGPoint(x: v.body.position.x - v.facingSign * v.body.size.width * 0.22, y: v.body.position.y + v.body.size.height * 0.42)
        } else { v.cargo?.isHidden = true }
        // Idle marker (own workers only, after a moment of idleness).
        let idle = e.owner == ctl.me && e.order == .idle && !e.moving
        if idle { if v.idleSince < 0 { v.idleSince = t } } else { v.idleSince = -1 }
        if idle && t - v.idleSince > 1.5 {
            if v.idleMark == nil {
                let m = SKSpriteNode(texture: bank.fx["pixel"], size: CGSize(width: 6, height: 6))
                m.color = SKColor(red: 1, green: 0.72, blue: 0.2, alpha: 1); m.colorBlendFactor = 1
                m.zRotation = .pi / 4; m.zPosition = 0.3
                let g = SKSpriteNode(texture: bank.fx["glow"], size: CGSize(width: 18, height: 18))
                g.color = m.color; g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0.6; g.zPosition = -0.01
                m.addChild(g)
                v.root.addChild(m); v.idleMark = m
            }
            v.idleMark!.isHidden = false
            v.idleMark!.position = CGPoint(x: 0, y: v.body.size.height * 0.95 + 4 + CGFloat(sin(t * 4 + seed)) * 2)
        } else { v.idleMark?.isHidden = true }
    }

    /// Small pooled floating text (deliveries).
    func floatLabel(_ text: String, at p: CGPoint, color: SKColor) {
        let l: SKLabelNode
        if let free = labelPool.first(where: { $0.parent == nil }) { l = free } else {
            guard labelPool.count < 16 else { return }
            l = SKLabelNode(fontNamed: "Menlo-Bold")
            l.fontSize = 13; l.verticalAlignmentMode = .center
            let sh = SKLabelNode(fontNamed: "Menlo-Bold")
            sh.fontSize = 13; sh.verticalAlignmentMode = .center; sh.fontColor = SKColor(white: 0, alpha: 0.75)
            sh.position = CGPoint(x: 1, y: -1); sh.zPosition = -0.01; sh.name = "shadow"
            l.addChild(sh)
            labelPool.append(l)
        }
        l.removeAllActions()
        (l.childNode(withName: "shadow") as? SKLabelNode)?.text = text
        l.text = text; l.fontColor = color; l.alpha = 1; l.position = p; l.zPosition = 480
        l.setScale(min(1.6, max(1, zoom * 0.9)))
        worldNode.addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 22, duration: 0.9), .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.45)])]), .removeFromParent()]))
    }

    /// Night lighting on units: aircraft navigation lights, vehicle headlights, Brood bioluminescence.
    func unitLights(_ e: Entity, _ v: EntityView, _ fac: Faction, _ t: Double, _ seed: Double) {
        let on = night > 0.15 && quality >= 1 && zoom < 2.6
        if !on {
            if v.headlight?.isHidden == false { v.headlight?.isHidden = true }
            for l in v.navLights where !l.isHidden { l.isHidden = true }
            return
        }
        func dot(_ c: SKColor, _ sz: CGFloat) -> SKSpriteNode {
            let l = SKSpriteNode(texture: bank.fx["glow"], size: CGSize(width: sz, height: sz))
            l.blendMode = .add; l.colorBlendFactor = 1; l.color = c
            v.root.addChild(l); v.navLights.append(l)
            return l
        }
        let w = v.body.size.width
        if e.isAir {
            if v.navLights.isEmpty {
                _ = dot(SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 1), 9)
                _ = dot(SKColor(red: 0.3, green: 1, blue: 0.5, alpha: 1), 9)
                _ = dot(.white, 7)
            }
            let span = w * 0.34
            v.navLights[0].position = CGPoint(x: v.body.position.x - span, y: v.body.position.y)
            v.navLights[1].position = CGPoint(x: v.body.position.x + span, y: v.body.position.y)
            v.navLights[2].position = CGPoint(x: v.body.position.x, y: v.body.position.y - 6)
            let blink = (t * 1.3 + seed * 0.37).truncatingRemainder(dividingBy: 1) < 0.12
            v.navLights[0].alpha = night; v.navLights[1].alpha = night
            v.navLights[2].alpha = blink ? night : 0
        } else if fac == .aliens {
            if v.navLights.isEmpty { _ = dot(SKColor(red: 0.55, green: 1, blue: 0.4, alpha: 1), max(14, w * 0.55)) }
            v.navLights[0].position = CGPoint(x: v.body.position.x, y: v.body.position.y + v.body.size.height * 0.32)
            v.navLights[0].alpha = night * (0.25 + 0.18 * CGFloat(sin(t * 2.2 + seed)))
        } else if v.vehicle || v.heavy {
            if v.headlight == nil {
                let h = SKSpriteNode(texture: bank.fx["cone"])
                h.anchorPoint = CGPoint(x: 0.04, y: 0.5); h.blendMode = .add; h.colorBlendFactor = 1
                h.color = fac == .humans ? SKColor(red: 1, green: 0.92, blue: 0.7, alpha: 1) : SKColor(red: 0.6, green: 0.95, blue: 1, alpha: 1)
                h.size = CGSize(width: 64 + w * 0.3, height: 30)
                v.root.addChild(h); v.headlight = h
            }
            let h = v.headlight!
            let dx = cos(e.facing), dy = sin(e.facing)
            let ang = atan2(16 * (dy - dx), 32 * (dx + dy))
            h.zRotation = CGFloat(ang)
            h.position = CGPoint(x: CGFloat(cos(ang)) * w * 0.26, y: 7 + CGFloat(sin(ang)) * w * 0.13)
            h.alpha = night * 0.42
        } else {
            v.headlight?.isHidden = true
            return
        }
        v.headlight?.isHidden = false
        for l in v.navLights { l.isHidden = false; liftLight(l, in: v, by: 1) }
        if let h = v.headlight { liftLight(h, in: v) }
    }

    // MARK: Projectiles & artillery telegraphs

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
        var markers = 0
        let trailEvery = quality == 2 ? 2 : (quality == 1 ? 4 : 0)
        for (i, p) in ps.enumerated() {
            let s = projPool[i]
            let vis = visibleToMe(p.x, p.y)
            s.isHidden = !vis
            if !vis { continue }
            let pos = Iso.scene(p.x, p.y)
            let total = max(0.05, p.total)
            let t = min(1, p.age / total)
            let src = world.entity(p.source)
            let srcAlt: CGFloat = (src?.isAir ?? false) ? 38 : 16
            let dstAlt: CGFloat = p.targetAir ? 38 : 9
            var alt: CGFloat = srcAlt + (dstAlt - srcAlt) * CGFloat(t)
            let arcing = ["shell", "acid", "spore", "bomb"].contains(p.style)
            let arcH = CGFloat(min(130, total * 52))
            if arcing { alt += CGFloat(sin(t * .pi)) * arcH }
            let point = CGPoint(x: pos.x, y: pos.y + alt)
            let sa = Iso.scene(p.sx, p.sy), ta = Iso.scene(p.tx, p.ty)
            var ang = atan2(ta.y - sa.y + (dstAlt - srcAlt), ta.x - sa.x)
            if arcing { ang = atan2((ta.y - sa.y) / total + CGFloat(cos(t * .pi)) * .pi * arcH / CGFloat(total), (ta.x - sa.x) / total) }
            s.position = point
            s.zRotation = ang
            let col = GameScene.styleColor(p.style)
            s.color = col
            let halo = s.children.first as? SKSpriteNode
            halo?.color = col
            halo?.position = .zero
            let heavy = p.damage >= 30
            switch p.style {
            case "shell", "bomb":
                s.texture = bank.fx["shell"]; s.size = CGSize(width: heavy ? 10 : 8, height: heavy ? 10 : 8); s.blendMode = .alpha; s.colorBlendFactor = 0.25
                halo?.size = CGSize(width: 18, height: 18); halo?.alpha = 0.55
            case "acid", "spore":
                s.texture = bank.fx["orb"]; s.size = CGSize(width: heavy ? 15 : 11, height: heavy ? 13 : 10); s.blendMode = .alpha; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 30, height: 30); halo?.alpha = 0.75
            case "flak", "pulse":
                s.texture = bank.fx["orb"]; s.size = CGSize(width: 11, height: 11); s.blendMode = .add; s.colorBlendFactor = 1
                halo?.size = CGSize(width: heavy ? 40 : 30, height: heavy ? 40 : 30); halo?.alpha = 0.9
            case "rocket", "missile":
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: heavy ? 16 : 13, height: 4.5); s.blendMode = .alpha; s.colorBlendFactor = 0.25
                halo?.size = CGSize(width: 18, height: 18); halo?.alpha = 0.95; halo?.position = CGPoint(x: -8, y: 0)
            case "spine":
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: 16, height: 2.6); s.blendMode = .alpha; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 10, height: 10); halo?.alpha = 0.25
            default:
                s.texture = bank.fx["bolt"]; s.size = CGSize(width: 22, height: 2.6); s.blendMode = .add; s.colorBlendFactor = 1
                halo?.size = CGSize(width: 16, height: 10); halo?.alpha = 0.5
            }
            // Trails: missile smoke, AA contrails, acid drips, shell glitter.
            if trailEvery > 0, (trailTick + i) % trailEvery == 0, onScreen(point) {
                if p.targetAir {
                    puff("glow", at: point, size: CGSize(width: 7, height: 7), color: SKColor(white: 0.95, alpha: 1), alpha: 0.7, blend: .add, z: 399, life: 0.45, grow: 2.2)
                } else if p.style == "rocket" || p.style == "missile" || p.style == "shell" {
                    puff("smoke", at: point, size: CGSize(width: 9, height: 9), color: SKColor(white: 0.78, alpha: 1), alpha: 0.55, blend: .alpha, z: 399, life: 0.55, rise: 3, grow: 2.4)
                } else if p.style == "acid" || p.style == "spore" {
                    puff("orb", at: point, size: CGSize(width: 5, height: 5), color: col, alpha: 0.8, blend: .alpha, z: 399, life: 0.4, rise: -14)
                }
            }
            // Telegraph where artillery will land: a pulsing danger reticle sized to the splash.
            if arcing && p.splash > 0 && p.target < 0 {
                let m = marker(markers); markers += 1
                let r = CGFloat(max(0.8, p.splash))
                m.position = ta
                m.size = CGSize(width: r * 92, height: r * 46)
                m.color = p.owner == ctl.me && !ctl.spectating ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1) : SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 1)
                m.alpha = 0.35 + 0.5 * CGFloat(t) * CGFloat(0.6 + 0.4 * sin(world.time * 20))
                m.setScale(1.25 - 0.25 * CGFloat(t))
                m.isHidden = false
            }
        }
        for i in ps.count..<projPool.count { projPool[i].isHidden = true }
        for i in markers..<markerPool.count { markerPool[i].isHidden = true }
    }

    func marker(_ i: Int) -> SKSpriteNode {
        if i < markerPool.count { return markerPool[i] }
        let m = SKSpriteNode(texture: bank.fx["ring_marker"])
        m.colorBlendFactor = 1; m.zPosition = 8
        worldNode.addChild(m)
        markerPool.append(m)
        return m
    }

    // MARK: Event consumption

    func consumeEvents() {
        for ev in world.events {
            switch ev {
            case .shot(let from, let fx0, let fy0, let tx, let ty, let style, _, let air):
                guard visibleToMe(fx0, fy0) || visibleToMe(tx, ty) else { continue }
                let src = world.entity(from)
                let srcAir = src?.isAir ?? false
                if style == "arc" { lightningFX(fx0, fy0, tx, ty, srcAir, air) }
                else if style == "rail" || style == "beam" { beam(fx0, fy0, tx, ty, style, srcAir, air) }
                if style == "claw" { slashFX(tx, ty, air) }
                else if let s = src { muzzle(s, style, toward: (tx, ty)) }
                sfx?.shot(style, at: Iso.scene(fx0, fy0))
            case .impact(let x, let y, let r, let style, let air, let power, let surface):
                if ctl.spectating { battleCam.record(x, y, weight: power * (1 + r), time: world.time) }
                guard visibleToMe(x, y) else { continue }
                impact(x, y, radius: r, style: style, air: air, power: power, surface: surface)
                if !air && r >= 0.9 && surface != "structure" {
                    let c = CGFloat(min(2.2, r))
                    scar("crater", at: Iso.scene(x, y), size: CGSize(width: 50 * c, height: 25 * c), color: biomeEarth, alpha: 0.85)
                }
            case .death(let x, let y, let big, _, let air, let building):
                if ctl.spectating { battleCam.record(x, y, weight: big ? 140 : 50, time: world.time) }
                guard visibleToMe(x, y) else { continue }
                let r = building ? 2.6 : (big ? 1.7 : 0.8)
                explosion(x, y, radius: r, air: air, power: building ? 120 : (big ? 90 : 35))
                sfx?.explosion(big: building || big, at: Iso.scene(x, y))
            case .heal(let x, let y):
                guard visibleToMe(x, y) else { continue }
                let p = Iso.scene(x, y)
                puff("spark", at: CGPoint(x: p.x, y: p.y + 20), size: CGSize(width: 14, height: 14), color: SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1), z: 450, life: 0.7, rise: 16)
            case .emp(let x, let y, let r):
                for k in 0..<2 {
                    guard let s = fx() else { break }
                    s.texture = bank.fx["shockwave"]; s.size = CGSize(width: 24, height: 12)
                    s.color = SKColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)
                    s.position = Iso.scene(x, y); s.zPosition = 455
                    s.run(.sequence([.wait(forDuration: Double(k) * 0.12), .group([.scale(to: CGFloat(r) * 7.5, duration: 0.45), .fadeOut(withDuration: 0.5)])]))
                    s.run(recycle(s, after: 0.65))
                }
                addTrauma(0.25, at: Iso.scene(x, y))
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
        for c in world.clouds where visibleToMe(c.x, c.y) && world.tick % (quality == 2 ? 5 : 9) == 0 {
            let jx = Double(hnoise(world.tick, Int(c.x * 10), 3) - 0.5) * c.radius
            let p = Iso.scene(c.x + jx, c.y)
            puff("smoke", at: CGPoint(x: p.x, y: p.y + 6), size: CGSize(width: CGFloat(c.radius) * 64, height: CGFloat(c.radius) * 32),
                 color: c.slow < 1 ? SKColor(red: 0.72, green: 0.42, blue: 0.95, alpha: 1) : SKColor(red: 0.55, green: 0.95, blue: 0.3, alpha: 1),
                 alpha: 0.45, blend: .alpha, z: 90, life: 0.8, rise: 8, grow: 1.25)
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

    /// Muzzle flash at the weapon end of the sprite, sized by damage and coloured by weapon family.
    func muzzle(_ src: Entity, _ style: String, toward: (Double, Double)) {
        guard let v = views[src.id], !v.root.isHidden else { return }
        let base = v.root.position
        guard onScreen(base) else { return }
        let dmg = CGFloat(world.weapon(src)?.damage ?? 8)
        if dmg < 10 && !detail { return }
        let tp = Iso.scene(toward.0, toward.1)
        let a = atan2(tp.y - base.y, tp.x - base.x)
        let w = v.body.size.width, h = v.body.size.height
        let tip = CGPoint(x: base.x + cos(a) * w * 0.42, y: base.y + (src.isAir ? 38 : h * 0.45) + sin(a) * w * 0.18)
        let size = min(42, 12 + dmg * 0.55)
        let col = GameScene.styleColor(style)
        switch GameScene.family(style) {
        case .ballistic:
            if let s = fx() {
                s.texture = bank.sparks[0]; s.size = CGSize(width: size, height: size); s.color = col; s.position = tip; s.zPosition = 452; s.zRotation = a
                s.run(.animate(with: Array(bank.sparks.prefix(2)), timePerFrame: 0.035)); s.run(recycle(s, after: 0.08))
            }
            if dmg >= 25 && detail { puff("smoke", at: tip, size: CGSize(width: size * 0.7, height: size * 0.7), color: SKColor(white: 0.7, alpha: 1), alpha: 0.5, blend: .alpha, z: 451, life: 0.6, rise: 10, grow: 2) }
        case .energy:
            puff("glow", at: tip, size: CGSize(width: size * 1.2, height: size * 1.2), color: col, z: 452, life: 0.12, grow: 0.4)
            if dmg >= 25 { puff("shockwave", at: tip, size: CGSize(width: size, height: size * 0.5), color: col, alpha: 0.8, z: 452, life: 0.2, grow: 2.2) }
        case .bio:
            puff("orb", at: tip, size: CGSize(width: size * 0.5, height: size * 0.5), color: col, alpha: 0.85, blend: .alpha, z: 452, life: 0.22, grow: 1.8)
        }
    }

    func slashFX(_ x: Double, _ y: Double, _ air: Bool) {
        let p = Iso.scene(x, y)
        guard onScreen(p), let s = fx() else { return }
        s.texture = bank.fx["slash"]; s.size = CGSize(width: 30, height: 30)
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
        for (w, life, a) in [(rail ? 14.0 : 6.0, rail ? 0.45 : 0.16, 0.35), (rail ? 4.0 : 2.2, rail ? 0.25 : 0.1, 1.0)] as [(CGFloat, Double, CGFloat)] {
            guard let s = fx() else { return }
            s.texture = bank.fx["beam"]; s.anchorPoint = CGPoint(x: 0, y: 0.5)
            s.size = CGSize(width: len, height: w); s.position = pa; s.zRotation = ang
            s.color = GameScene.styleColor(style); s.alpha = a; s.zPosition = 456
            s.run(.group([.fadeOut(withDuration: life), .scaleY(to: 0.15, duration: life)])); s.run(recycle(s, after: life + 0.02))
        }
        if rail && detail {
            // Ionised trail: sparkles left along the slug's path.
            for k in 1..<6 {
                let f = CGFloat(k) / 6
                puff("spark", at: CGPoint(x: pa.x + (pb.x - pa.x) * f, y: pa.y + (pb.y - pa.y) * f), size: CGSize(width: 8, height: 8), color: GameScene.styleColor("rail"), alpha: 0.8, z: 456, life: 0.5, rise: 5)
            }
        }
    }

    func lightningFX(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ srcAir: Bool, _ air: Bool) {
        let (pa, pb) = endpoints(x0, y0, x1, y1, srcAir, air)
        guard onScreen(pa) || onScreen(pb), let s = fx() else { return }
        let len = hypot(pb.x - pa.x, pb.y - pa.y)
        s.texture = bank.lightning[Int(hnoise(world.tick, Int(x0 * 5), 1) * 3) % 3]
        s.anchorPoint = CGPoint(x: 0, y: 0.5)
        s.size = CGSize(width: len, height: min(24, 9 + len * 0.12)); s.position = pa; s.zRotation = atan2(pb.y - pa.y, pb.x - pa.x)
        s.color = GameScene.styleColor("arc"); s.zPosition = 457
        s.yScale = hnoise(world.tick, 3, 3) > 0.5 ? 1 : -1
        s.run(.sequence([.fadeAlpha(to: 0.3, duration: 0.04), .fadeAlpha(to: 1, duration: 0.03), .fadeOut(withDuration: 0.1)])); s.run(recycle(s, after: 0.19))
        puff("glow", at: pb, size: CGSize(width: 24, height: 24), color: GameScene.styleColor("arc"), z: 457, life: 0.15)
    }

    // MARK: Impacts (by weapon family, power, splash and surface)

    func impact(_ x: Double, _ y: Double, radius: Double, style: String, air: Bool, power: Double, surface: String) {
        let p = Iso.scene(x, y)
        let base = CGPoint(x: p.x, y: p.y + (air ? 38 : 8))
        guard onScreen(base) else { return }
        let col = GameScene.styleColor(style)
        let fam = GameScene.family(style)
        let pw = CGFloat(power)
        // Anti-air: bursts in the sky.
        if air {
            switch fam {
            case .ballistic:
                puff("smoke", at: base, size: CGSize(width: 16 + pw * 0.4, height: 16 + pw * 0.4), color: SKColor(white: 0.25, alpha: 1), alpha: 0.75, blend: .alpha, z: 458, life: 0.7, rise: 6, grow: 1.8)
                puff("glow", at: base, size: CGSize(width: 26 + pw, height: 26 + pw), color: col, z: 459, life: 0.15)
            case .energy:
                puff("shockwave", at: base, size: CGSize(width: 20, height: 10), color: col, alpha: 0.95, z: 459, life: 0.3, grow: 2.4)
                puff("glow", at: base, size: CGSize(width: 28, height: 28), color: col, z: 459, life: 0.15)
            case .bio:
                puff("orb", at: base, size: CGSize(width: 14, height: 14), color: col, alpha: 0.85, blend: .alpha, z: 459, life: 0.35, grow: 2.2)
            }
            if radius >= 1 { addTrauma(0.05, at: base) }
            return
        }
        // Area attacks: show the true splash footprint, then the family explosion.
        if radius >= 0.6 {
            let r = CGFloat(radius)
            puff("shockwave", at: p, size: CGSize(width: r * 92, height: r * 46), color: fam == .bio ? col : (fam == .energy ? col : SKColor(red: 1, green: 0.8, blue: 0.5, alpha: 1)),
                 alpha: 0.9, z: 7, life: 0.35, grow: 1.08)
            switch fam {
            case .ballistic: explosion(x, y, radius: radius, air: false, power: power)
            case .energy:
                puff("glow", at: base, size: CGSize(width: 46 * r, height: 34 * r), color: col, z: 459, life: 0.25, grow: 1.2)
                if style == "quake" {
                    for k in 0..<3 {
                        guard let w = fx() else { break }
                        w.texture = bank.fx["shockwave"]; w.size = CGSize(width: 30 * r, height: 15 * r); w.color = col; w.position = p; w.zPosition = 7; w.setScale(0.3)
                        w.run(.sequence([.wait(forDuration: Double(k) * 0.1), .group([.scale(to: 1.5, duration: 0.45), .fadeOut(withDuration: 0.45)])])); w.run(recycle(w, after: 0.8))
                    }
                    puff("smoke", at: base, size: CGSize(width: 40 * r, height: 22 * r), color: SKColor(red: 0.55, green: 0.5, blue: 0.45, alpha: 1), alpha: 0.6, blend: .alpha, z: 458, life: 0.9, rise: 10, grow: 1.4)
                }
                for k in 0..<(detail ? 4 : 2) {
                    let a = CGFloat(k) * 1.6 + CGFloat(x)
                    puff("spark", at: base, size: CGSize(width: 10, height: 10), color: col, z: 460, life: 0.3, rise: sin(a) * 18 * r, drift: cos(a) * 26 * r)
                }
            case .bio: splash(base, radius: radius, color: col)
            }
            if !air && radius > 1.1 { decal(p, radius: radius, color: fam == .bio ? col : SKColor(white: 0.05, alpha: 1), splat: fam == .bio) }
            addTrauma(min(0.4, pw / 260 + CGFloat(radius) * 0.04), at: base)
            return
        }
        // Single-target hits: react to what was hit.
        switch surface {
        case "metal", "structure":
            if let s = fx() {
                s.texture = bank.sparks[0]; s.size = CGSize(width: 16 + pw * 0.5, height: 16 + pw * 0.5); s.color = fam == .energy ? col : SKColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
                s.position = base; s.zPosition = 455
                s.run(.animate(with: bank.sparks, timePerFrame: 0.035)); s.run(recycle(s, after: 0.15))
            }
            if pw >= 24 {
                // Armour penetration: a white-hot flare and molten shards.
                puff("glow", at: base, size: CGSize(width: 30 + pw * 0.6, height: 30 + pw * 0.6), color: SKColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), z: 459, life: 0.12)
                if detail { for k in 0..<3 {
                    let a = CGFloat(k) * 2.1 + CGFloat(y)
                    puff("orb", at: base, size: CGSize(width: 5, height: 5), color: SKColor(red: 1, green: 0.55, blue: 0.15, alpha: 1), z: 460, life: 0.4, rise: abs(sin(a)) * 20 + 6, drift: cos(a) * 22)
                } }
                if pw >= 40 { addTrauma(0.08, at: base) }
            }
        case "ichor":
            puff("orb", at: base, size: CGSize(width: 10 + pw * 0.25, height: 9 + pw * 0.2), color: SKColor(red: 0.55, green: 0.95, blue: 0.25, alpha: 1), alpha: 0.85, blend: .alpha, z: 455, life: 0.3, rise: -4, grow: 1.8)
            if pw >= 20 && detail { decal(p, radius: 0.5, color: SKColor(red: 0.45, green: 0.8, blue: 0.2, alpha: 1), splat: true) }
        case "flesh":
            puff("orb", at: base, size: CGSize(width: 8 + pw * 0.2, height: 8 + pw * 0.2), color: SKColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1), alpha: 0.7, blend: .alpha, z: 455, life: 0.25, grow: 1.7)
            if fam == .ballistic, detail { puff("spark", at: base, size: CGSize(width: 10, height: 10), color: col, z: 455, life: 0.1) }
        default:
            puff("smoke", at: base, size: CGSize(width: 12, height: 9), color: SKColor(red: 0.6, green: 0.52, blue: 0.4, alpha: 1), alpha: 0.5, blend: .alpha, z: 455, life: 0.4, rise: 6, grow: 1.6)
        }
    }

    func splash(_ at: CGPoint, radius: Double, color: SKColor) {
        let r = CGFloat(max(0.6, radius))
        for k in 0..<(detail ? 6 : 3) {
            let a = CGFloat(k) * 1.05 + 0.4
            puff("orb", at: at, size: CGSize(width: 7, height: 7), color: color, alpha: 0.9, blend: .alpha, life: 0.35, rise: sin(a) * 9 * r + 12, drift: cos(a) * 20 * r)
        }
        puff("glow", at: at, size: CGSize(width: 40 * r, height: 24 * r), color: color, z: 454, life: 0.3, grow: 1.3)
        puff("smoke", at: at, size: CGSize(width: 34 * r, height: 20 * r), color: color.blend(.black, 0.4), alpha: 0.5, blend: .alpha, z: 453, life: 0.9, rise: 10, grow: 1.4)
    }

    /// Staged explosion: white flash, fireball flipbook, shockwave, debris arcs, smoke column (heavy), scorch.
    func explosion(_ x: Double, _ y: Double, radius: Double, air: Bool, power: Double) {
        let p = Iso.scene(x, y)
        let base = CGPoint(x: p.x, y: p.y + (air ? 38 : 10))
        guard onScreen(base) else { return }
        let r = CGFloat(max(0.5, radius))
        let heavy = power >= 60 || radius >= 1.5
        puff("glow", at: base, size: CGSize(width: 70 * r, height: 55 * r), color: SKColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), z: 462, life: 0.08)
        if let s = fx() {
            s.texture = bank.explosion[0]; s.blendMode = .alpha; s.colorBlendFactor = 0
            s.size = CGSize(width: 64 * r, height: 64 * r); s.position = CGPoint(x: base.x, y: base.y + 10 * r); s.zPosition = 460
            let tpf = heavy ? 0.065 : 0.045
            s.run(.animate(with: bank.explosion, timePerFrame: tpf)); s.run(recycle(s, after: tpf * 8 + 0.02))
        }
        puff("glow", at: base, size: CGSize(width: 96 * r, height: 64 * r), color: SKColor(red: 1, green: 0.66, blue: 0.3, alpha: 1), alpha: 0.85, z: 459, life: 0.3)
        if !air { puff("shockwave", at: p, size: CGSize(width: 50 * r, height: 25 * r), color: SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1), z: 6, life: 0.45, grow: 1.5) }
        let shards = quality == 0 ? 1 : (heavy ? 6 : 3)
        for k in 0..<shards {
            guard let d = fx() else { break }
            d.texture = bank.shards[k % 2]; d.blendMode = .alpha; d.colorBlendFactor = 0
            d.size = CGSize(width: 7 + CGFloat(k % 3) * 2, height: 7 + CGFloat(k % 3) * 2)
            d.position = base; d.zPosition = 461
            let a = Double(k) * 2.1 + x * 3
            let dx = CGFloat(cos(a)) * 44 * r, up = 30 * r + CGFloat(k) * 4
            let arc = SKAction.customAction(withDuration: 0.65) { node, el in
                let t = el / 0.65
                node.position = CGPoint(x: base.x + dx * t, y: base.y + up * 4 * t * (1 - t) - (air ? 34 * t : 0))
            }
            d.run(.group([arc, .rotate(byAngle: 9, duration: 0.65), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.15)])]))
            d.run(recycle(d, after: 0.67))
        }
        if heavy && quality >= 1 {
            // Rising smoke column with embers.
            for k in 0..<3 {
                guard let s = fx() else { break }
                s.texture = bank.fx["smoke"]; s.blendMode = .alpha; s.size = CGSize(width: 30 * r, height: 30 * r)
                s.color = SKColor(white: 0.14, alpha: 1); s.alpha = 0; s.position = CGPoint(x: base.x, y: base.y + 8); s.zPosition = 458
                s.run(.sequence([.wait(forDuration: 0.15 + Double(k) * 0.18), .fadeAlpha(to: 0.65, duration: 0.1),
                                 .group([.moveBy(x: 12, y: 46 * r, duration: 1.8), .scale(to: 1.9, duration: 1.8), .fadeOut(withDuration: 1.8)])]))
                s.run(recycle(s, after: 2.4))
            }
        }
        if !air && radius > 1.0 { decal(p, radius: radius, color: SKColor(white: 0.05, alpha: 1), splat: false) }
        addTrauma(min(0.55, CGFloat(power) / 220), at: base)
    }

    /// Ground marks now persist (see GameScene+Scars): scorch from blasts, residue from Brood and Lattice losses.
    func decal(_ p: CGPoint, radius: Double, color: SKColor, splat: Bool) {
        guard quality >= 1 || radius > 1.5 else { return }
        let r = CGFloat(radius)
        scar(splat ? "residue" : "scorch", at: p, size: CGSize(width: 54 * r, height: 27 * r), color: color, alpha: splat ? 0.55 : 0.7,
             rotation: CGFloat(hnoise(Int(p.x), Int(p.y), 3) - 0.5) * 0.4, texture: splat ? bank.splats[Int(p.x) & 1] : bank.fx["scorch"])
    }

    // MARK: Deaths and wrecks

    func playDeath(_ e: Entity, _ v: EntityView) {
        let root = v.root
        let p = root.position
        guard onScreen(p) else { root.removeFromParent(); return }
        v.teamRing?.run(.fadeOut(withDuration: 0.2))
        v.field?.run(.fadeOut(withDuration: 0.3))
        v.ring?.removeFromParent()
        v.shadow?.run(.fadeOut(withDuration: 0.4))
        v.lights.forEach { $0.removeFromParent() }
        v.fire?.removeFromParent()
        if e.isResource {
            if e.type == ResourceKind.wood.rawValue {
                // The last tree in a stand topples, kicking up leaves and dust.
                let dir: CGFloat = hnoise(e.id, 2, 2) > 0.5 ? 1 : -1
                v.body.anchorPoint = CGPoint(x: 0.5, y: 0.08)
                v.body.shader = nil
                let fall = SKAction.rotate(byAngle: -1.45 * dir, duration: 0.75); fall.timingMode = .easeIn
                v.body.run(.sequence([fall,
                                    .run { [weak self] in
                                        guard let self = self else { return }
                                        let q = CGPoint(x: p.x + dir * 40, y: p.y + 4)
                                        self.puff("smoke", at: q, size: CGSize(width: 40, height: 20), color: SKColor(red: 0.55, green: 0.47, blue: 0.36, alpha: 1), alpha: 0.6, blend: .alpha, z: 95, life: 0.9, rise: 6, grow: 1.8)
                                        for k in 0..<5 {
                                            self.puff("pixel", at: CGPoint(x: q.x + CGFloat(k * 9 - 18), y: q.y + 10), size: CGSize(width: 4, height: 3),
                                                      color: SKColor(red: 0.45, green: 0.6, blue: 0.25, alpha: 1), blend: .alpha, z: 456, life: 1.1, rise: CGFloat(10 + k * 3), drift: CGFloat(k * 6 - 12))
                                        }
                                        self.addTrauma(0.04, at: q)
                                    },
                                    .wait(forDuration: 1.2), .fadeOut(withDuration: 0.8)]))
                root.run(.sequence([.wait(forDuration: 2.8), .removeFromParent()]))
            } else {
                // A depleted deposit crumbles into dust.
                puff("smoke", at: CGPoint(x: p.x, y: p.y + 6), size: CGSize(width: 50, height: 26), color: SKColor(white: 0.5, alpha: 1), alpha: 0.55, blend: .alpha, z: 95, life: 1.0, rise: 8, grow: 1.6)
                root.run(.sequence([.group([.fadeOut(withDuration: 0.7), .scaleY(to: 0.3, duration: 0.7)]), .removeFromParent()]))
            }
            return
        }
        if e.isBuilding {
            v.body.run(.group([.moveBy(x: 0, y: -26, duration: 1.4), .scaleY(to: 0.55, duration: 1.4), .fadeOut(withDuration: 1.4)]))
            for k in 0..<4 {
                run(.sequence([.wait(forDuration: Double(k) * 0.22), .run { [weak self] in
                    self?.explosion(e.x + Double(k % 2) - 0.5, e.y + Double(k / 2) - 0.5, radius: 1.3, air: false, power: k == 0 ? 120 : 60)
                }]))
            }
            let rubble = SKSpriteNode(texture: bank.fx["rubble"])
            rubble.size = CGSize(width: CGFloat(e.size) * 58, height: CGFloat(e.size) * 29)
            rubble.position = p; rubble.zPosition = 5
            worldNode.addChild(rubble)
            rubble.run(.sequence([.wait(forDuration: 110), .fadeOut(withDuration: 10), .removeFromParent()]))
            scar("scorch", at: p, size: CGSize(width: CGFloat(e.size) * 80, height: CGFloat(e.size) * 40), color: SKColor(white: 0.03, alpha: 1), alpha: 0.8)
            // Smouldering ruins for a while.
            rubble.run(.repeat(.sequence([.run { [weak self] in
                guard let self = self, self.onScreen(p) else { return }
                self.puff("smoke", at: CGPoint(x: p.x + CGFloat.random(in: -20...20), y: p.y + 8), size: CGSize(width: 22, height: 22), color: SKColor(white: 0.18, alpha: 1),
                          alpha: 0.5, blend: .alpha, z: 458, life: 2.2, rise: 50, grow: 2.6, drift: 14)
            }, .wait(forDuration: 0.6)]), count: 40))
            root.run(.sequence([.wait(forDuration: 1.5), .removeFromParent()]))
            return
        }
        let fac = world.players[max(0, e.owner)].faction
        let body = v.body
        let side = v.facingSign
        if e.isAir {
            // Spiral down trailing smoke, then crash.
            body.run(.group([.moveBy(x: 34 * side, y: -40, duration: 0.8), .rotate(byAngle: -2.2 * side, duration: 0.8), .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.2)])]))
            for k in 0..<4 {
                run(.sequence([.wait(forDuration: Double(k) * 0.18), .run { [weak self] in
                    guard let self = self else { return }
                    self.puff("smoke", at: CGPoint(x: p.x + 8 * side * CGFloat(k), y: p.y + 38 - CGFloat(k) * 9), size: CGSize(width: 16, height: 16), color: SKColor(white: 0.15, alpha: 1), alpha: 0.75, blend: .alpha, z: 458, life: 1.0, rise: 16, grow: 2)
                }]))
            }
            run(.sequence([.wait(forDuration: 0.78), .run { [weak self] in self?.explosion(e.x + 0.4, e.y - 0.4, radius: 1.1, air: false, power: 70) }]))
            root.run(.sequence([.wait(forDuration: 1.0), .removeFromParent()]))
            return
        }
        if v.vehicle || v.heavy {
            // Wreck: the hull stays, scorched and burning, then fades.
            body.color = .black; body.colorBlendFactor = fac == .aliens ? 0.45 : 0.68
            body.run(.rotate(byAngle: -0.12 * side, duration: 0.25))
            if fac == .aliens { body.run(.scaleY(to: 0.55, duration: 0.8)) }
            let fireCol = fac == .machines ? SKColor(red: 0.4, green: 0.85, blue: 1, alpha: 1) : (fac == .aliens ? SKColor(red: 0.55, green: 1, blue: 0.3, alpha: 1) : SKColor(red: 1, green: 0.5, blue: 0.15, alpha: 1))
            let glow = SKSpriteNode(texture: bank.fx["glow"]); glow.blendMode = .add; glow.colorBlendFactor = 1; glow.color = fireCol
            glow.size = CGSize(width: body.size.width * 0.7, height: body.size.height * 0.5); glow.position = CGPoint(x: 0, y: body.size.height * 0.35); glow.zPosition = 0.5
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.1), .fadeAlpha(to: 0.9, duration: 0.14)])))
            root.addChild(glow)
            let smoke = SKAction.repeat(.sequence([.run { [weak self] in
                self?.puff("smoke", at: CGPoint(x: p.x, y: p.y + body.size.height * 0.5), size: CGSize(width: 14, height: 14), color: SKColor(white: fac == .aliens ? 0.35 : 0.12, alpha: 1),
                           alpha: 0.65, blend: .alpha, z: 458, life: 1.4, rise: 34, grow: 2.4, drift: 10)
            }, .wait(forDuration: 0.3)]), count: quality >= 1 ? 12 : 4)
            root.run(smoke)
            if v.heavy {
                run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in self?.explosion(e.x + 0.3, e.y + 0.2, radius: 1.0, air: false, power: 60) }]))
            }
            if fac == .aliens { decal(p, radius: 1.2, color: SKColor(red: 0.45, green: 0.85, blue: 0.25, alpha: 1), splat: true) }
            else { decal(p, radius: 1.1, color: SKColor(white: 0.04, alpha: 1), splat: false) }
            // The hulk stays on the field for a while (capped; oldest wrecks clear first). Flames die down first.
            glow.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 2), .removeFromParent()]))
            root.zPosition -= 0.05
            root.run(.sequence([.wait(forDuration: 4.0), .colorize(withColorBlendFactor: 0.75, duration: 0)]))
            body.run(.sequence([.wait(forDuration: 6), .fadeAlpha(to: 0.82, duration: 2)]))
            root.run(.sequence([.wait(forDuration: 28), .fadeOut(withDuration: 4), .removeFromParent()]))
            wrecks.removeAll { $0.parent == nil }
            wrecks.append(root)
            if wrecks.count > 36 { let old = wrecks.removeFirst(); old.removeAllActions(); old.run(.sequence([.fadeOut(withDuration: 1), .removeFromParent()])) }
            return
        }
        switch fac {
        case .humans:
            body.anchorPoint = CGPoint(x: 0.5, y: 0.12)
            body.run(.group([.rotate(byAngle: -1.4 * side, duration: 0.32), .sequence([.wait(forDuration: 1.6), .fadeOut(withDuration: 0.8)])]))
        case .machines:
            body.color = SKColor(white: 0.12, alpha: 1); body.colorBlendFactor = 0.6
            body.run(.group([.scaleY(to: 0.35, duration: 0.45), .sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.8)])]))
            for k in 0..<3 {
                run(.sequence([.wait(forDuration: Double(k) * 0.15), .run { [weak self] in
                    self?.puff("spark", at: CGPoint(x: p.x, y: p.y + 10), size: CGSize(width: 16, height: 16), color: SKColor(red: 0.5, green: 0.9, blue: 1, alpha: 1), z: 456, life: 0.2)
                }]))
            }
            decal(p, radius: 0.8, color: SKColor(white: 0.02, alpha: 1), splat: true)
        case .aliens:
            body.color = SKColor(red: 0.5, green: 1, blue: 0.3, alpha: 1); body.colorBlendFactor = 0.5
            body.run(.group([.scaleX(to: 1.3 * side, duration: 0.6), .scaleY(to: 0.25, duration: 0.6), .fadeOut(withDuration: 0.75)]))
            splash(CGPoint(x: p.x, y: p.y + 8), radius: 0.7, color: SKColor(red: 0.55, green: 0.95, blue: 0.3, alpha: 1))
            decal(p, radius: 1.0, color: SKColor(red: 0.45, green: 0.85, blue: 0.25, alpha: 1), splat: true)
        }
        root.run(.sequence([.wait(forDuration: 2.6), .removeFromParent()]))
    }

    // MARK: Selection overlays: target lines and weapon range

    func syncSelectionOverlays() {
        var n = 0
        let sel = ctl.selection.compactMap { world.entity($0) }
        for e in sel.prefix(40) where e.owner == ctl.me || ctl.spectating {
            guard let tg = world.entity(e.target), let va = views[e.id], let vb = views[tg.id] else { continue }
            let a = CGPoint(x: va.root.position.x, y: va.root.position.y + (e.isAir ? 38 : 10))
            let b = CGPoint(x: vb.root.position.x, y: vb.root.position.y + (tg.isAir ? 38 : 10))
            let l = line(n); n += 1
            l.position = a; l.size = CGSize(width: hypot(b.x - a.x, b.y - a.y), height: 2)
            l.zRotation = atan2(b.y - a.y, b.x - a.x)
            l.color = SKColor(red: 1, green: 0.35, blue: 0.3, alpha: 1); l.alpha = 0.45; l.isHidden = false
        }
        for i in n..<linePool.count { linePool[i].isHidden = true }
        // Weapon range ring for a single selected unit or tower.
        if sel.count == 1, let e = sel.first, let w = world.weapon(e), let v = views[e.id] {
            let r = CGFloat(w.range + (e.isBuilding ? Double(e.size) / 2 : e.radius))
            rangeRing.size = CGSize(width: r * 90, height: r * 45)
            rangeRing.position = v.root.position
            rangeRing.isHidden = false
        } else { rangeRing.isHidden = true }
    }

    func line(_ i: Int) -> SKSpriteNode {
        if i < linePool.count { return linePool[i] }
        let s = SKSpriteNode(texture: bank.fx["beam"])
        s.anchorPoint = CGPoint(x: 0, y: 0.5); s.colorBlendFactor = 1; s.zPosition = 470
        worldNode.addChild(s)
        linePool.append(s)
        return s
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
            case .machines: l.alpha = 0.55 + 0.4 * CGFloat(sin(t * (busy ? 6 : 2.5) + seed))
            case .aliens: l.alpha = 0.5 + 0.45 * CGFloat(sin(t * (busy ? 5 : 2) + seed + Double(k)))
            }
            // After dusk the lamps burn brighter and draw above the night.
            let pulse: CGFloat = fac == .machines ? 1 + 0.25 * CGFloat(sin(t * 3 + seed)) : 1
            l.setScale(pulse * (1 + night * 0.7))
            if night > 0.05 { liftLight(l, in: v, by: 1) } else { l.zPosition = 0.3 }
        }
        if e.complete {
            let warm = fac == .humans ? SKColor(red: 1, green: 0.74, blue: 0.42, alpha: 1) : (fac == .machines ? SKColor(red: 0.42, green: 0.88, blue: 1, alpha: 1) : SKColor(red: 0.58, green: 1, blue: 0.45, alpha: 1))
            lightPool(v, width: CGFloat(e.size) * 96, color: warm, strength: busy ? 0.6 : 0.46)
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
        animateParts(e, v, d, t, busy: busy)
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

extension SKColor {
    /// Linear blend toward another colour (t = 0…1).
    func blend(_ o: SKColor, _ t: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        #if os(iOS)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1); o.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #else
        let c1 = usingColorSpace(.sRGB) ?? self, c2 = o.usingColorSpace(.sRGB) ?? o
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        return SKColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
