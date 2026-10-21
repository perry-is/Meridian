import SpriteKit
import MeridianCore

/// Ambient life: flocks crossing the sky (with shadows sliding over the ground), fish rising in the water,
/// critters that scatter from troops, and dust devils on the plateau. Everything is spawned near the
/// camera, capped, and skipped when zoomed far out, at low quality, or in big stress battles.
final class Critter {
    let node: SKSpriteNode
    var x: Double, y: Double
    var fleeing = false
    var nextHop = 0.0
    init(node: SKSpriteNode, x: Double, y: Double) { self.node = node; self.x = x; self.y = y }
}

extension GameScene {

    var wildlifeOn: Bool { quality >= 1 && !ctl.stressMode && !(ctl.battleMode && world.entities.count > 260) }

    func buildWildlife() {
        let m = world.map
        for y in 0..<m.size { for x in 0..<m.size where m.terrainAt(x, y) == .water { waterTiles.append((x, y)) } }
    }

    func updateWildlife(_ dt: Double) {
        guard wildlifeOn else { return }
        let now = CACurrentMediaTime()
        // Flocks.
        if now > nextFlock {
            nextFlock = now + 22 + Double.random(in: 0...26)
            if zoom < 3 { spawnFlock() }
        }
        // Fish and ripples.
        if now > nextRipple, !waterTiles.isEmpty, zoom < 2.4 {
            nextRipple = now + 0.7 + Double.random(in: 0...1.2)
            for _ in 0..<6 {
                let (tx, ty) = waterTiles[Int.random(in: 0..<waterTiles.count)]
                let p = Iso.scene(Double(tx) + Double.random(in: 0.2...0.8), Double(ty) + Double.random(in: 0.2...0.8))
                guard onScreen(p), world.players[ctl.me].explored[world.tileIndex(Double(tx), Double(ty))] || ctl.spectating else { continue }
                ripple(p, fish: Double.random(in: 0...1) < 0.3 && night < 0.6)
                break
            }
        }
        // Dust devils on the plateau.
        if biome.ambient == .dust && now > nextDevil {
            nextDevil = now + 28 + Double.random(in: 0...30)
            if zoom < 2.6 { dustDevil() }
        }
        // A shooting star now and then on clear nights.
        if night > 0.6 && now > nextStar {
            nextStar = now + 14 + Double.random(in: 0...20)
            let a = CGPoint(x: CGFloat.random(in: -0.4...0.3) * size.width, y: CGFloat.random(in: 0.15...0.45) * size.height)
            let s = SKSpriteNode(texture: bank.fx["beam"], size: CGSize(width: 90, height: 3))
            s.anchorPoint = CGPoint(x: 1, y: 0.5); s.blendMode = .add; s.colorBlendFactor = 1
            s.color = SKColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
            s.position = a; s.zRotation = -0.45; s.alpha = 0; s.zPosition = 895
            cam.addChild(s)
            s.run(.sequence([.group([.moveBy(x: 260, y: -120, duration: 0.7), .sequence([.fadeAlpha(to: 0.9, duration: 0.1), .wait(forDuration: 0.35), .fadeOut(withDuration: 0.25)])]), .removeFromParent()]))
        }
        updateCritters(dt)
    }

    // MARK: Flocks

