import SpriteKit
import MeridianCore

/// Battlefield persistence: craters, scorch, residue and tread marks that outlive the fight and fade slowly.
/// Each kind is a fixed-size ring buffer of ground sprites (no allocation once warm, oldest recycled first),
/// drawn flat on the ground beneath units. Purely visual: never touches navigation or selection.
final class ScarPool {
    let cap: Int
    let life: Double
    let fade: Double
    private(set) var nodes: [SKSpriteNode] = []
    private var next = 0

    init(cap: Int, life: Double, fade: Double) { self.cap = cap; self.life = life; self.fade = fade }

    func take(parent: SKNode, texture: SKTexture?) -> SKSpriteNode {
        let s: SKSpriteNode
        if nodes.count < cap {
            s = SKSpriteNode(texture: texture)
            s.colorBlendFactor = 1
            parent.addChild(s)
            nodes.append(s)
        } else {
            s = nodes[next]
            next = (next + 1) % cap
            s.removeAllActions()
            s.texture = texture
            s.isHidden = false
            s.zRotation = 0
            s.setScale(1)
        }
        return s
    }
}

extension GameScene {

    func scarPool(_ kind: String) -> ScarPool {
        if let p = scarPools[kind] { return p }
        let p: ScarPool
        switch kind {
        case "crater": p = ScarPool(cap: 90, life: 150, fade: 30)
        case "scorch": p = ScarPool(cap: 140, life: 80, fade: 20)
        case "residue": p = ScarPool(cap: 120, life: 70, fade: 20)
        default: p = ScarPool(cap: 260, life: 10, fade: 6)   // tracks
        }
        scarPools[kind] = p
        return p
    }

    /// Lays a persistent ground mark. z 3–4 keeps marks under units and decor but above the terrain.
    func scar(_ kind: String, at p: CGPoint, size: CGSize, color: SKColor, alpha: CGFloat, rotation: CGFloat = 0, texture: SKTexture? = nil) {
        let pool = scarPool(kind)
        let s = pool.take(parent: worldNode, texture: texture ?? bank.fx[kind == "crater" ? "crater" : "scorch"])
        s.size = size; s.color = color; s.position = p; s.zRotation = rotation
        s.colorBlendFactor = kind == "crater" ? 0.35 : 1
        s.zPosition = kind == "track" ? 3 : (kind == "crater" ? 3.5 : 4)
        s.alpha = 0
        s.run(.sequence([.fadeAlpha(to: alpha, duration: kind == "track" ? 0.05 : 0.25), .wait(forDuration: pool.life), .fadeOut(withDuration: pool.fade),
                         .run { [weak s] in s?.isHidden = true }]))
    }

    /// Crater tint: the biome's own earth.
    var biomeEarth: SKColor { SKColor(red: CGFloat(biome.dirtA.x), green: CGFloat(biome.dirtA.y), blue: CGFloat(biome.dirtA.z), alpha: 1) }

    /// Tread marks behind ground vehicles, one segment per ~0.45 tiles travelled.
    func layTracks(_ e: Entity, _ v: EntityView) {
        guard quality >= 1, detail, e.moving, !e.isAir, v.vehicle || v.heavy else { return }
        let d2 = (e.x - v.trackX) * (e.x - v.trackX) + (e.y - v.trackY) * (e.y - v.trackY)
        guard d2 > 0.2 else { return }
        v.trackX = e.x; v.trackY = e.y
        guard onScreen(v.root.position) else { return }
        let dx = cos(e.facing), dy = sin(e.facing)
        let ang = atan2(16 * (dy - dx), 32 * (dx + dy))
        let fac = world.players[max(0, e.owner)].faction
        let w = max(18, v.body.size.width * 0.5)
        scar("track", at: Iso.scene(e.x, e.y), size: CGSize(width: w * 0.9, height: w * 0.42),
             color: fac == .aliens ? SKColor(red: 0.12, green: 0.18, blue: 0.08, alpha: 1) : SKColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 1),
             alpha: 0.3, rotation: CGFloat(ang), texture: fac == .aliens ? bank.fx["scorch"] : bank.fx["track"])
    }
}
