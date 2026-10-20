import SpriteKit
import MeridianCore

/// Visual node for one simulation entity.
final class EntityView {
    let root = SKNode()
    let body: SKSpriteNode
    let shadow: SKSpriteNode?
    var ring: SKSpriteNode?
    var facingSign: CGFloat = 1
    var lastHP: Double = 0
    var baseScale: CGFloat = 1

    init(body: SKSpriteNode, shadow: SKSpriteNode?) {
        self.body = body
        self.shadow = shadow
        if let s = shadow { root.addChild(s) }
        root.addChild(body)
    }
}

final class GameScene: SKScene {
    let ctl: GameController
    let bank: TextureBank
    var world: World { ctl.world }
    let worldNode = SKNode()
    let cam = SKCameraNode()
    let barLayer = SKNode()
    let fxLayer = SKNode()
    var views: [Int: EntityView] = [:]
    var projPool: [SKSpriteNode] = []
    var fxPool: [SKSpriteNode] = []
    var beamPool: [SKSpriteNode] = []
    var barPool: [(SKSpriteNode, SKSpriteNode)] = []
    var siteViews: [(platform: SKSpriteNode, beacon: SKSpriteNode, pips: [SKSpriteNode])] = []
    var fogNode: SKSpriteNode!
    var fogShader: SKShader!
    var ghost: SKSpriteNode!
    var ghostTiles = SKNode()
    var boxNode: SKShapeNode!
    var rallyFlag: SKSpriteNode!
    var lastUpdate: TimeInterval = 0
    var zoom: CGFloat = 1.8
    var fogTimer = 0.0
    var fxBudget = 0
    var boxStart: CGPoint?
    var hotspot: [(Double, Double)] = []
    var spectateTimer = 0.0
    var perfFrames: [Double] = []
    let N: Int

