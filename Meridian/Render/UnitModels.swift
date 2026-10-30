import CoreGraphics
import Foundation
import ImageIO

/// Pre-rendered 3D unit sprites (tools/blender/unit_render.py): eight facings x six poses per unit, each with a
/// mask of the model's team-colour markings. Units without renders fall back to the procedural UnitArt drawings.
enum UnitModels {
    static let facingCount = 8
    /// 0 idle, 1-4 walk / wing-beat cycle, 5 attack.
    static let poseCount = 6
    static let idle = 0, walk = 1, attack = 5

    /// The unit's lit renders and team masks as [facing][pose], facing k*45° on screen (0 = right,
    /// counter-clockwise), if bundled.
    static func load(_ id: String) -> [[(base: CGImage, mask: CGImage)]]? {
        var out: [[(CGImage, CGImage)]] = []
        for k in 0..<facingCount {
            var poses: [(CGImage, CGImage)] = []
            for p in 0..<poseCount {
                guard let b = image("u3d_\(id)_d\(k)_\(p)"), let m = image("u3d_\(id)_d\(k)_\(p)m") else { return nil }
                poses.append((b, m))
            }
            out.append(poses)
        }
        return out
    }

    /// Recolours the masked markings with the team colour, keeping the render's own shading.
    static func tinted(_ base: CGImage, mask: CGImage, team: RGB) -> CGImage {
        let w = base.width, h = base.height, r = CGRect(x: 0, y: 0, width: w, height: h)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(base, in: r)
        // Clip masks must be greyscale without alpha.
        let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        g.draw(mask, in: r)
        if let gm = g.makeImage() {
            ctx.saveGState()
            ctx.clip(to: r, mask: gm)
            ctx.setBlendMode(.color)
            ctx.setFillColor(team.cg)
            ctx.fill(r)
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    /// Facing index for a direction given as a scene-space (isometric screen) vector.
    static func facing(_ v: CGPoint) -> Int {
        // Undo the 2:1 squash so the eight facings are even angles on the ground, as rendered.
        let a = atan2(Double(v.y) * 2, Double(v.x))
        return ((Int((a / (.pi / 4)).rounded()) % facingCount) + facingCount) % facingCount
    }

    static func bundled(_ name: String) -> CGImage? { image(name) }

    private static func image(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

/// Pre-rendered 3D buildings (tools/blender/buildings.py), drawn into the same canvas as WorldArt.buildingCanvas,
/// with a team-colour mask and metadata (visual height and light points, in points from the footprint centre).
enum BuildingModels {
    struct Meta: Decodable { let height: CGFloat; let lights: [[CGFloat]] }

    nonisolated(unsafe) private static var metaCache: [String: Meta?] = [:]

    static func meta(_ id: String) -> Meta? {
        if let m = metaCache[id] { return m }
        let m = Bundle.main.url(forResource: "b3d_\(id)", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
        metaCache[id] = m
        return m
    }

    /// The team-tinted render, if this building has a 3D model.
    static func image(_ id: String, team: RGB) -> CGImage? {
        guard meta(id) != nil, let b = UnitModels.bundled("b3d_\(id)"), let m = UnitModels.bundled("b3d_\(id)m") else { return nil }
        return UnitModels.tinted(b, mask: m, team: team)
    }
}
