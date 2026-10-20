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
    var frames: [SKTexture] = []
    var teamRing: SKSpriteNode?
    var lastFire: Double = -1
    var bodyY: CGFloat = 0
    var turn: CGFloat = 0
    var lights: [SKSpriteNode] = []
    var fxTimer: Double = 0
    var fire: SKSpriteNode?
    var wasComplete = true

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
    var zoom: CGFloat = 1.35
    var fogTimer = 0.0
    var fxBudget = 0
    var boxStart: CGPoint?
    var vignette: SKSpriteNode?
    var hotspot: [(Double, Double)] = []
    var spectateTimer = 0.0
    var perfFrames: [Double] = []
    var trailTick = 0
    var lastProducedSound = -10.0
    var shakeEnabled = true
    var sfx: SoundEngine? { silent ? nil : SoundEngine.shared }
    var silent = false
    var backdrop = false
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
        if let z = ProcessInfo.processInfo.arguments.firstIndex(of: "-zoom").flatMap({ Double(ProcessInfo.processInfo.arguments[$0 + 1]) }) { zoom = CGFloat(z) }
        else if let hq = world.buildings(of: ctl.me).first { focus(hq.x + 3, hq.y - 3) }
        ctl.focusCamera = { [weak self] x, y in self?.focus(x, y) }
        ctl.cameraWorldRect = { [weak self] in self?.visibleWorldQuad() ?? [] }
        applyZoom()
        setupInput(view)
    }

    // MARK: Static layers

    func buildTerrain() {
        worldNode.addChild(TerrainLayer.groundNode(world))
        TerrainLayer.populate(world, bank: bank, into: worldNode)
        TerrainLayer.clouds(world, bank: bank, into: worldNode)
        let v = TerrainLayer.vignette(size: size, bank: bank)
        vignette = v
        cam.addChild(v)
        cam.addChild(TerrainLayer.motes(bank: bank))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        vignette?.size = size
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
        float fh(vec2 p) { p = fract(p * vec2(233.34, 851.73)); p += dot(p, p + 23.45); return fract(p.x * p.y); }
        float fn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(fh(i), fh(i + vec2(1.0, 0.0)), u.x), mix(fh(i + vec2(0.0, 1.0)), fh(i + vec2(1.0, 1.0)), u.x), u.y); }
        void main() {
            vec2 p = u_origin + v_tex_coord * u_size;
            float wx = (p.x / 32.0 - p.y / 16.0) * 0.5;
            float wy = (p.x / 32.0 + p.y / 16.0) * 0.5;
            vec2 uv = vec2(wx / u_n, wy / u_n);
            vec2 w = vec2(wx, wy);
            float haze = fn(w * 0.12 + vec2(u_time * 0.03, u_time * 0.015)) * 0.6 + fn(w * 0.31 - vec2(u_time * 0.02, 0.0)) * 0.4;
            float a = 0.97;
            vec3 c = mix(vec3(0.015, 0.02, 0.04), vec3(0.06, 0.07, 0.12), haze);
            if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
                vec4 f = texture2D(u_fog, uv);
                // Unexplored: drifting haze. Explored but unseen: cool translucent veil. Visible: clear.
                float unexplored = 0.88 + 0.1 * haze;
                a = mix(unexplored, 0.46, f.g);
                c = mix(c, vec3(0.03, 0.05, 0.11), f.g);
                a = mix(a, 0.0, f.r);
            }
            gl_FragColor = vec4(c * a, a);
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
        if !silent { sfx?.listener = cam.position; sfx?.hearing = max(500, size.width * zoom * 0.7) }
        shakeEnabled = UserDefaults.standard.object(forKey: "fx.shake") as? Bool ?? true
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
            let frames = bank.unit[owner][e.type]
            let s = SKSpriteNode(texture: frames[0])
            let sz = UnitArt.canvasSize(d)
            s.size = CGSize(width: sz, height: sz)
            let sh = SKSpriteNode(texture: bank.fx["shadow"], size: CGSize(width: sz * 0.8, height: sz * 0.4))
            if e.isAir {
                s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                s.position = CGPoint(x: 0, y: 38)
                sh.alpha = 0.55
                sh.position = CGPoint(x: 6, y: -2)
            } else {
                s.anchorPoint = CGPoint(x: 0.5, y: 0.12)
                sh.position = CGPoint(x: 3, y: 1)
            }
            let v = EntityView(body: s, shadow: sh)
            v.frames = frames
            v.bodyY = s.position.y
            // Team ring: the primary readability cue in big battles.
            let ring = SKSpriteNode(texture: bank.fx["teamring"])
            let rw = max(30, CGFloat(d.radius) * 120)
            ring.size = CGSize(width: rw, height: rw / 2)
            ring.color = TeamColor.sk(e.owner); ring.colorBlendFactor = 1
            ring.alpha = e.isAir ? 0.45 : 0.75
            ring.zPosition = -0.1
            v.root.insertChild(ring, at: 0)
            v.teamRing = ring
            return v
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
            s.anchorPoint = CGPoint(x: 0.5, y: k == .wood ? 0.08 : (k == .iron ? 0.22 : 0.16))
            if k == .wood { s.setScale(0.8 + CGFloat(e.id % 5) * 0.06); s.xScale *= e.id % 2 == 0 ? 1 : -1 }
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
                animateUnit(e, v, t)
            } else if e.isBuilding {
                animateBuilding(e, v, t)
            } else if e.isResource {
                let k = ResourceKind(rawValue: e.type)!
                let full = Double(k == .iron ? world.data.rules.economy.ironNodeAmount : (k == .gold ? world.data.rules.economy.goldNodeAmount : world.data.rules.economy.treeAmount))
                if k != .wood { v.body.setScale(CGFloat(0.65 + 0.35 * min(1, Double(e.amount) / full))) }
            }
            // Selection ring.
            let isSel = selected.contains(e.id)
            if isSel {
                if v.ring == nil {
                    let r = SKSpriteNode(texture: bank.fx["selectring"])
                    let rad: CGFloat = e.isBuilding ? CGFloat(e.size) * 40 : CGFloat(max(0.35, e.radius)) * 140
                    r.size = CGSize(width: rad, height: rad / 2)
                    r.colorBlendFactor = 1
                    r.zPosition = -0.05
                    r.run(.repeatForever(.sequence([.scale(to: 1.07, duration: 0.45), .scale(to: 0.97, duration: 0.45)])))
                    v.root.addChild(r)
                    v.ring = r
                }
                v.ring!.color = e.owner == ctl.me ? SKColor(red: 0.35, green: 1, blue: 0.45, alpha: 1) : (e.owner < 0 ? .yellow : SKColor(red: 1, green: 0.3, blue: 0.25, alpha: 1))
                v.ring!.isHidden = false
            } else { v.ring?.isHidden = true }
            // Health / progress bars for damaged, selected or constructing things.
            let hurt = e.hp < e.maxHp - 0.5
            let showBar = isSel || (e.isBuilding && (hurt || !e.complete)) || (hurt && (zoom < 1.5 || e.hp < e.maxHp * 0.6))
            if !e.isResource && !e.isMine && showBar {
                let bar = bar(bars); bars += 1
                let w: CGFloat = e.isBuilding ? CGFloat(e.size) * 22 : 20
                let top: CGFloat = e.isBuilding ? BuildingArt.visualHeight(world.bdef(e)) + 10 :
                    (e.isAir ? 38 + v.body.size.height * 0.45 : v.body.size.height * 0.9)
                bar.0.position = CGPoint(x: v.root.position.x, y: v.root.position.y + top)
                bar.0.size = CGSize(width: w + 2, height: e.isBuilding ? 6 : 4)
                let frac = CGFloat(e.isBuilding && !e.complete ? e.buildProgress : e.hp / max(1, e.maxHp))
                bar.1.size = CGSize(width: max(0.5, w * frac), height: e.isBuilding ? 4 : 2.2)
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
                views.removeValue(forKey: id)
                if let e = world.anyEntity(id), !e.alive, !v.root.isHidden { playDeath(e, v) } else { v.root.removeFromParent() }
            }
        }
        // Rally flag for selected production building.
        if ctl.selection.count == 1, let b = world.entity(ctl.selection[0]), b.isBuilding, b.owner == ctl.me, b.hasRally {
            rallyFlag.isHidden = false
            rallyFlag.position = Iso.scene(b.rallyX, b.rallyY)
        } else { rallyFlag.isHidden = true }
    }

    /// Per-faction motion language on top of the sprite frames.
    func animateUnit(_ e: Entity, _ v: EntityView, _ t: Double) {
        let sx = cos(e.facing) + sin(e.facing)
        if abs(sx) > 0.15 { v.facingSign = sx < 0 ? -1 : 1 }
        let fac = world.players[e.owner].faction
        let seed = Double(e.id % 97)
        let speed = world.speed(e)
        // Frame cycling: walk cycle while moving, idle engines for aircraft.
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
            // Bank into turns: compare heading change.
            let target = CGFloat(-sx) * 0.12 * (e.moving ? 1 : 0.2)
            v.turn += (target - v.turn) * 0.1
            rot = v.turn
        } else if e.moving {
            switch fac {
            case .humans: y += CGFloat(abs(sin(t * 10 + seed))) * 1.3
            case .machines: rot = CGFloat(sin(t * 7 + seed)) * 0.025; y += CGFloat(abs(sin(t * 7 + seed))) * 0.8
            case .aliens: sy = 1 + CGFloat(sin(t * 12 + seed)) * 0.05; rot = CGFloat(sin(t * 6 + seed)) * 0.05
            }
        } else if fac == .aliens {
            sy = 1 + CGFloat(sin(t * 2.5 + seed)) * 0.03     // breathing
        } else if fac == .machines {
            v.teamRing?.alpha = 0.6 + (e.linked ? 0.35 : 0) * CGFloat(0.6 + 0.4 * sin(t * 4 + seed))
        }
        // Recoil kick when firing.
        let sinceFire = t - e.lastFireTime
        var kick: CGFloat = 0
        if sinceFire < 0.12 && world.weapon(e) != nil { kick = CGFloat(1 - sinceFire / 0.12) * 2.2 }
        v.body.position = CGPoint(x: -v.facingSign * kick, y: y)
        v.body.zRotation = rot * v.facingSign
        v.body.xScale = v.facingSign
        v.body.yScale = sy
        // State tints: cloaked shimmer, hit flash, network link glow.
        v.body.alpha = world.isCloaked(e) ? 0.4 + 0.1 * CGFloat(sin(t * 6)) : 1
        if t - e.lastHitTime < 0.08 {
            v.body.colorBlendFactor = 0.55; v.body.color = SKColor(red: 1, green: 0.25, blue: 0.15, alpha: 1)
        } else if e.disruptedUntil > t {
            v.body.colorBlendFactor = 0.35; v.body.color = SKColor(red: 0.4, green: 0.6, blue: 1, alpha: 1)
        } else { v.body.colorBlendFactor = 0 }
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
