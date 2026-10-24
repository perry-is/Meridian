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

    /// Rig review: every unit of a faction, large, in four poses (rest; aimed up / tool raised;
    /// aimed down / strike; gait frame with recoil). The upper part rotates about its pivot as in game.
    static func writePoses(_ f: Faction, to url: URL) {
        let data = GameData.shared
        let ids = data.unitIDs(f)
        let cell: CGFloat = 150, cols = 4
        let W = cell * CGFloat(cols), H = cell * CGFloat(ids.count)
        let img = Pen.image(W, H, scale: 1) { p in
            p.fill(p.poly([(0, 0), (W, 0), (W, H), (0, H)]), RGB(0.27, 0.40, 0.25))
            for (row, u) in ids.enumerated() {
                let d = data.units[u], r = UnitArt.rig(d.id)
                let S = UnitArt.canvasSize(d), sc = (cell - 10) / S
                let poses: [(Int, CGFloat, CGFloat, String)] = r.kind == .tool || r.kind == .beamTool || r.kind == .biteTool
                    ? [(0, 0, 0, ""), (2, 0.95, 0, "wood"), (4, -0.55, 0, "ore"), (6, 0.4, 0, "build")]
                    : [(0, r.rest, 0, ""), (2, r.aimUp, 0, ""), (4, -r.aimDown, 0, ""), (6, r.rest, -r.kick, "")]
                for (c, pose) in poses.enumerated() {
                    let ox = CGFloat(c) * cell + 5, oy = H - CGFloat(row + 1) * cell + 5
                    p.ctx.draw(UnitArt.renderBase(d, team: TeamColor.rgb(0), frame: pose.0), in: CGRect(x: ox, y: oy, width: S * sc, height: S * sc))
                    if let up = UnitArt.renderUpper(d, team: TeamColor.rgb(0), variant: pose.3) {
                        let k = S / 40 * sc
                        let px = ox + r.pivot.x * k, py = oy + r.pivot.y * k
                        p.ctx.saveGState()
                        p.ctx.translateBy(x: px + pose.2 * k * cos(pose.1), y: py + pose.2 * k * sin(pose.1))
                        p.ctx.rotate(by: pose.1)
                        p.ctx.draw(up, in: CGRect(x: -r.pivot.x * k, y: -r.pivot.y * k, width: S * sc, height: S * sc))
                        p.ctx.restoreGState()
                        p.fill(p.ellipsePath(px, py, 2, 2), RGB(1, 0, 1, 0.8))
                    }
                }
            }
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }

    /// Building review: one faction's eight structures, large, on a terrain-coloured ground.
    static func writeBuildings(_ f: Faction, to url: URL) {
        let data = GameData.shared
        let ids = data.buildingIDs(f)
        let cols = 4, cellW: CGFloat = 300, cellH: CGFloat = 300
        let W = cellW * CGFloat(cols), H = cellH * CGFloat((ids.count + cols - 1) / cols)
        let img = Pen.image(W, H, scale: 1) { p in
            p.fill(p.poly([(0, 0), (W, 0), (W, H), (0, H)]), RGB(0.27, 0.40, 0.25))
            for (k, b) in ids.enumerated() {
                let d = data.buildings[b]
                let im = WorldArt.building(d, team: TeamColor.rgb(0))
                let c = WorldArt.buildingCanvas(d)
                let sc = min((cellW - 20) / c.w, (cellH - 20) / c.h) * 1.0
                let x = CGFloat(k % cols) * cellW + (cellW - c.w * sc) / 2
                let y = H - CGFloat(k / cols + 1) * cellH + 10
                p.ctx.draw(im, in: CGRect(x: x, y: y, width: c.w * sc, height: c.h * sc))
            }
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}

extension ArtSheet {
    /// Portrait review: every unit's face (top), then a few units through look / blink / talk poses.
    static func writePortraits(to url: URL) {
        let data = GameData.shared
        let cell: CGFloat = 120, cols = 15
        let poses: [(String, PortraitArt.Pose)] = [
            ("rest", PortraitArt.Pose()),
            ("look left", PortraitArt.Pose(look: CGPoint(x: -1, y: 0.2))),
            ("look right", PortraitArt.Pose(look: CGPoint(x: 1, y: -0.3))),
            ("blink", PortraitArt.Pose(blink: 1)),
            ("talk", PortraitArt.Pose(mouth: 0.55, t: 0.3)),
            ("talk wide", PortraitArt.Pose(look: CGPoint(x: 0.4, y: 0.2), mouth: 1, t: 1.1)),
        ]
        let samples = ["h_ranger", "h_kestrel", "m_arc", "m_bulwark", "a_mantis", "a_colossus"]
        let W = cell * CGFloat(cols), H = cell * 3 + cell * CGFloat(samples.count)
        func face(_ p: Pen, _ id: String, _ x: CGFloat, _ y: CGFloat, _ pose: PortraitArt.Pose) {
            let s = cell - 8
            let r = CGRect(x: x + 4, y: y + 4, width: s, height: s)
            let fac = id.first == "m" ? RGB(0.10, 0.20, 0.26) : (id.first == "a" ? RGB(0.18, 0.12, 0.22) : RGB(0.16, 0.18, 0.12))
            p.grad(p.roundRectPath(r.minX, r.minY, s, s, 8), fac.light(0.15), fac.dark(0.5), from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY), outline: nil)
            p.ctx.saveGState()
            p.ctx.addPath(p.roundRectPath(r.minX, r.minY, s, s, 8)); p.ctx.clip()
            p.ctx.translateBy(x: r.minX, y: r.minY); p.ctx.scaleBy(x: s / 40, y: s / 40)
            PortraitArt.draw(Pen(p.ctx, 40, 40), unit: id, team: TeamColor.rgb(0), pose: pose)
            p.ctx.restoreGState()
            p.stroke(p.roundRectPath(r.minX, r.minY, s, s, 8), TeamColor.rgb(0).alpha(0.8), 1.5)
        }
        let img = Pen.image(W, H, scale: 2) { p in
            p.fill(p.poly([(0, 0), (W, 0), (W, H), (0, H)]), RGB(0.06, 0.06, 0.08))
            for (fi, f) in Faction.allCases.enumerated() {
                for (k, u) in data.unitIDs(f).enumerated() {
                    face(p, data.units[u].id, CGFloat(k) * cell, H - CGFloat(fi + 1) * cell, PortraitArt.Pose(look: CGPoint(x: 0.25, y: 0)))
                }
            }
            for (si, id) in samples.enumerated() {
                for (k, pose) in poses.enumerated() {
                    face(p, id, CGFloat(k) * cell, H - 3 * cell - CGFloat(si + 1) * cell, pose.1)
                }
            }
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}

extension ArtSheet {
    /// Alpha bounds of a unit in its 40×40 design grid (origin bottom-left).
    static func designBounds(_ d: UnitDef) -> CGRect {
        let img = UnitArt.render(d, team: TeamColor.rgb(0))
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var x0 = w, x1 = 0, y0 = h, y1 = 0
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 40 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        let k = 40 / CGFloat(w)
        // Memory rows run top-down.
        return CGRect(x: CGFloat(x0) * k, y: CGFloat(h - 1 - y1) * k, width: CGFloat(x1 - x0) * k, height: CGFloat(y1 - y0) * k)
    }

    /// Prototype: close-ups of the actual units (vector, drawn straight from the unit art).
    static func writeCloseups(to url: URL) {
        let data = GameData.shared
        let cell: CGFloat = 120, cols = 15
        let W = cell * CGFloat(cols), H = cell * 3
        let img = Pen.image(W, H, scale: 2) { p in
            p.fill(p.poly([(0, 0), (W, 0), (W, H), (0, H)]), RGB(0.06, 0.06, 0.08))
            for (fi, f) in Faction.allCases.enumerated() {
                for (k, u) in data.unitIDs(f).enumerated() {
                    let d = data.units[u]
                    let b = designBounds(d)
                    let side = max(b.height * 0.92, b.width * 0.62)
                    let focus = CGRect(x: b.maxX - side + side * 0.04, y: b.maxY - side + side * 0.02, width: side, height: side)
                    let s = cell - 8
                    let r = CGRect(x: CGFloat(k) * cell + 4, y: H - CGFloat(fi + 1) * cell + 4, width: s, height: s)
                    let bg = fi == 1 ? RGB(0.10, 0.20, 0.26) : (fi == 2 ? RGB(0.18, 0.12, 0.22) : RGB(0.16, 0.18, 0.12))
                    p.grad(p.roundRectPath(r.minX, r.minY, s, s, 8), bg.light(0.15), bg.dark(0.5), from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY), outline: nil)
                    p.ctx.saveGState()
                    p.ctx.addPath(p.roundRectPath(r.minX, r.minY, s, s, 8)); p.ctx.clip()
                    p.ctx.translateBy(x: r.minX, y: r.minY); p.ctx.scaleBy(x: s / focus.width, y: s / focus.height)
                    p.ctx.translateBy(x: -focus.minX, y: -focus.minY)
                    UnitArt.phase = 0
                    let pen = Pen(p.ctx, 40, 40)
                    UnitArt.base(d.id, pen, TeamColor.rgb(0))
                    UnitArt.upper(d.id, "", pen, TeamColor.rgb(0))
                    p.ctx.restoreGState()
                    p.stroke(p.roundRectPath(r.minX, r.minY, s, s, 8), TeamColor.rgb(0).alpha(0.8), 1.5)
                }
            }
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}
