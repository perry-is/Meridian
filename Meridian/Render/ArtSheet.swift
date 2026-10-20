import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MeridianCore

/// Development helper: renders every unit and building onto one PNG for visual review.
enum ArtSheet {
    static func write(to url: URL) {
        let data = GameData.shared
        let cell: CGFloat = 96
        let cols = 15
        let unitRows = 3, bRows = 3
        let bH: CGFloat = 250
        let W = cell * CGFloat(cols), H = cell * CGFloat(unitRows) + bH * CGFloat(bRows) + 90
        let img = Pen.image(W, H, scale: 1) { p in
            p.fill(p.poly([(0, 0), (W, 0), (W, H), (0, H)]), RGB(0.25, 0.38, 0.24))
            for (fi, f) in Faction.allCases.enumerated() {
                for (k, u) in data.unitIDs(f).enumerated() {
                    let d = data.units[u]
                    let im = UnitArt.render(d, team: TeamColor.rgb(fi % 2))
                    let s = UnitArt.canvasSize(d) * 1.4
                    let x = CGFloat(k) * cell + (cell - s) / 2, y = H - CGFloat(fi + 1) * cell + 8
                    p.ctx.draw(im, in: CGRect(x: x, y: y, width: s, height: s))
                }
                var x: CGFloat = 4
                for b in data.buildingIDs(f) {
                    let d = data.buildings[b]
                    let im = WorldArt.building(d, team: TeamColor.rgb(fi % 2))
                    let c = WorldArt.buildingCanvas(d)
                    let sc: CGFloat = 0.8
                    p.ctx.draw(im, in: CGRect(x: x, y: H - CGFloat(unitRows) * cell - CGFloat(fi + 1) * bH, width: c.w * sc, height: c.h * sc))
                    x += c.w * sc + 6
                }
            }
            var x: CGFloat = 4
            for v in 0..<3 { p.ctx.draw(EnvironmentArt.iron(v), in: CGRect(x: x, y: 4, width: 58, height: 48)); x += 62 }
            for v in 0..<3 { p.ctx.draw(EnvironmentArt.gold(v), in: CGRect(x: x, y: 4, width: 50, height: 54)); x += 56 }
            for v in 0..<3 { p.ctx.draw(EnvironmentArt.tree(v), in: CGRect(x: x, y: 4, width: 48, height: 78)); x += 52 }
            for v in 0..<6 { p.ctx.draw(EnvironmentArt.cliff(v), in: CGRect(x: x, y: 4, width: 62, height: v >= 3 ? 84 : 60)); x += 66 }
            p.ctx.draw(WorldArt.siteBeacon(), in: CGRect(x: x, y: 4, width: 30, height: 60))
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}
