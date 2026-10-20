import CoreGraphics
import Foundation

/// Tiny drawing DSL over CGContext used by the procedural art generator.
/// Coordinates are in points with origin at bottom-left; images are rendered at `scale` pixels per point.
struct RGB {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t) }
    func light(_ t: CGFloat) -> RGB { mix(RGB(1, 1, 1, a), t) }
    func dark(_ t: CGFloat) -> RGB { mix(RGB(0, 0, 0, a), t) }
    func alpha(_ v: CGFloat) -> RGB { RGB(r, g, b, v) }
}

final class Pen {
    let ctx: CGContext
    let w: CGFloat, h: CGFloat
    init(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) { self.ctx = ctx; self.w = w; self.h = h }

    static func image(_ w: CGFloat, _ h: CGFloat, scale: CGFloat = 2, _ draw: (Pen) -> Void) -> CGImage {
        let pw = max(1, Int(ceil(w * scale))), ph = max(1, Int(ceil(h * scale)))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        draw(Pen(ctx, w, h))
        return ctx.makeImage()!
    }

    // MARK: Paths

    func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        guard let f = pts.first else { return p }
        p.move(to: CGPoint(x: f.0, y: f.1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    func ellipsePath(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    func roundRectPath(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil)
    }

    // MARK: Fills

    /// Fill with a vertical light-to-dark gradient and an outline: the house style for readable sprites.
    func shade(_ path: CGPath, _ c: RGB, outline: RGB? = RGB(0.06, 0.06, 0.08, 0.9), lw: CGFloat = 1.1, top: CGFloat = 0.28, bottom: CGFloat = 0.3) {
        let bb = path.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [c.light(top).cg, c.cg, c.dark(bottom).cg] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: bb.minX, y: bb.maxY), end: CGPoint(x: bb.maxX * 0.3 + bb.minX * 0.7, y: bb.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        if let o = outline {
            ctx.addPath(path); ctx.setStrokeColor(o.cg); ctx.setLineWidth(lw); ctx.strokePath()
        }
    }

    func fill(_ path: CGPath, _ c: RGB) { ctx.addPath(path); ctx.setFillColor(c.cg); ctx.fillPath() }

    func stroke(_ path: CGPath, _ c: RGB, _ lw: CGFloat) {
        ctx.addPath(path); ctx.setStrokeColor(c.cg); ctx.setLineWidth(lw); ctx.strokePath()
    }

    func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: RGB, _ lw: CGFloat) {
        let p = CGMutablePath(); p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1))
        stroke(p, c, lw)
    }

    /// Line with dark outline (for limbs/barrels).
    func limb(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: RGB, _ lw: CGFloat) {
        line(a, b, RGB(0.05, 0.05, 0.07, 0.9), lw + 1.6)
        line(a, b, c, lw)
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: RGB, outline: Bool = true) {
        shade(ellipsePath(cx, cy, rx, ry), c, outline: outline ? RGB(0.05, 0.05, 0.07, 0.9) : nil)
    }

    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RGB, r: CGFloat = 1.5) {
        shade(roundRectPath(x, y, w, h, r), c)
    }

    func shape(_ pts: [(CGFloat, CGFloat)], _ c: RGB) { shade(poly(pts), c) }

    func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: RGB) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [c.cg, c.alpha(c.a * 0.45).cg, c.alpha(0).cg] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
    }

    func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: RGB) { fill(ellipsePath(cx, cy, r, r), c) }

    func highlight(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        fill(ellipsePath(cx, cy, rx, ry), RGB(1, 1, 1, 0.35))
    }
}

extension Pen {
    /// Post-process lighting for sprites: warm rim light on edges facing the upper-left sun and a cool
    /// shade band on the lower-right, derived from the sprite's own silhouette.
    static func lit(_ img: CGImage, scale: CGFloat = 2, offset: CGFloat = 1.6, light: RGB = RGB(1.0, 0.88, 0.62), shade: RGB = RGB(0.10, 0.08, 0.28)) -> CGImage {
        let w = img.width, h = img.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func layer(_ color: RGB, _ dx: CGFloat, _ dy: CGFloat) -> CGImage {
            let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let r = CGRect(x: 0, y: 0, width: w, height: h)
            c.draw(img, in: r)
            c.setBlendMode(.sourceIn); c.setFillColor(color.cg); c.fill(r)
            c.setBlendMode(.destinationOut)
            c.draw(img, in: r.offsetBy(dx: dx * scale, dy: dy * scale))
            return c.makeImage()!
        }
        let rim = layer(light, offset, -offset)        // edges whose up-left neighbour is empty
        let dark = layer(shade, -offset, offset)       // edges whose down-right neighbour is empty
        let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        out.draw(img, in: r)
        out.setAlpha(0.42); out.setBlendMode(.sourceAtop); out.draw(dark, in: r)
        out.setAlpha(0.6); out.setBlendMode(.screen); out.draw(rim, in: r)
        return out.makeImage()!
    }
}

/// Deterministic hash noise for textures.
@inline(__always) func hnoise(_ x: Int, _ y: Int, _ s: Int) -> CGFloat {
    var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ s &* 1442695041)
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return CGFloat(h & 0xFFFF) / 65535
}
