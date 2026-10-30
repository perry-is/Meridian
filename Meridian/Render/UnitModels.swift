import CoreGraphics
import Foundation
import ImageIO

/// Pre-rendered 3D unit sprites (tools/blender/unit_render.py): eight facings per unit, each with a mask of the
/// model's team-colour markings. Units without renders fall back to the procedural UnitArt drawings.
enum UnitModels {
    static let facingCount = 8

    /// The unit's lit renders and team masks, facing k*45° on screen (0 = right, counter-clockwise), if bundled.
    static func load(_ id: String) -> [(base: CGImage, mask: CGImage)]? {
        var out: [(CGImage, CGImage)] = []
        for k in 0..<facingCount {
            guard let b = image("u3d_\(id)_d\(k)"), let m = image("u3d_\(id)_d\(k)m") else { return nil }
            out.append((b, m))
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

    private static func image(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
