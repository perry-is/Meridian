import SpriteKit
import MeridianCore
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    static func from(_ cg: CGImage) -> PlatformImage {
        #if os(iOS)
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        #endif
    }
}

/// Team colours for up to four players.
enum TeamColor {
    static let colors: [RGB] = [RGB(0.22, 0.62, 1.0), RGB(1.0, 0.33, 0.24), RGB(0.95, 0.85, 0.2), RGB(0.7, 0.4, 1.0)]
    static func rgb(_ p: Int) -> RGB { p < 0 ? RGB(0.85, 0.85, 0.85) : colors[p % colors.count] }
    static func sk(_ p: Int) -> SKColor { let c = rgb(p); return SKColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    static func swiftUI(_ p: Int) -> (Double, Double, Double) { let c = rgb(p); return (Double(c.r), Double(c.g), Double(c.b)) }
}

/// Generates every texture once at match start and packs them into a single atlas so SpriteKit can batch draws.
final class TextureBank {
    let data: GameData
    private(set) var unit: [[[SKTexture]]] = []     // [player][unitType][frame]
    private(set) var building: [[SKTexture]] = []   // [player][buildingType]
    private(set) var resource: [[SKTexture]] = []   // [kind][variant]
    private(set) var cliffs: [SKTexture] = []
    private(set) var flora: [[SKTexture]] = []
    private(set) var fx: [String: SKTexture] = [:]
    private(set) var explosion: [SKTexture] = []
    private(set) var sparks: [SKTexture] = []
    private(set) var lightning: [SKTexture] = []
    private(set) var splats: [SKTexture] = []
    private(set) var shards: [SKTexture] = []
    private(set) var sitePlatform: SKTexture!
    private(set) var siteBeacon: SKTexture!
    /// Cached SwiftUI-friendly icons.
    private(set) var unitIcons: [Int: CGImage] = [:]
    private(set) var buildingIcons: [Int: CGImage] = [:]

    static var cache: [String: TextureBank] = [:]

    /// Standalone portrait (menu showcase) rendered on demand and memoised.
    nonisolated(unsafe) static var portraits: [Int: CGImage] = [:]
    static func portrait(_ unit: Int, team: Int) -> CGImage? {
        if let p = portraits[unit] { return p }
        let img = UnitArt.render(GameData.shared.units[unit], team: TeamColor.rgb(team))
        portraits[unit] = img
        return img
    }

    static func make(data: GameData, factions: [Faction]) -> TextureBank {
        let key = factions.map { $0.rawValue }.joined(separator: "-")
        if let c = cache[key] { return c }
        let b = TextureBank(data: data, factions: factions)
        cache = [key: b]
        return b
    }

