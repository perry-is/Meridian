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
    private(set) var unit: [[SKTexture]] = []       // [player][unitType]
    private(set) var building: [[SKTexture]] = []   // [player][buildingType]
    private(set) var resource: [[SKTexture]] = []   // [kind][variant]
    private(set) var boulders: [SKTexture] = []
    private(set) var fx: [String: SKTexture] = [:]
    private(set) var sitePlatform: SKTexture!
    private(set) var siteBeacon: SKTexture!
    private(set) var tileSet: SKTileSet!
    private(set) var tileGroups: [String: SKTileGroup] = [:]
    /// Cached SwiftUI-friendly icons.
    private(set) var unitIcons: [Int: CGImage] = [:]
    private(set) var buildingIcons: [Int: CGImage] = [:]

    static var cache: [String: TextureBank] = [:]

    static func make(data: GameData, factions: [Faction]) -> TextureBank {
        let key = factions.map { $0.rawValue }.joined(separator: "-")
        if let c = cache[key] { return c }
        let b = TextureBank(data: data, factions: factions)
        cache = [key: b]
        return b
    }

    private init(data: GameData, factions: [Faction]) {
        self.data = data
        var images: [String: PlatformImage] = [:]
        var unitNames: [[String]] = [], buildingNames: [[String]] = []
        for (pi, f) in factions.enumerated() {
            let tc = TeamColor.rgb(pi)
            var un: [String] = [], bn: [String] = []
            for (i, u) in data.units.enumerated() {
                let name = "u\(pi)_\(i)"
                un.append(name)
                guard u.faction == f else { continue }
                let img = UnitArt.render(u, team: tc)
                images[name] = .from(img)
                if pi == 0 { unitIcons[i] = img }
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
        for k in ResourceKind.allCases { for v in 0..<3 { images["r\(k.rawValue)_\(v)"] = .from(WorldArt.resource(k, variant: v)) } }
        for v in 0..<3 { images["boulder\(v)"] = .from(WorldArt.boulder(variant: v)) }
        let fxNames = ["glow", "ring", "shadow", "beam", "bolt", "orb", "shell", "spark", "smoke", "scorch", "pixel"]
        for n in fxNames { images["fx_" + n] = .from(WorldArt.effect(n)) }
        images["site_platform"] = .from(WorldArt.sitePlatform())
        images["site_beacon"] = .from(WorldArt.siteBeacon())

        let atlas = SKTextureAtlas(dictionary: images)
        unit = unitNames.map { $0.map { images[$0] != nil ? atlas.textureNamed($0) : SKTexture() } }
        building = buildingNames.map { $0.map { images[$0] != nil ? atlas.textureNamed($0) : SKTexture() } }
        resource = ResourceKind.allCases.map { k in (0..<3).map { atlas.textureNamed("r\(k.rawValue)_\($0)") } }
        boulders = (0..<3).map { atlas.textureNamed("boulder\($0)") }
        for n in fxNames { fx[n] = atlas.textureNamed("fx_" + n) }
        sitePlatform = atlas.textureNamed("site_platform")
        siteBeacon = atlas.textureNamed("site_beacon")
        buildTiles()
    }

    private func buildTiles() {
        var groups: [SKTileGroup] = []
        for t in [Terrain.grass, .dirt, .moss, .rock, .water] {
            for elev in [false, true] {
                var defs: [SKTileDefinition] = []
                for v in 0..<4 {
                    let tex = SKTexture(cgImage: WorldArt.tile(t, variant: v + (elev ? 10 : 0), elevated: elev))
                    tex.filteringMode = .linear
                    defs.append(SKTileDefinition(texture: tex, size: CGSize(width: 64, height: 32)))
                }
                let rule = SKTileGroupRule(adjacency: .adjacencyAll, tileDefinitions: defs)
                let g = SKTileGroup(rules: [rule])
                g.name = "\(t.rawValue)_\(elev)"
                tileGroups[g.name!] = g
                groups.append(g)
            }
        }
        tileSet = SKTileSet(tileGroups: groups, tileSetType: .isometric)
    }

    func group(_ t: Terrain, elevated: Bool) -> SKTileGroup { tileGroups["\(t.rawValue)_\(elevated && t.groundPassable)"]! }
}