    init(controller: GameController, size: CGSize) {
        ctl = controller
        N = controller.world.map.size
        bank = TextureBank.make(data: controller.data, factions: controller.world.players.map { $0.faction })
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }
        addChild(worldNode)
        addChild(cam)
        camera = cam
        worldNode.addChild(barLayer); barLayer.zPosition = 500
        worldNode.addChild(fxLayer); fxLayer.zPosition = 0
        buildTerrain()
        buildSites()
        buildFog()
        ghost = SKSpriteNode()
        ghost.alpha = 0.6; ghost.zPosition = 620; ghost.isHidden = true
        worldNode.addChild(ghost)
        ghostTiles.zPosition = 619; worldNode.addChild(ghostTiles)
        boxNode = SKShapeNode()
        boxNode.strokeColor = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 0.9)
        boxNode.fillColor = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 0.12)
        boxNode.lineWidth = 1.5; boxNode.zPosition = 1000; boxNode.isHidden = true
        cam.addChild(boxNode)
        rallyFlag = SKSpriteNode(texture: bank.fx["ring"], size: CGSize(width: 40, height: 20))
        rallyFlag.color = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1); rallyFlag.colorBlendFactor = 1
        rallyFlag.zPosition = 5; rallyFlag.isHidden = true
        worldNode.addChild(rallyFlag)
        if ctl.stressMode { focus(Double(N) / 2, Double(N) / 2); zoom = 2.6 }
        else if let hq = world.buildings(of: ctl.me).first { focus(hq.x + 3, hq.y - 3) }
        ctl.focusCamera = { [weak self] x, y in self?.focus(x, y) }
        ctl.cameraWorldRect = { [weak self] in self?.visibleWorldQuad() ?? [] }
        applyZoom()
        setupInput(view)
    }

    // MARK: Static layers

    func buildTerrain() {
        let tm = SKTileMapNode(tileSet: bank.tileSet, columns: N, rows: N, tileSize: CGSize(width: 64, height: 32))
        let map = world.map
        for r in 0..<N {
            for c in 0..<N {
                let t = map.terrainAt(c, r)
                let g = bank.group(t, elevated: map.elevation[map.idx(c, r)] > 0)
                let defs = g.rules[0].tileDefinitions
                let v = Int(hnoise(c, r, 77) * CGFloat(defs.count)) % defs.count
                tm.setTileGroup(g, andTileDefinition: defs[v], forColumn: c, row: r)
            }
        }
        let c00 = tm.centerOfTile(atColumn: 0, row: 0)
        let want = Iso.scene(0.5, 0.5)
        tm.position = CGPoint(x: want.x - c00.x, y: want.y - c00.y)
        tm.zPosition = 0
        worldNode.addChild(tm)
        // Boulders on rock tiles give cliffs real height.
        for r in 0..<N {
            for c in 0..<N where map.terrainAt(c, r) == .rock {
                if hnoise(c, r, 5) < 0.25 { continue }
                let s = SKSpriteNode(texture: bank.boulders[Int(hnoise(c, r, 6) * 3) % 3])
                s.anchorPoint = CGPoint(x: 0.5, y: 0.22)
                s.position = Iso.scene(Double(c) + 0.5, Double(r) + 0.5)
                s.setScale(0.55 + hnoise(c, r, 8) * 0.3)
                s.zPosition = 100 + Iso.depth(Double(c) + 0.5, Double(r) + 0.5) * 0.4
                worldNode.addChild(s)
            }
        }
    }

    func buildSites() {
        for s in world.sites {
            let plat = SKSpriteNode(texture: bank.sitePlatform)
            plat.size = CGSize(width: 272, height: 136)   // capture radius (3 tiles) in iso space
            plat.position = Iso.scene(s.x, s.y)
            plat.zPosition = 2
            plat.colorBlendFactor = 0.7
            worldNode.addChild(plat)
            let b = SKSpriteNode(texture: bank.siteBeacon)
            b.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            b.position = plat.position
            b.zPosition = 100 + Iso.depth(s.x, s.y) * 0.4
            b.colorBlendFactor = 0.6
            worldNode.addChild(b)
            var pips: [SKSpriteNode] = []
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                let p = SKSpriteNode(texture: bank.fx["orb"], size: CGSize(width: 9, height: 9))
                p.position = Iso.scene(s.x + cos(a) * 2.2, s.y + sin(a) * 2.2)
                p.zPosition = 3
                p.colorBlendFactor = 1
                worldNode.addChild(p)
                pips.append(p)
            }
            siteViews.append((plat, b, pips))
        }
    }

    func buildFog() {
        let w = CGFloat(N) * 64, h = CGFloat(N) * 32
        fogNode = SKSpriteNode(color: .black, size: CGSize(width: w + 2000, height: h + 2000))
        fogNode.position = CGPoint(x: w / 2, y: 0)
        fogNode.zPosition = 600
        let src = """
        void main() {
            vec2 p = u_origin + v_tex_coord * u_size;
            float wx = (p.x / 32.0 - p.y / 16.0) * 0.5;
            float wy = (p.x / 32.0 + p.y / 16.0) * 0.5;
            vec2 uv = vec2(wx / u_n, wy / u_n);
            float a = 1.0;
            if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
                vec4 f = texture2D(u_fog, uv);
                a = mix(0.96, 0.5, f.g);
                a = mix(a, 0.0, f.r);
            }
            gl_FragColor = vec4(0.015, 0.02, 0.035, 1.0) * a;
        }
        """
        fogShader = SKShader(source: src)
        fogShader.uniforms = [
            SKUniform(name: "u_origin", vectorFloat2: vector_float2(Float(w / 2 - (w + 2000) / 2), Float(-(h + 2000) / 2))),
            SKUniform(name: "u_size", vectorFloat2: vector_float2(Float(w + 2000), Float(h + 2000))),
            SKUniform(name: "u_n", float: Float(N)),
            SKUniform(name: "u_fog", texture: fogTexture()),
        ]
        fogNode.shader = fogShader
        worldNode.addChild(fogNode)
    }

    func fogTexture() -> SKTexture {
        let p = world.players[ctl.me]
        var bytes = [UInt8](repeating: 0, count: N * N * 4)
        for i in 0..<(N * N) {
            bytes[i * 4] = p.visible[i] > 0 ? 255 : 0
            bytes[i * 4 + 1] = p.explored[i] ? 255 : 0
            bytes[i * 4 + 3] = 255
        }
        let t = SKTexture(data: Data(bytes), size: CGSize(width: N, height: N), flipped: false)
        t.filteringMode = .linear
        return t
    }

    // MARK: Frame update

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : currentTime - lastUpdate
        lastUpdate = currentTime
        if ctl.stressMode { perfLog(dt) }
        ctl.advance(dt)
        fxBudget = 50
        consumeEvents()
        syncEntities()
        syncProjectiles()
        syncSites()
        syncGhost()
        fogTimer -= dt
        if fogTimer <= 0 {
            fogTimer = 0.2
            fogShader.uniformNamed("u_fog")?.textureValue = fogTexture()
            ctl.minimapVersion &+= 1
        }
    }

    /// Frame-time log for stress runs (printed to stdout; read with `simctl launch --console`).
    func perfLog(_ dt: Double) {
        perfFrames.append(dt)
        if perfFrames.count >= 300 {
            let s = perfFrames.sorted()
            let avg = perfFrames.reduce(0, +) / Double(perfFrames.count)
            let units = world.entities.filter { $0.isUnit && $0.alive && !$0.isMine }.count
            print(String(format: "PERF units=%d nodes=%d avgFrame=%.2fms fps=%.1f p95=%.2fms projectiles=%d", units, worldNode.children.count, avg * 1000, 1 / avg, s[Int(Double(s.count) * 0.95)] * 1000, world.projectiles.count))
            perfFrames.removeAll()
        }
    }

    func position(_ e: Entity, _ a: Double) -> (Double, Double) {
        guard e.isUnit else { return (e.x, e.y) }
        let k = min(1, max(0, a))
        return (e.px + (e.x - e.px) * k, e.py + (e.y - e.py) * k)
    }

    func makeView(_ e: Entity) -> EntityView {
        let owner = max(0, e.owner)
        switch e.kind {
        case .unit:
            if e.isMine {
                let s = SKSpriteNode(texture: bank.fx["orb"], size: CGSize(width: 10, height: 10))
                s.color = TeamColor.sk(e.owner); s.colorBlendFactor = 0.8; s.alpha = 0.7
                return EntityView(body: s, shadow: nil)
            }
            let d = world.udef(e)
            let tex = bank.unit[owner][e.type]
            let s = SKSpriteNode(texture: tex)
            let sz = UnitArt.canvasSize(d)
            s.size = CGSize(width: sz, height: sz)
            let sh = SKSpriteNode(texture: bank.fx["shadow"], size: CGSize(width: sz * 0.8, height: sz * 0.4))
            if e.isAir {
                s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                s.position = CGPoint(x: 0, y: 34)
                sh.alpha = 0.6
            } else {
                s.anchorPoint = CGPoint(x: 0.5, y: 0.12)
                sh.position = CGPoint(x: 0, y: 2)
            }
            return EntityView(body: s, shadow: sh)
        case .building:
            let d = world.bdef(e)
            let c = WorldArt.buildingCanvas(d)
            let s = SKSpriteNode(texture: bank.building[owner][e.type], size: CGSize(width: c.w, height: c.h))
            s.anchorPoint = CGPoint(x: 0.5, y: c.anchorY)
            return EntityView(body: s, shadow: nil)
        case .resource:
            let k = ResourceKind(rawValue: e.type)!
            let v = e.id % 3
            let s = SKSpriteNode(texture: bank.resource[k.rawValue][v])
            s.anchorPoint = CGPoint(x: 0.5, y: k == .wood ? 0.1 : 0.25)
            if k == .wood { s.setScale(0.85 + CGFloat(e.id % 5) * 0.06) }
            return EntityView(body: s, shadow: nil)
        }
    }

    func syncEntities() {
        let a = ctl.interpolation
        let t = world.time
        var seen = Set<Int>()
        seen.reserveCapacity(world.entities.count)
        let selected = Set(ctl.selection)
        var bars = 0
        for e in world.entities where e.alive {
            let v: EntityView
            if let ex = views[e.id] { v = ex } else {
                v = makeView(e)
                views[e.id] = v
                worldNode.addChild(v.root)
            }
            seen.insert(e.id)
            let shown = e.onMap && ctl.isShown(e) && !(e.isMine && e.owner != ctl.me && !world.canSee(ctl.me, e))
            v.root.isHidden = !shown
            if !shown { continue }
            let (x, y) = position(e, a)
            v.root.position = Iso.scene(x, y)
            let depth = Iso.depth(x, y)
            v.root.zPosition = (e.isAir ? 300 : 100) + depth * 0.4 + (e.isBuilding ? -0.2 : 0)
            if e.isUnit && !e.isMine {
                // Facing: flip when heading screen-left.
                let sx = cos(e.facing) + sin(e.facing)
                if abs(sx) > 0.15 { v.facingSign = sx < 0 ? -1 : 1 }
                v.body.xScale = v.facingSign * abs(v.body.xScale)
                if e.isAir {
                    v.body.position.y = 34 + CGFloat(sin(t * 2.4 + Double(e.id))) * 2
                } else if e.moving {
                    v.body.position.y = CGFloat(abs(sin(t * 11 + Double(e.id)))) * 1.4
                } else { v.body.position.y = 0 }
                // Cloaked own units shimmer; recoil flash on fire.
                v.body.alpha = world.isCloaked(e) ? 0.45 : 1
                if t - e.lastFireTime < 0.09 && world.weapon(e) != nil {
                    v.body.colorBlendFactor = 0.35; v.body.color = .white
                } else if t - e.lastHitTime < 0.08 {
                    v.body.colorBlendFactor = 0.45; v.body.color = SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 1)
                } else { v.body.colorBlendFactor = 0 }
            } else if e.isBuilding {
                v.body.alpha = e.complete ? 1 : 0.45 + 0.4 * CGFloat(e.buildProgress)
                if t - e.lastHitTime < 0.08 { v.body.colorBlendFactor = 0.3; v.body.color = SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 1) }
                else if e.disruptedUntil > t { v.body.colorBlendFactor = 0.4; v.body.color = SKColor(red: 0.4, green: 0.6, blue: 1, alpha: 1) }
                else { v.body.colorBlendFactor = 0 }
            } else if e.isResource {
                let k = ResourceKind(rawValue: e.type)!
                let full = Double(k == .iron ? world.data.rules.economy.ironNodeAmount : (k == .gold ? world.data.rules.economy.goldNodeAmount : world.data.rules.economy.treeAmount))
                if k != .wood { v.body.setScale(CGFloat(0.65 + 0.35 * min(1, Double(e.amount) / full))) }
            }
            // Selection ring.
            let isSel = selected.contains(e.id)
            if isSel {
                if v.ring == nil {
                    let r = SKSpriteNode(texture: bank.fx["ring"])
                    let rad: CGFloat = e.isBuilding ? CGFloat(e.size) * 36 : CGFloat(max(0.35, e.radius)) * 110
                    r.size = CGSize(width: rad, height: rad / 2)
                    r.colorBlendFactor = 1
                    r.zPosition = -0.05
                    v.root.addChild(r)
                    v.ring = r
                }
                v.ring!.color = e.owner == ctl.me ? SKColor(red: 0.35, green: 1, blue: 0.45, alpha: 1) : (e.owner < 0 ? .yellow : SKColor(red: 1, green: 0.3, blue: 0.25, alpha: 1))
                v.ring!.isHidden = false
            } else { v.ring?.isHidden = true }
            // Health / progress bars for damaged, selected or constructing things.
            if !e.isResource && !e.isMine && (isSel || e.hp < e.maxHp - 0.5 || (e.isBuilding && !e.complete)) {
                let bar = bar(bars); bars += 1
                let w: CGFloat = e.isBuilding ? CGFloat(e.size) * 22 : 26
                let top: CGFloat = e.isBuilding ? CGFloat(WorldArt.buildingCanvas(world.bdef(e)).h) * (1 - WorldArt.buildingCanvas(world.bdef(e)).anchorY) - 10 :
                    (e.isAir ? 34 + v.body.size.height * 0.45 : v.body.size.height * 0.88)
                bar.0.position = CGPoint(x: v.root.position.x, y: v.root.position.y + top)
                bar.0.size = CGSize(width: w + 2, height: 5)
                let frac = CGFloat(e.isBuilding && !e.complete ? e.buildProgress : e.hp / max(1, e.maxHp))
                bar.1.size = CGSize(width: max(0.5, w * frac), height: 3)
                bar.1.position = CGPoint(x: bar.0.position.x - w / 2, y: bar.0.position.y)
                bar.1.color = e.isBuilding && !e.complete ? SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1) :
                    (e.owner == ctl.me ? (frac > 0.5 ? SKColor(red: 0.3, green: 0.95, blue: 0.4, alpha: 1) : (frac > 0.25 ? .yellow : .red)) : TeamColor.sk(e.owner))
                bar.0.isHidden = false; bar.1.isHidden = false
            }
        }
        for i in bars..<barPool.count { barPool[i].0.isHidden = true; barPool[i].1.isHidden = true }
        // Remove views for dead entities.
        if seen.count != views.count {
            for (id, v) in views where !seen.contains(id) {
                v.root.removeFromParent()
                views.removeValue(forKey: id)
            }
        }
        // Rally flag for selected production building.
        if ctl.selection.count == 1, let b = world.entity(ctl.selection[0]), b.isBuilding, b.owner == ctl.me, b.hasRally {
            rallyFlag.isHidden = false
            rallyFlag.position = Iso.scene(b.rallyX, b.rallyY)
        } else { rallyFlag.isHidden = true }
    }

    func bar(_ i: Int) -> (SKSpriteNode, SKSpriteNode) {
        if i < barPool.count { return barPool[i] }
        let bg = SKSpriteNode(texture: bank.fx["pixel"], color: SKColor(white: 0, alpha: 0.75), size: CGSize(width: 10, height: 5))
        bg.colorBlendFactor = 1
        let fg = SKSpriteNode(texture: bank.fx["pixel"], color: .green, size: CGSize(width: 10, height: 3))
        fg.colorBlendFactor = 1
        fg.anchorPoint = CGPoint(x: 0, y: 0.5)
        fg.zPosition = 0.01
        barLayer.addChild(bg); barLayer.addChild(fg)
        barPool.append((bg, fg))
        return (bg, fg)
    }

    // MARK: Projectiles & effects

    static func styleColor(_ s: String) -> SKColor {
        switch s {
        case "bullet": return SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        case "rocket", "missile": return SKColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        case "shell", "bomb": return SKColor(red: 1, green: 0.6, blue: 0.25, alpha: 1)
        case "arc", "pulse", "rail", "beam": return SKColor(red: 0.45, green: 0.95, blue: 1, alpha: 1)
        case "flak": return SKColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        case "quake": return SKColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        case "acid", "spine": return SKColor(red: 0.6, green: 1, blue: 0.3, alpha: 1)
        case "spore": return SKColor(red: 0.85, green: 0.5, blue: 1, alpha: 1)
        case "claw": return SKColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        case "mine": return SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        default: return .white
        }
    }

    func syncProjectiles() {
        let ps = world.projectiles
        while projPool.count < ps.count {
            let s = SKSpriteNode(texture: bank.fx["bolt"])
            s.colorBlendFactor = 1
            s.zPosition = 400
            worldNode.addChild(s)
            projPool.append(s)
        }
        for (i, p) in ps.enumerated() {
            let s = projPool[i]
            s.isHidden = !(world.players[ctl.me].visible[world.tileIndex(p.x, p.y)] > 0)
            let pos = Iso.scene(p.x, p.y)
            let total = max(0.05, p.total)
            let t = min(1, p.age / total)
            // Altitude: from shooter height to target height, plus an arc for artillery.
            let srcAlt: CGFloat = 14
            let dstAlt: CGFloat = p.targetAir ? 34 : 8
            var alt = srcAlt + (dstAlt - srcAlt) * CGFloat(t)
            let arcing = ["shell", "acid", "spore", "bomb"].contains(p.style)
            if arcing { alt += CGFloat(sin(t * .pi)) * CGFloat(min(90, total * 40)) }
            s.position = CGPoint(x: pos.x, y: pos.y + alt)
            let dx = Iso.scene(p.tx, p.ty).x - Iso.scene(p.sx, p.sy).x, dy = Iso.scene(p.tx, p.ty).y - Iso.scene(p.sx, p.sy).y
            s.zRotation = atan2(dy, dx)
            switch p.style {
            case "shell", "bomb": s.texture = bank.fx["shell"]; s.size = CGSize(width: 7, height: 7)
            case "acid", "spore", "flak", "pulse": s.texture = bank.fx["orb"]; s.size = CGSize(width: 10, height: 10)
            case "rocket", "missile": s.texture = bank.fx["bolt"]; s.size = CGSize(width: 12, height: 4)
            default: s.texture = bank.fx["bolt"]; s.size = CGSize(width: 9, height: 3)
            }
            s.color = GameScene.styleColor(p.style)
        }
        for i in ps.count..<projPool.count { projPool[i].isHidden = true }
    }

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
        if s.parent == nil { worldNode.addChild(s) }
        return s
    }

    func recycle(_ s: SKSpriteNode, after d: TimeInterval) -> SKAction {
        .sequence([.wait(forDuration: d), .run { [weak self, weak s] in
            guard let s = s else { return }
            s.removeFromParent(); s.isHidden = false
            if (self?.fxPool.count ?? 99) < 300 { self?.fxPool.append(s) }
        }])
    }

    func visibleToMe(_ x: Double, _ y: Double) -> Bool { ctl.spectating || world.players[ctl.me].visible[world.tileIndex(x, y)] > 0 }

    func consumeEvents() {
        for ev in world.events {
            switch ev {
            case .shot(_, let fx0, let fy0, let tx, let ty, let style, _, let air):
                guard visibleToMe(fx0, fy0) || visibleToMe(tx, ty) else { continue }
                if ["arc", "rail", "beam"].contains(style) { beam(fx0, fy0, tx, ty, style, air) }
                if style == "claw" { slash(tx, ty, air) }
                else { muzzle(fx0, fy0, style) }
            case .impact(let x, let y, let r, let style, let air):
                if ctl.spectating { hotspot.append((x, y)) }
                guard visibleToMe(x, y) else { continue }
                explosion(x, y, radius: r, color: GameScene.styleColor(style), air: air, big: false)
            case .death(let x, let y, let big, _, let air, let building):
                guard visibleToMe(x, y) else { continue }
                explosion(x, y, radius: building ? 2.5 : (big ? 1.6 : 0.7), color: SKColor(red: 1, green: 0.6, blue: 0.25, alpha: 1), air: air, big: true)
            case .heal(let x, let y):
                guard visibleToMe(x, y), let s = fx() else { continue }
                s.texture = bank.fx["spark"]; s.size = CGSize(width: 14, height: 14)
                s.color = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1)
                let p = Iso.scene(x, y); s.position = CGPoint(x: p.x, y: p.y + 20); s.zPosition = 450
                s.run(.group([.moveBy(x: 0, y: 14, duration: 0.6), .fadeOut(withDuration: 0.6)]))
                s.run(recycle(s, after: 0.62))
            case .emp(let x, let y, let r):
                guard let s = fx() else { continue }
                s.texture = bank.fx["ring"]; s.size = CGSize(width: 20, height: 10)
                s.color = SKColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)
                s.position = Iso.scene(x, y); s.zPosition = 450
                s.run(.group([.scale(to: CGFloat(r) * 6.4, duration: 0.4), .fadeOut(withDuration: 0.5)]))
                s.run(recycle(s, after: 0.52))
            default: break
            }
        }
        world.events.removeAll(keepingCapacity: true)
        // Spectator camera drifts toward the densest fighting.
        if ctl.spectating {
            spectateTimer -= 1.0 / 60
            if spectateTimer <= 0 && !hotspot.isEmpty {
                spectateTimer = 3
                let hx = hotspot.reduce(0) { $0 + $1.0 } / Double(hotspot.count), hy = hotspot.reduce(0) { $0 + $1.1 } / Double(hotspot.count)
                cam.run(.move(to: Iso.scene(hx, hy), duration: 1.0))
                hotspot.removeAll()
            }
        }
        // Command feedback ping.
        if let cp = ctl.commandPing {
            ctl.commandPing = nil
            if let s = fx() {
                s.texture = bank.fx["ring"]; s.size = CGSize(width: 46, height: 23); s.blendMode = .alpha
                s.color = cp.2 ? SKColor(red: 1, green: 0.3, blue: 0.25, alpha: 1) : SKColor(red: 0.35, green: 1, blue: 0.45, alpha: 1)
                s.position = Iso.scene(cp.0, cp.1); s.zPosition = 5
                s.run(.group([.scale(to: 0.3, duration: 0.45), .fadeOut(withDuration: 0.45)]))
                s.run(recycle(s, after: 0.47))
            }
        }
        // Persistent cloud visuals.
        for c in world.clouds where visibleToMe(c.x, c.y) && world.tick % 6 == 0 {
            guard let s = fx() else { break }
            s.texture = bank.fx["smoke"]; s.blendMode = .alpha
            s.size = CGSize(width: CGFloat(c.radius) * 60, height: CGFloat(c.radius) * 30)
            s.color = c.slow < 1 ? SKColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1) : SKColor(red: 0.55, green: 0.95, blue: 0.3, alpha: 1)
            s.alpha = 0.5
            let p = Iso.scene(c.x + Double(world.rng.state % 7) * 0.05, c.y); s.position = CGPoint(x: p.x, y: p.y + 6); s.zPosition = 90
            s.run(.group([.fadeOut(withDuration: 0.6), .scale(by: 1.2, duration: 0.6)]))
            s.run(recycle(s, after: 0.62))
        }
    }

    func muzzle(_ x: Double, _ y: Double, _ style: String) {
        guard let s = fx() else { return }
        s.texture = bank.fx["glow"]; s.size = CGSize(width: 14, height: 14)
        s.color = GameScene.styleColor(style)
        let p = Iso.scene(x, y); s.position = CGPoint(x: p.x, y: p.y + 14); s.zPosition = 450
        s.run(.fadeOut(withDuration: 0.08)); s.run(recycle(s, after: 0.09))
    }

    func slash(_ x: Double, _ y: Double, _ air: Bool) {
        guard let s = fx() else { return }
        s.texture = bank.fx["spark"]; s.size = CGSize(width: 18, height: 18)
        s.color = GameScene.styleColor("claw")
        let p = Iso.scene(x, y); s.position = CGPoint(x: p.x, y: p.y + (air ? 34 : 12)); s.zPosition = 450
        s.zRotation = CGFloat(world.tick % 4) * 0.4
        s.run(.group([.fadeOut(withDuration: 0.15), .scale(to: 1.4, duration: 0.15)])); s.run(recycle(s, after: 0.16))
    }

    func beam(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ style: String, _ air: Bool) {
        guard let s = fx() else { return }
        let a = Iso.scene(x0, y0), b = Iso.scene(x1, y1)
        let pa = CGPoint(x: a.x, y: a.y + 16), pb = CGPoint(x: b.x, y: b.y + (air ? 34 : 10))
        let len = hypot(pb.x - pa.x, pb.y - pa.y)
        s.texture = bank.fx["beam"]
        s.anchorPoint = CGPoint(x: 0, y: 0.5)
        s.size = CGSize(width: len, height: style == "rail" ? 5 : 4)
        s.position = pa; s.zRotation = atan2(pb.y - pa.y, pb.x - pa.x)
        s.color = GameScene.styleColor(style); s.zPosition = 455
        s.run(.fadeOut(withDuration: style == "rail" ? 0.25 : 0.12)); s.run(recycle(s, after: 0.26))
    }

    func explosion(_ x: Double, _ y: Double, radius: Double, color: SKColor, air: Bool, big: Bool) {
        let p = Iso.scene(x, y)
        let base = CGPoint(x: p.x, y: p.y + (air ? 34 : 6))
        let r = CGFloat(max(0.4, radius))
        if let s = fx() {
            s.texture = bank.fx["glow"]; s.size = CGSize(width: 40 * r, height: 30 * r)
            s.color = color; s.position = base; s.zPosition = 460
            s.setScale(0.4)
            s.run(.group([.scale(to: 1.2, duration: 0.22), .fadeOut(withDuration: 0.3)])); s.run(recycle(s, after: 0.32))
        }
        guard big || radius > 0.9 else { return }
        if let s = fx() {
            s.texture = bank.fx["smoke"]; s.blendMode = .alpha; s.size = CGSize(width: 36 * r, height: 36 * r)
            s.color = SKColor(white: 0.25, alpha: 1); s.alpha = 0.7
            s.position = CGPoint(x: base.x, y: base.y + 6); s.zPosition = 458
            s.run(.group([.moveBy(x: 0, y: 22, duration: 1.0), .fadeOut(withDuration: 1.0), .scale(by: 1.5, duration: 1.0)])); s.run(recycle(s, after: 1.02))
        }
        for k in 0..<(big ? 4 : 2) {
            guard let s = fx() else { break }
            s.texture = bank.fx["spark"]; s.size = CGSize(width: 10, height: 10)
            s.color = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
            s.position = base; s.zPosition = 461
            let a = Double(k) * 1.7 + x
            s.run(.group([.moveBy(x: CGFloat(cos(a)) * 30 * r, y: CGFloat(sin(a)) * 20 * r + 10, duration: 0.35), .fadeOut(withDuration: 0.35)]))
            s.run(recycle(s, after: 0.37))
        }
        if !air && radius > 1.2, let s = fx() {
            s.texture = bank.fx["scorch"]; s.blendMode = .alpha; s.size = CGSize(width: 46 * r, height: 23 * r)
            s.color = .black; s.alpha = 0.8; s.position = p; s.zPosition = 4
            s.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 2)])); s.run(recycle(s, after: 6.1))
        }
    }

    // MARK: Sites, ghost

    func syncSites() {
        for (i, s) in world.sites.enumerated() {
            let v = siteViews[i]
            let col = s.owner >= 0 ? TeamColor.sk(s.owner) : SKColor(white: 0.85, alpha: 1)
            v.platform.color = col; v.beacon.color = col
            let who = s.owner >= 0 ? s.owner : s.capturer
            let lit = Int((s.control * 16).rounded(.down))
            for (k, pip) in v.pips.enumerated() {
                pip.color = k < lit && who >= 0 ? TeamColor.sk(who) : SKColor(white: 0.2, alpha: 1)
                pip.alpha = s.contested ? (world.tick % 10 < 5 ? 1 : 0.4) : 1
            }
            v.platform.alpha = ctl.selectedSite == i ? 1 : 0.85
        }
    }

    func syncGhost() {
        guard case .place(let t) = ctl.mode, let g = ctl.ghostTile else { ghost.isHidden = true; ghostTiles.isHidden = true; return }
        let d = world.data.buildings[t]
        let c = WorldArt.buildingCanvas(d)
        ghost.texture = bank.building[ctl.me][t]
        ghost.size = CGSize(width: c.w, height: c.h)
        ghost.anchorPoint = CGPoint(x: 0.5, y: c.anchorY)
        let s = Double(d.size)
        ghost.position = Iso.scene(Double(g.0) + s / 2, Double(g.1) + s / 2)
        ghost.isHidden = false
        let ok = ctl.hud.placementValid
        ghost.color = ok ? .green : .red
        ghost.colorBlendFactor = 0.35
        ghostTiles.isHidden = false
        ghostTiles.removeAllChildren()
        for yy in g.1..<(g.1 + d.size) {
            for xx in g.0..<(g.0 + d.size) {
                let blocked = world.nav.isBlocked(xx, yy)
                let tsp = SKSpriteNode(texture: bank.fx["ring"], size: CGSize(width: 58, height: 29))
                tsp.color = blocked ? .red : .green; tsp.colorBlendFactor = 1; tsp.alpha = 0.8
                tsp.position = Iso.scene(Double(xx) + 0.5, Double(yy) + 0.5)
                ghostTiles.addChild(tsp)
            }
        }
    }

    // MARK: Camera

    func focus(_ x: Double, _ y: Double) {
        cam.position = Iso.scene(x, y)
        clampCamera()
    }

    func applyZoom() {
        zoom = min(4.5, max(0.7, zoom))
        cam.setScale(zoom)
        clampCamera()
    }

    func clampCamera() {
        let w = CGFloat(N) * 64, h = CGFloat(N) * 32
        cam.position.x = min(w, max(0, cam.position.x))
        cam.position.y = min(h / 2, max(-h / 2, cam.position.y))
    }

    func visibleWorldQuad() -> [(Double, Double)] {
        let hw = size.width / 2 * zoom, hh = size.height / 2 * zoom
        let c = cam.position
        return [CGPoint(x: c.x - hw, y: c.y - hh), CGPoint(x: c.x + hw, y: c.y - hh), CGPoint(x: c.x + hw, y: c.y + hh), CGPoint(x: c.x - hw, y: c.y + hh)].map { Iso.world($0) }
    }

    func worldPoint(fromView p: CGPoint) -> (Double, Double) {
        let s = convertPoint(fromView: p)
        let w = worldNode.convert(s, from: self)
        return Iso.world(w)
    }

    func setupInput(_ view: SKView) {
        #if os(iOS)
        setupTouch(view)
        #endif
    }
}