    private init(data: GameData, factions: [Faction]) {
        self.data = data
        let t0 = Date()
        defer { print(String(format: "BANK generated in %.2fs", Date().timeIntervalSince(t0))) }
        var images: [String: PlatformImage] = [:]
        var unitNames: [[String]] = [], buildingNames: [[String]] = []
        for (pi, f) in factions.enumerated() {
            let tc = TeamColor.rgb(pi)
            var un: [String] = [], bn: [String] = []
            for (i, u) in data.units.enumerated() {
                let name = "u\(pi)_\(i)"
                un.append(name)
                guard u.faction == f else { continue }
                for fr in 0..<UnitArt.frameCount {
                    let img = UnitArt.render(u, team: tc, frame: fr)
                    images[name + "_\(fr)"] = .from(img)
                    if pi == 0 && fr == 0 { unitIcons[i] = img }
                }
            }
            for (i, b) in data.buildings.enumerated() {
                let name = "b\(pi)_\(i)"
                bn.append(name)
                guard b.faction == f else { continue }
                let img = WorldArt.building(b, team: tc)
                images[name] = .from(img)
                if pi == 0 { buildingIcons[i] = img }
            }
            unitNames.append(un); buildingNames.append(bn)
        }
        // Icons for every faction (tech screens show all of the player's own faction only, but keep complete).
        for (i, u) in data.units.enumerated() where unitIcons[i] == nil { unitIcons[i] = UnitArt.render(u, team: TeamColor.rgb(0)) }
        for (i, b) in data.buildings.enumerated() where buildingIcons[i] == nil { buildingIcons[i] = WorldArt.building(b, team: TeamColor.rgb(0)) }
        for v in 0..<3 {
            images["r0_\(v)"] = .from(EnvironmentArt.iron(v))
            images["r1_\(v)"] = .from(EnvironmentArt.gold(v))
            images["r2_\(v)"] = .from(EnvironmentArt.tree(v))
        }
        for v in 0..<6 { images["cliff\(v)"] = .from(EnvironmentArt.cliff(v)) }
        for k in 0..<5 { for v in 0..<2 { images["flora\(k)_\(v)"] = .from(EnvironmentArt.flora(k, v)) } }
        let fxNames = ["glow", "ring", "shadow", "beam", "bolt", "orb", "shell", "spark", "smoke", "scorch", "pixel"]
        for n in fxNames { images["fx_" + n] = .from(WorldArt.effect(n)) }
        images["fx_vignette"] = .from(EnvironmentArt.vignette())
        images["fx_teamring"] = .from(EnvironmentArt.teamRing())
        for (i, im) in EffectsArt.explosionFrames().enumerated() { images["ex\(i)"] = .from(im) }
        for (i, im) in EffectsArt.sparkFrames().enumerated() { images["sp\(i)"] = .from(im) }
        for v in 0..<3 { images["ln\(v)"] = .from(EffectsArt.lightning(v)); images["splat\(v)"] = .from(EffectsArt.splat(v)) }
        for v in 0..<2 { images["shard\(v)"] = .from(EffectsArt.shard(v)) }
        images["fx_slash"] = .from(EffectsArt.slash())
        images["fx_rubble"] = .from(EffectsArt.rubble())
        images["fx_shockwave"] = .from(EffectsArt.shockwave())
        images["fx_selectring"] = .from(EffectsArt.selectRing())
        for k in ["heavy", "siege", "air", "marker", "field", "support", "worker"] { images["fx_ring_" + k] = .from(EffectsArt.classRing(k)) }
        images["fx_cloud"] = .from(EnvironmentArt.cloud())
        images["fx_cone"] = .from(EffectsArt.cone())
        images["fx_dish"] = .from(EffectsArt.radarDish())
        images["fx_flag"] = .from(EffectsArt.flag())
        images["fx_critter0"] = .from(EffectsArt.critter(0)); images["fx_critter1"] = .from(EffectsArt.critter(1))
        images["fx_skyray"] = .from(EffectsArt.skyray())
        images["fx_crater"] = .from(EffectsArt.crater())
        images["fx_track"] = .from(EffectsArt.track())
        images["fx_bird0"] = .from(EffectsArt.bird(0)); images["fx_bird1"] = .from(EffectsArt.bird(1))
        images["site_platform"] = .from(WorldArt.sitePlatform())
        images["site_beacon"] = .from(WorldArt.siteBeacon())

        let atlas = SKTextureAtlas(dictionary: images)
        unit = unitNames.map { $0.map { n in (0..<UnitArt.frameCount).map { images[n + "_\($0)"] != nil ? atlas.textureNamed(n + "_\($0)") : SKTexture() } } }
        building = buildingNames.map { $0.map { images[$0] != nil ? atlas.textureNamed($0) : SKTexture() } }
        resource = ResourceKind.allCases.map { k in (0..<3).map { atlas.textureNamed("r\(k.rawValue)_\($0)") } }
        cliffs = (0..<6).map { atlas.textureNamed("cliff\($0)") }
        flora = (0..<5).map { k in (0..<2).map { atlas.textureNamed("flora\(k)_\($0)") } }
        explosion = (0..<8).map { atlas.textureNamed("ex\($0)") }
        sparks = (0..<4).map { atlas.textureNamed("sp\($0)") }
        lightning = (0..<3).map { atlas.textureNamed("ln\($0)") }
        splats = (0..<3).map { atlas.textureNamed("splat\($0)") }
        shards = (0..<2).map { atlas.textureNamed("shard\($0)") }
        for n in fxNames + ["vignette", "cloud", "teamring", "slash", "rubble", "shockwave", "selectring", "ring_heavy", "ring_siege", "ring_air", "ring_marker", "ring_field", "cone", "crater", "track", "bird0", "bird1", "dish", "flag", "ring_support", "ring_worker", "critter0", "critter1", "skyray"] { fx[n] = atlas.textureNamed("fx_" + n) }
        sitePlatform = atlas.textureNamed("site_platform")
        siteBeacon = atlas.textureNamed("site_beacon")
    }

}