    func spawnFlock() {
        let night = self.night > 0.55
        if night && biome.ambient == .dust { return }
        let ray = biome.ambient == .dust
        let count = ray ? Int.random(in: 1...2) : Int.random(in: 4...8)
        let flock = SKNode()
        flock.zPosition = 595     // above units and effects, beneath the fog of war
        let shadows = SKNode()
        shadows.zPosition = 8
        let vw = size.width * zoom, vh = size.height * zoom
        let fromLeft = Bool.random()
        let start = CGPoint(x: cam.position.x + (fromLeft ? -1 : 1) * (vw * 0.6 + 60), y: cam.position.y + CGFloat.random(in: -vh * 0.35...vh * 0.35))
        let travel = CGVector(dx: (fromLeft ? 1 : -1) * (vw * 1.2 + 160), dy: CGFloat.random(in: -vh * 0.25...vh * 0.25))
        let dur = Double(hypot(travel.dx, travel.dy)) / (ray ? 45 : (night ? 140 : 95))
        let alt: CGFloat = ray ? 170 : 120
        for k in 0..<count {
            // V formation (or a loose pair of rays).
            let row = CGFloat((k + 1) / 2), side: CGFloat = k % 2 == 0 ? 1 : -1
            let off = CGPoint(x: -row * 22 * (fromLeft ? 1 : -1), y: side * row * 12 + CGFloat.random(in: -4...4))
            let b = SKSpriteNode(texture: ray ? bank.fx["skyray"] : bank.fx["bird0"])
            b.position = off
            b.xScale = fromLeft ? 1 : -1
            if ray {
                b.setScale(1.3); b.xScale = fromLeft ? 1.3 : -1.3
                b.run(.repeatForever(.sequence([.scaleY(to: 1.1, duration: 1.4), .scaleY(to: 1.35, duration: 1.4)])))
            } else {
                // Egrets over the delta; dark swifts over the meadows; bats after dusk.
                let tint: SKColor = night ? SKColor(red: 0.1, green: 0.08, blue: 0.12, alpha: 1) :
                    (biome.ambient == .mist ? SKColor(red: 0.95, green: 0.97, blue: 1, alpha: 1) : SKColor(red: 0.16, green: 0.14, blue: 0.16, alpha: 1))
                b.color = tint; b.colorBlendFactor = 1
                b.setScale(0.85); b.xScale = fromLeft ? 0.85 : -0.85
                let flap = SKAction.animate(with: [bank.fx["bird0"]!, bank.fx["bird1"]!], timePerFrame: night ? 0.07 : 0.14 + Double.random(in: 0...0.04))
                b.run(.repeatForever(flap))
                b.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.6 + Double(k) * 0.05), .moveBy(x: 0, y: -3, duration: 0.6)])))
            }
            flock.addChild(b)
            let sh = SKSpriteNode(texture: bank.fx["shadow"], size: CGSize(width: ray ? 46 : 14, height: ray ? 18 : 6))
            sh.alpha = ray ? 0.32 : 0.22
            sh.position = CGPoint(x: off.x, y: off.y - alt)
            shadows.addChild(sh)
        }
        flock.position = start; shadows.position = start
        worldNode.addChild(flock); worldNode.addChild(shadows)
        for n in [flock, shadows] {
            n.run(.sequence([.moveBy(x: travel.dx, y: travel.dy, duration: dur), .removeFromParent()]))
        }
    }

    // MARK: Water life

    func ripple(_ p: CGPoint, fish: Bool) {
        puff("shockwave", at: p, size: CGSize(width: 16, height: 8), color: SKColor(red: 0.85, green: 0.95, blue: 1, alpha: 1), alpha: 0.5, blend: .alpha, z: 3, life: 1.3, grow: 2.8)
        guard fish, let s = fx() else { return }
        // A small fish arcs out of the water and back in.
        s.texture = bank.fx["pixel"]; s.blendMode = .alpha
        s.size = CGSize(width: 6, height: 3); s.color = biome.waterGlow > 0 ? SKColor(red: 0.6, green: 1, blue: 0.9, alpha: 1) : SKColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1)
        s.position = p; s.zPosition = 6
        let dir: CGFloat = Bool.random() ? 1 : -1
        let up = SKAction.moveBy(x: dir * 7, y: 12, duration: 0.22); up.timingMode = .easeOut
        let down = SKAction.moveBy(x: dir * 7, y: -12, duration: 0.22); down.timingMode = .easeIn
        s.zRotation = dir * 0.6
        s.run(.sequence([.group([up, .rotate(toAngle: 0, duration: 0.22)]), .group([down, .rotate(toAngle: -dir * 0.7, duration: 0.22)]), .run { [weak self] in
            self?.puff("shockwave", at: CGPoint(x: p.x + dir * 14, y: p.y), size: CGSize(width: 10, height: 5), color: .white, alpha: 0.6, blend: .alpha, z: 3, life: 0.8, grow: 2.4)
        }]))
        s.run(recycle(s, after: 0.5))
    }

    // MARK: Dust devils

    func dustDevil() {
        let vw = size.width * zoom, vh = size.height * zoom
        let p = CGPoint(x: cam.position.x + CGFloat.random(in: -vw * 0.4...vw * 0.4), y: cam.position.y + CGFloat.random(in: -vh * 0.3...vh * 0.3))
        let (wx, wy) = Iso.world(p)
        guard world.map.inBounds(Int(wx), Int(wy)), world.players[ctl.me].explored[world.tileIndex(wx, wy)] || ctl.spectating else { return }
        let e = SKEmitterNode()
        e.particleTexture = bank.fx["smoke"]
        e.particleBirthRate = 26
        e.particleLifetime = 1.6
        e.particlePositionRange = CGVector(dx: 10, dy: 4)
        e.particleSpeed = 55; e.particleSpeedRange = 15
        e.emissionAngle = .pi / 2; e.emissionAngleRange = 0.5
        e.xAcceleration = CGFloat(biome.wind.x) * 14
        e.particleAlpha = 0.45; e.particleAlphaSpeed = -0.28
        e.particleScale = 0.25; e.particleScaleSpeed = 0.5
        e.particleRotationSpeed = 6
        e.particleColor = SKColor(red: 0.72, green: 0.52, blue: 0.36, alpha: 1); e.particleColorBlendFactor = 1
        e.particleBlendMode = .alpha
        e.zPosition = 120
        e.targetNode = worldNode
        e.position = p
        worldNode.addChild(e)
        let path = CGVector(dx: CGFloat(biome.wind.x) * 70 + CGFloat.random(in: -40...40), dy: CGFloat(biome.wind.y) * 40)
        e.run(.sequence([.group([.moveBy(x: path.dx, y: path.dy, duration: 7),
                                 .sequence([.wait(forDuration: 5.5), .run { e.particleBirthRate = 0 }])]),
                         .wait(forDuration: 1.8), .removeFromParent()]))
    }

    // MARK: Critters

    func updateCritters(_ dt: Double) {
        critterTimer -= dt
        guard critterTimer <= 0 else { return }
        critterTimer = 0.25
        let now = CACurrentMediaTime()
        // Retire critters that wandered off screen; keep a few near the camera on open ground.
        critters.removeAll { c in
            if c.node.parent == nil { return true }
            if !onScreen(c.node.position) && !c.fleeing { c.node.removeFromParent(); return true }
            return false
        }
        if critters.count < (zoom < 1.6 ? 6 : 3), night < 0.7 {
            let vw = size.width * zoom, vh = size.height * zoom
            let p = CGPoint(x: cam.position.x + CGFloat.random(in: -vw * 0.45...vw * 0.45), y: cam.position.y + CGFloat.random(in: -vh * 0.4...vh * 0.4))
            let (x, y) = Iso.world(p)
            let tx = Int(x), ty = Int(y)
            if world.map.inBounds(tx, ty), world.map.terrainAt(tx, ty) == .grass || world.map.terrainAt(tx, ty) == .moss,
               !world.nav.isBlocked(tx, ty), world.players[ctl.me].visible[world.tileIndex(x, y)] > 0 || ctl.spectating,
               !threatNear(x, y, 4) {
                let s = SKSpriteNode(texture: bank.fx["critter0"])
                s.color = critterTint; s.colorBlendFactor = 0.85
                s.position = p; s.zPosition = 100 + Iso.depth(x, y) * 0.4
                s.alpha = 0; s.run(.fadeIn(withDuration: 0.4))
                worldNode.addChild(s)
                critters.append(Critter(node: s, x: x, y: y))
            }
        }
        for c in critters where !c.fleeing {
            if threatNear(c.x, c.y, 2.6) {
                // Startled: dash away and vanish into the grass.
                c.fleeing = true
                let a = Double.random(in: 0...(2 * .pi))
                let to = Iso.scene(c.x + cos(a) * 3, c.y + sin(a) * 3)
                c.node.removeAllActions()
                c.node.xScale = to.x < c.node.position.x ? -1 : 1
                c.node.run(.repeatForever(.animate(with: [bank.fx["critter0"]!, bank.fx["critter1"]!], timePerFrame: 0.06)))
                c.node.run(.sequence([.group([.move(to: to, duration: 0.6), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)])]), .removeFromParent()]))
            } else if now > c.nextHop {
                c.nextHop = now + Double.random(in: 1.2...4)
                let a = Double.random(in: 0...(2 * .pi))
                let nx = c.x + cos(a) * 0.5, ny = c.y + sin(a) * 0.5
                guard world.map.inBounds(Int(nx), Int(ny)), !world.nav.isBlocked(Int(nx), Int(ny)) else { continue }
                c.x = nx; c.y = ny
                let to = Iso.scene(nx, ny)
                c.node.xScale = to.x < c.node.position.x ? -1 : 1
                let hop = SKAction.sequence([.setTexture(bank.fx["critter1"]!), .group([.move(to: to, duration: 0.22), .sequence([.moveBy(x: 0, y: 4, duration: 0.11), .moveBy(x: 0, y: -4, duration: 0.11)])]), .setTexture(bank.fx["critter0"]!)])
                c.node.run(hop)
                c.node.zPosition = 100 + Iso.depth(nx, ny) * 0.4
            }
        }
    }

    var critterTint: SKColor {
        switch biome.ambient {
        case .pollen: return SKColor(red: 0.62, green: 0.48, blue: 0.34, alpha: 1)
        case .mist: return SKColor(red: 0.35, green: 0.62, blue: 0.4, alpha: 1)
        case .dust: return SKColor(red: 0.78, green: 0.45, blue: 0.3, alpha: 1)
        }
    }

    func threatNear(_ x: Double, _ y: Double, _ r: Double) -> Bool {
        for e in world.entities where e.alive && e.isUnit && !e.isAir && e.onMap && abs(e.x - x) < r && abs(e.y - y) < r { return true }
        return false
    }
}
