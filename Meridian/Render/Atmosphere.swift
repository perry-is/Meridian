import SpriteKit
import MeridianCore

/// Cosmetic time of day. A slow cycle (golden afternoon → dusk → a short blue night → dawn) drawn as one
/// multiply overlay above the battlefield. Light sources (building lamps, light pools, beacons, aircraft
/// navigation lights, headlights) sit above the overlay, so the world lights up as night falls.
/// Never affects the simulation. The night floor is kept bright enough that combat stays readable.
/// Disabled in Settings ("Day/night cycle"), the world holds the original golden look.
enum Sky {
    /// Seconds of match time for one full day.
    static let period = 660.0
    /// The match opens in the afternoon.
    static let startPhase = 0.06
    /// Global z of the overlay; light sources draw just above it, combat effects (455+) stay above both.
    static let overlayZ: CGFloat = 450
    static let lightZ: CGFloat = 451

    /// (phase, multiply colour) keyframes.
    static let keys: [(Double, SIMD3<Double>)] = [
        (0.00, [1.00, 1.00, 1.00]),
        (0.22, [1.00, 0.93, 0.82]),   // golden hour
        (0.32, [0.86, 0.74, 0.84]),   // dusk
        (0.42, [0.66, 0.71, 0.96]),   // night
        (0.62, [0.66, 0.71, 0.96]),
        (0.74, [0.96, 0.80, 0.84]),   // dawn
        (0.84, [1.00, 0.97, 0.92]),
        (1.00, [1.00, 1.00, 1.00]),
    ]

    static func color(_ phase: Double) -> SIMD3<Double> {
        let p = phase - floor(phase)
        for i in 1..<keys.count where p <= keys[i].0 {
            let (a, ca) = keys[i - 1], (b, cb) = keys[i]
            var k = (p - a) / max(1e-6, b - a)
            k = k * k * (3 - 2 * k)
            return ca + (cb - ca) * k
        }
        return keys[0].1
    }

    /// 0 in daylight, 1 at full night (how strongly lights show).
    static func darkness(_ c: SIMD3<Double>) -> CGFloat {
        CGFloat(min(1, max(0, (1 - (c.x + c.y) / 2) / 0.32)))
    }

    /// `-tod <phase>` pins the time of day (captures and testing).
    static let pinned: Double? = ProcessInfo.processInfo.arguments.firstIndex(of: "-tod").flatMap { Double(ProcessInfo.processInfo.arguments[$0 + 1]) }

    static var enabled: Bool { UserDefaults.standard.object(forKey: "fx.daynight") as? Bool ?? true }
}

extension GameScene {

