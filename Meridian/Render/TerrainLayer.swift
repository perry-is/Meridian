import SpriteKit
import MeridianCore

/// "Twilight Frontier" battlefield: a single shader-drawn ground quad that blends terrain types smoothly,
/// plus depth-sorted rock formations, flora doodads and atmospheric overlays.
enum TerrainLayer {

    // MARK: Data textures

    /// Two N×N RGBA textures describing the map for the ground shader (bilinear-sampled, pre-blurred).
    /// terrain: R dirt, G moss, B rock, A water. extra: R elevation, G iron stain, B gold glint, A forest floor.
    static func dataTextures(_ world: World) -> (SKTexture, SKTexture) {
        let m = world.map, n = m.size
        var t = [Float](repeating: 0, count: n * n * 4)
        var e = [Float](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                switch m.terrainAt(x, y) {
                case .dirt: t[i] = 1
                case .moss: t[i + 1] = 1
                case .rock: t[i + 2] = 1
                case .water: t[i + 3] = 1
                case .grass: break
                }
                e[i] = Float(m.elevation[m.idx(x, y)])
            }
        }
        for r in m.resources {
            let i = (r.y * n + r.x) * 4
            switch r.kind {
            case .iron: e[i + 1] = 1
            case .gold: e[i + 2] = 1
            case .wood: e[i + 3] = 1
            }
        }
        t = blur(t, n, passes: 1)
        e = blur(e, n, passes: 2)
        return (texture(t, n), texture(e, n))
    }

    static func blur(_ a: [Float], _ n: Int, passes: Int) -> [Float] {
        var src = a
        for _ in 0..<passes {
            var dst = src
            for y in 0..<n {
                for x in 0..<n {
                    for c in 0..<4 {
                        var s: Float = 0, w: Float = 0
                        for dy in -1...1 {
                            for dx in -1...1 {
                                let xx = x + dx, yy = y + dy
                                guard xx >= 0, yy >= 0, xx < n, yy < n else { continue }
                                let k: Float = (dx == 0 && dy == 0) ? 4 : (dx == 0 || dy == 0 ? 2 : 1)
                                s += src[(yy * n + xx) * 4 + c] * k; w += k
                            }
                        }
                        dst[(y * n + x) * 4 + c] = s / w
                    }
                }
            }
            src = dst
        }
        return src
    }

    static func texture(_ f: [Float], _ n: Int) -> SKTexture {
        let bytes = f.map { UInt8(clamp($0, 0, 1) * 255) }
        let t = SKTexture(data: Data(bytes), size: CGSize(width: n, height: n), flipped: false)
        t.filteringMode = .linear
        return t
    }

    // MARK: Ground shader

    static let groundSource = """
    float h21(vec2 p) { p = fract(p * vec2(233.34, 851.73)); p += dot(p, p + 23.45); return fract(p.x * p.y); }
    float vnoise(vec2 p) {
        vec2 i = floor(p); vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
    }
    float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { v += a * vnoise(p); p = p * 2.07 + 13.1; a *= 0.5; } return v; }

    void main() {
        vec2 p = u_origin + v_tex_coord * u_size;
        vec2 w = vec2((p.x / 32.0 - p.y / 16.0) * 0.5, (p.x / 32.0 + p.y / 16.0) * 0.5);
        vec2 uv = w / u_n;
        vec2 edge = min(uv, 1.0 - uv);
        float inside = min(edge.x, edge.y);
        // Beyond the map: a hazy abyss that fades from the rim (blended at the end).
        float outside = clamp(-inside * u_n / 10.0, 0.0, 1.0);
        float isOut = step(inside, 0.0);
        uv = clamp(uv, 0.0, 1.0);
        vec4 t = texture2D(u_terrain, uv);
        vec4 e = texture2D(u_extra, uv);
        float n1 = fbm(w * 0.18);
        float n2 = vnoise(w * 1.3);
        float n3 = vnoise(w * 5.0);
        float n4 = vnoise(w * 13.0);

        // Organic boundaries: noise pushes weights around before thresholding.
        float dirt = smoothstep(0.30, 0.70, t.r + (n2 - 0.5) * 0.45);
        float moss = smoothstep(0.30, 0.70, t.g + (n2 - 0.5) * 0.45);
        float rock = smoothstep(0.25, 0.60, t.b + (n3 - 0.5) * 0.25);
        float water = smoothstep(0.38, 0.62, t.a + (n2 - 0.5) * 0.18);

        vec3 grassC = mix(u_grassA, u_grassB, n1);
        grassC = mix(grassC, u_dry, smoothstep(0.6, 0.85, n2) * 0.35);  // dry patches
        grassC *= 0.86 + 0.26 * n4;
        // Wind: soft gust bands sweep across open grass; fine blades shimmer along the wind.
        vec2 wd = normalize(u_wind + vec2(0.0001, 0.0));
        float gust = vnoise(w * 0.22 - u_wind * u_time * 0.35);
        float blades = vnoise(vec2(dot(w, wd) * 6.0 - u_time * 2.2, dot(w, vec2(-wd.y, wd.x)) * 1.2));
        float sway = (smoothstep(0.5, 0.82, gust) * (0.75 + 0.5 * blades) - 0.12) * 0.11 * u_gust;
        vec3 mossC = mix(u_mossA, u_mossB, n1) * (0.88 + 0.22 * n4);
        vec3 dirtC = mix(u_dirtA, u_dirtB, n2 * 0.6 + n1 * 0.4) * (0.9 + 0.18 * n4);
        if (u_cracks > 0.0) {
            // Dried, cracked earth: cell edges of a jittered grid.
            vec2 cp = w * 1.7; vec2 ci = floor(cp); vec2 cf = fract(cp);
            float d1 = 8.0; float d2 = 8.0;
            for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) {
                vec2 g = vec2(float(i), float(j));
                vec2 o = vec2(h21(ci + g), h21(ci + g + 17.0));
                float dd = length(g + o - cf);
                d2 = min(d2, max(d1, dd)); d1 = min(d1, dd);
            } }
            float crack = 1.0 - smoothstep(0.02, 0.07, d2 - d1);
            dirtC *= 1.0 - crack * 0.26 * u_cracks * (0.6 + 0.4 * n2);
        }
        vec3 rockC = mix(u_rockA, u_rockB, n3) * (0.85 + 0.2 * n4);

        vec3 col = grassC;
        col = mix(col, mossC, moss);
        col = mix(col, dirtC, dirt);
        col = mix(col, rockC, rock);
        col *= 1.0 + sway * (1.0 - dirt) * (1.0 - rock);

        // Tiny wildflowers and pebbles (world-space so they stay put while zooming).
        vec2 cell = floor(w * 5.0);
        float speck = h21(cell);
        vec2 fc = fract(w * 5.0) - 0.5 - (vec2(h21(cell + 3.1), h21(cell + 7.7)) - 0.5) * 0.5;
        float petal = 1.0 - smoothstep(0.07, 0.11, length(fc * vec2(1.0, 1.6)));
        float flower = step(0.985, speck) * petal * (1.0 - dirt) * (1.0 - rock) * (1.0 - water);
        vec3 flowerC = mix(u_flowerA, u_flowerB, step(0.9925, speck));
        col = mix(col, flowerC, flower * 0.85);
        col = mix(col, col * 0.7, step(0.975, h21(floor(w * 4.0) + 7.0)) * dirt * 0.6);

        // Resource ground: rusty ore stain, gold glints, dark forest floor.
        col = mix(col, vec3(0.30, 0.22, 0.20), e.g * 0.55);
        vec3 emis = vec3(0.0);   // self-lit terms, boosted at night so they glow through the dark
        float glint = e.b * step(0.93, vnoise(w * 9.0 + u_time * 0.4));
        col = mix(col, vec3(1.0, 0.85, 0.4), glint * 0.8);
        emis += vec3(1.0, 0.75, 0.3) * (glint * 0.6 + e.b * 0.12);
        col *= 1.0 - e.a * 0.28;

        // Fake relief lighting from the elevation field (light from the upper left of the screen).
        float d = 1.0 / u_n;
        float hx = texture2D(u_extra, uv + vec2(d, 0.0)).r - texture2D(u_extra, uv - vec2(d, 0.0)).r;
        float hy = texture2D(u_extra, uv + vec2(0.0, d)).r - texture2D(u_extra, uv - vec2(0.0, d)).r;
        float light = clamp(1.0 + (-hx * 1.4 + hy * 0.5) * 0.9, 0.7, 1.3);
        col *= light * (1.0 + e.r * 0.08);

        // Water: depth gradient, moving ripples, glinting highlights, foam on the shoreline.
        if (water > 0.0) {
            float depth = smoothstep(0.5, 1.0, t.a);
            vec3 wc = mix(u_waterS, u_waterD, depth);
            vec2 fl = u_flow * u_time;
            float rip = vnoise(w * 2.2 - fl) * vnoise(w * 3.1 - fl * 1.4 + vec2(u_time * 0.1, 0.0));
            // Luminous mineral pools: slow internal light and bright rims.
            vec3 pool = u_waterGlow * vec3(0.10, 0.35, 0.40) * (0.5 + 0.5 * sin(u_time * 0.8 + n1 * 6.0)) * (1.0 - depth * 0.5);
            wc += pool;
            emis += pool * water * 1.6;
            wc += vec3(0.25, 0.35, 0.4) * smoothstep(0.35, 0.6, rip) * 0.35;
            wc += vec3(1.0, 0.9, 0.7) * step(0.985, vnoise(w * 7.0 + u_time * 0.8)) * 0.6;
            float foam = smoothstep(0.42, 0.5, t.a) * (1.0 - smoothstep(0.5, 0.62, t.a + (n3 - 0.5) * 0.1));
            foam *= 0.6 + 0.4 * sin(u_time * 1.6 + n2 * 9.0);
            wc = mix(wc, vec3(0.85, 0.95, 0.95), foam * 0.75);
            col = mix(col, wc, water);
        } else {
            // Damp darkened banks near water.
            col *= 1.0 - smoothstep(0.15, 0.38, t.a) * 0.25;
        }

        // Warm dusk grade: lift reds slightly, cool the darks.
        col = col * u_grade + u_lift * (1.0 - col);
        col += emis * u_night * 0.7;
        vec3 abyss = mix(u_abyss, vec3(0.02, 0.03, 0.05), outside);
        gl_FragColor = vec4(mix(col, abyss, isOut), 1.0);
    }
    """

    static func groundNode(_ world: World, biome b: Biome) -> SKSpriteNode {
        let n = CGFloat(world.map.size)
        let pad: CGFloat = 1600
        let w = n * 64 + pad * 2, h = n * 32 + pad * 2
        let node = SKSpriteNode(color: .black, size: CGSize(width: w, height: h))
        node.position = CGPoint(x: n * 32, y: 0)
        node.zPosition = -10
        let (tt, te) = dataTextures(world)
        let sh = SKShader(source: groundSource)
        sh.uniforms = [
            SKUniform(name: "u_origin", vectorFloat2: vector_float2(Float(n * 32 - w / 2), Float(-h / 2))),
            SKUniform(name: "u_size", vectorFloat2: vector_float2(Float(w), Float(h))),
            SKUniform(name: "u_n", float: Float(n)),
            SKUniform(name: "u_terrain", texture: tt),
            SKUniform(name: "u_extra", texture: te),
        ]
        func v3(_ n: String, _ v: SIMD3<Float>) { sh.addUniform(SKUniform(name: n, vectorFloat3: vector_float3(v.x, v.y, v.z))) }
        func v2(_ n: String, _ v: SIMD2<Float>) { sh.addUniform(SKUniform(name: n, vectorFloat2: vector_float2(v.x, v.y))) }
        v3("u_grassA", b.grassA); v3("u_grassB", b.grassB); v3("u_dry", b.dry)
        v3("u_mossA", b.mossA); v3("u_mossB", b.mossB); v3("u_dirtA", b.dirtA); v3("u_dirtB", b.dirtB)
        v3("u_rockA", b.rockA); v3("u_rockB", b.rockB); v3("u_waterS", b.waterS); v3("u_waterD", b.waterD)
        v3("u_flowerA", b.flowerA); v3("u_flowerB", b.flowerB); v3("u_grade", b.grade); v3("u_lift", b.lift); v3("u_abyss", b.abyss)
        v2("u_flow", b.flow); v2("u_wind", b.wind)
        sh.addUniform(SKUniform(name: "u_waterGlow", float: b.waterGlow))
        sh.addUniform(SKUniform(name: "u_gust", float: b.gust))
        sh.addUniform(SKUniform(name: "u_cracks", float: b.cracks))
        sh.addUniform(SKUniform(name: "u_night", float: 0))
        node.shader = sh
        return node
    }

    // MARK: Rock formations and flora

    /// Depth-sorted cliffs on rock tiles plus scattered flora. Interior rock tiles get taller spires.
    static func populate(_ world: World, bank: TextureBank, biome: Biome, into parent: SKNode) {
        let m = world.map, n = m.size
        func isRock(_ x: Int, _ y: Int) -> Bool { m.inBounds(x, y) && m.terrainAt(x, y) == .rock }
        for y in 0..<n {
            for x in 0..<n {
                let t = m.terrainAt(x, y)
                let r = hnoise(x, y, 31)
                if t == .rock {
                    var neighbors = 0
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where isRock(x + dx, y + dy) { neighbors += 1 }
                    let interior = neighbors >= 3
                    let tex = bank.cliffs[(interior ? 3 : 0) + Int(hnoise(x, y, 6) * 3) % 3]
                    let s = SKSpriteNode(texture: tex)
                    s.anchorPoint = CGPoint(x: 0.5, y: 0.2)
                    let jx = Double(hnoise(x, y, 8) - 0.5) * 0.4, jy = Double(hnoise(x, y, 9) - 0.5) * 0.4
                    s.position = Iso.scene(Double(x) + 0.5 + jx, Double(y) + 0.5 + jy)
                    let sc = (interior ? 0.75 : 0.6) + hnoise(x, y, 10) * 0.25
                    s.setScale(sc)
                    s.xScale *= hnoise(x, y, 11) > 0.5 ? -1 : 1
                    s.zPosition = 100 + Iso.depth(Double(x) + 0.5, Double(y) + 0.5) * 0.4
                    s.color = biome.cliffTint; s.colorBlendFactor = biome.cliffTintAmount
                    parent.addChild(s)
                    continue
                }
                guard t != .water, world.occupant[m.idx(x, y)] < 0 else { continue }
                // Keep base pads and sites tidy.
                if world.sites.contains(where: { dist2($0.x, $0.y, Double(x), Double(y)) < 9 }) { continue }
                var nearWater = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where m.inBounds(x + dx, y + dy) && m.terrainAt(x + dx, y + dy) == .water { nearWater = true }
                let kind: Int
                if nearWater && r < 0.25 { kind = 2 }                 // reeds
                else if t == .moss && r < 0.04 { kind = 3 }           // glowcaps
                else if r < 0.012 { kind = 4 }                        // crystal shard
                else if r < (t == .grass ? 0.08 : 0.04) { kind = Int(hnoise(x, y, 12) * 2) } // grass tufts
                else { continue }
                let s = SKSpriteNode(texture: bank.flora[kind][Int(hnoise(x, y, 13) * 2) % 2])
                s.anchorPoint = CGPoint(x: 0.5, y: 0.15)
                let jx = Double(hnoise(x, y, 14)) * 0.8 + 0.1, jy = Double(hnoise(x, y, 15)) * 0.8 + 0.1
                s.position = Iso.scene(Double(x) + jx, Double(y) + jy)
                // Decor stays quieter than combatants: smaller and slightly desaturated toward the ground.
                s.setScale((kind == 4 ? 0.5 : 0.6) + hnoise(x, y, 16) * 0.3)
                s.alpha = kind == 4 ? 0.8 : 0.85
                s.color = biome.floraTint; s.colorBlendFactor = kind >= 3 ? 0.15 : 0.25
                s.zPosition = kind == 4 ? 100 + Iso.depth(Double(x) + jx, Double(y) + jy) * 0.4 : 6
                if kind == 3 || kind == 4 {
                    s.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 1.5 + Double(r) * 2), .fadeAlpha(to: 0.85, duration: 1.5)])))
                }
                parent.addChild(s)
            }
        }
    }

    // MARK: Atmosphere (camera-space and world-space overlays)

    static func vignette(size: CGSize, bank: TextureBank) -> SKSpriteNode {
        let v = SKSpriteNode(texture: bank.fx["vignette"], size: size)
        v.zPosition = 900
        v.alpha = 0.85
        return v
    }

    static func clouds(_ world: World, bank: TextureBank, biome: Biome, into parent: SKNode) {
        let n = Double(world.map.size)
        var r = RNG(seed: 99)
        for k in 0..<7 {
            let c = SKSpriteNode(texture: bank.fx["cloud"])
            c.size = CGSize(width: 1400 + r.range(0, 900), height: 700 + r.range(0, 400))
            c.blendMode = .multiplyAlpha
            c.alpha = biome.cloudAlpha
            c.zPosition = 580
            let start = Iso.scene(r.range(-20, n), r.range(0, n))
            c.position = start
            parent.addChild(c)
            // Slow drift across the map, wrapping around.
            let dx = 64 * n + 3000
            let dur = 260 + Double(k) * 40
            c.position.x = start.x - 1500
            c.run(.repeatForever(.sequence([.moveBy(x: dx, y: 0, duration: dur), .moveBy(x: -dx, y: 0, duration: 0)])))
        }
    }

    static func motes(bank: TextureBank, biome: Biome) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = bank.fx["glow"]
        e.particleBirthRate = 6
        e.particleLifetime = 9
        e.particleLifetimeRange = 4
        e.particlePositionRange = CGVector(dx: 1400, dy: 1400)
        e.particleSpeed = 14
        e.particleSpeedRange = 10
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi
        e.particleAlpha = 0
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.0, 0.55, 0.0] as [NSNumber], times: [0, 0.5, 1])
        e.particleScale = 0.18
        e.particleScaleRange = 0.12
        e.particleColor = biome.moteColor
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.zPosition = 890
        switch biome.ambient {
        case .pollen: break
        case .mist:
            // Slow, fat spores drifting up from the wetlands.
            e.particleBirthRate = 5; e.particleSpeed = 8; e.particleScale = 0.14; e.particleScaleRange = 0.08
            e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.0, 0.7, 0.2, 0.7, 0.0] as [NSNumber], times: [0, 0.25, 0.5, 0.75, 1])
        case .dust:
            // Grit carried sideways on the plateau wind.
            e.particleTexture = bank.fx["smoke"]; e.particleBlendMode = .alpha
            e.particleBirthRate = 14; e.particleLifetime = 5; e.particleSpeed = 120; e.particleSpeedRange = 50
            e.emissionAngle = -0.25; e.emissionAngleRange = 0.25
            e.particleScale = 0.12; e.particleScaleRange = 0.1
            e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.0, 0.32, 0.0] as [NSNumber], times: [0, 0.5, 1])
        }
        e.advanceSimulationTime(10)
        return e
    }

    /// Slow banks of low mist over the delta's water (world space, beneath units' heads).
    static func mistBanks(_ world: World, bank: TextureBank, into parent: SKNode) {
        let m = world.map
        var r = RNG(seed: 7)
        var placed = 0
        for _ in 0..<400 where placed < 16 {
            let x = r.int(m.size), y = r.int(m.size)
            guard m.terrainAt(x, y) == .water else { continue }
            let c = SKSpriteNode(texture: bank.fx["cloud"])
            c.size = CGSize(width: 420 + r.range(0, 260), height: 120 + r.range(0, 60))
            c.color = SKColor(red: 0.85, green: 0.95, blue: 1, alpha: 1); c.colorBlendFactor = 1
            c.blendMode = .screen
            c.alpha = 0
            c.position = Iso.scene(Double(x), Double(y))
            c.zPosition = 160
            let a = 0.22 + r.range(0, 0.12)
            let p = 16 + r.range(0, 10)
            c.run(.repeatForever(.sequence([.group([.fadeAlpha(to: CGFloat(a), duration: p), .moveBy(x: 90, y: 30, duration: p)]),
                                            .group([.fadeAlpha(to: 0.04, duration: p), .moveBy(x: -90, y: -30, duration: p)])])))
            parent.addChild(c)
            placed += 1
        }
    }

}