    func buildSky() {
        let o = SKSpriteNode(color: .white, size: size)
        o.blendMode = .multiply
        o.zPosition = Sky.overlayZ
        o.isHidden = true
        cam.addChild(o)
        skyOverlay = o
        // Fireflies (meadow, delta) wake up after dusk.
        if biome.ambient != .dust {
            let f = SKEmitterNode()
            f.particleTexture = bank.fx["glow"]
            f.particleBirthRate = 0
            f.particleLifetime = 6; f.particleLifetimeRange = 3
            f.particlePositionRange = CGVector(dx: 1200, dy: 1600)
            f.particleSpeed = 10; f.particleSpeedRange = 8
            f.emissionAngleRange = .pi * 2
            f.particleAlpha = 0
            f.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.0, 0.9, 0.1, 0.9, 0.0] as [NSNumber], times: [0, 0.2, 0.45, 0.7, 1])
            f.particleScale = 0.1; f.particleScaleRange = 0.05
            f.particleColor = SKColor(red: 0.85, green: 1, blue: 0.45, alpha: 1); f.particleColorBlendFactor = 1
            f.particleBlendMode = .add
            f.zPosition = Sky.lightZ + 2
            cam.addChild(f)
            fireflies = f
        }
    }

    func updateSky() {
        guard let o = skyOverlay else { return }
        let on = Sky.enabled && !ctl.stressMode && !ctl.battleMode
        let c = Sky.pinned.map { Sky.color($0) } ?? (on ? Sky.color(Sky.startPhase + world.time / Sky.period) : SIMD3<Double>(1, 1, 1))
        night = Sky.darkness(c)
        o.isHidden = c.x > 0.995 && c.y > 0.995 && c.z > 0.995
        o.color = SKColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        o.size = CGSize(width: size.width + 8, height: size.height + 8)
        fireflies?.particleBirthRate = night > 0.4 && zoom < 2.4 ? 9 * night : 0
        groundShader?.uniformNamed("u_night")?.floatValue = Float(night)
    }

    /// Places a light child above the night overlay regardless of its parent's depth.
    @inline(__always) func liftLight(_ l: SKNode, in v: EntityView, by dz: CGFloat = 0) {
        l.zPosition = Sky.lightZ + dz - v.root.zPosition
    }

    /// Soft pool of light on the ground under a lit structure (shown from dusk).
    func lightPool(_ v: EntityView, width: CGFloat, color: SKColor, strength: CGFloat) {
        if v.pool == nil {
            let p = SKSpriteNode(texture: bank.fx["glow"])
            p.blendMode = .add; p.colorBlendFactor = 1
            v.root.addChild(p); v.pool = p
        }
        guard let p = v.pool else { return }
        p.isHidden = night < 0.05
        if p.isHidden { return }
        p.color = color
        p.size = CGSize(width: width, height: width * 0.5)
        p.alpha = night * strength
        liftLight(p, in: v, by: -0.5)
    }
}

/// Wind sway for decor sprites (grass, reeds, trees), done in the fragment shader so thousands of sprites
/// animate with no per-frame CPU work. Works on atlas textures: `a_rect` is the sprite's sub-rectangle.
enum Sway {
    static let shader: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 r = a_rect;
            float ly = clamp((v_tex_coord.y - r.y) / r.w, 0.0, 1.0);
            float bend = sin(u_time * a_sway.x + a_sway.y) * a_sway.z * ly * ly;
            vec2 uv = v_tex_coord - vec2(bend * r.z, 0.0);
            float inside = step(r.x, uv.x) * step(uv.x, r.x + r.z);
            vec4 c = texture2D(u_texture, uv) * inside;
            c.rgb = mix(c.rgb, a_tint.rgb * c.a, a_tint.a);
            gl_FragColor = c * v_color_mix.a;
        }
        """)
        s.attributes = [SKAttribute(name: "a_rect", type: .vectorFloat4), SKAttribute(name: "a_sway", type: .vectorFloat3),
                        SKAttribute(name: "a_tint", type: .vectorFloat4)]
        return s
    }()

    /// speed (rad/s), phase, amplitude (fraction of sprite width at the top).
    static func apply(_ s: SKSpriteNode, speed: Float, phase: Float, amplitude: Float, tint: SKColor = .white, tintAmount: CGFloat = 0) {
        guard let t = s.texture else { return }
        let r = t.textureRect()
        var cr: CGFloat = 1, cg: CGFloat = 1, cb: CGFloat = 1, ca: CGFloat = 1
        #if os(iOS)
        tint.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
        #else
        (tint.usingColorSpace(.sRGB) ?? tint).getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
        #endif
        s.shader = shader
        s.setValue(SKAttributeValue(vectorFloat4: vector_float4(Float(r.minX), Float(r.minY), Float(r.width), Float(r.height))), forAttribute: "a_rect")
        s.setValue(SKAttributeValue(vectorFloat3: vector_float3(speed, phase, amplitude)), forAttribute: "a_sway")
        s.setValue(SKAttributeValue(vectorFloat4: vector_float4(Float(cr), Float(cg), Float(cb), Float(tintAmount))), forAttribute: "a_tint")
    }
}
