import CoreGraphics

/// Volume helpers for unit art: shapes that read as solid objects lit from the upper left
/// (the same sun as the terrain and buildings), instead of flat outlines.
extension Pen {
    static let ink = RGB(0.05, 0.05, 0.07, 0.92)

    /// Linear gradient fill along an arbitrary axis, then an ink outline.
    func grad(_ path: CGPath, _ c0: RGB, _ c1: RGB, from a: CGPoint, to b: CGPoint, outline: RGB? = Pen.ink, lw: CGFloat = 0.75) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [c0.cg, c1.cg] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        if let o = outline { ctx.addPath(path); ctx.setStrokeColor(o.cg); ctx.setLineWidth(lw); ctx.strokePath() }
    }

    /// Solid lit from the top-left: light upper edge, base colour, darker lower-right.
    func solid(_ path: CGPath, _ c: RGB, outline: RGB? = Pen.ink, lw: CGFloat = 0.75, contrast: CGFloat = 1) {
        let bb = path.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [c.light(0.32 * contrast).cg, c.cg, c.dark(0.38 * contrast).cg] as CFArray, locations: [0, 0.42, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: bb.minX, y: bb.maxY), end: CGPoint(x: bb.minX + bb.width * 0.45, y: bb.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        if let o = outline { ctx.addPath(path); ctx.setStrokeColor(o.cg); ctx.setLineWidth(lw); ctx.strokePath() }
    }

    /// Tapered limb from a (radius ra) to b (radius rb): two tangents plus rounded ends.
    func capsule(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ ra: CGFloat, _ rb: CGFloat, _ c: RGB, outline: RGB? = Pen.ink, lw: CGFloat = 0.7) {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let L = max(0.001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / L, ny = dx / L
        let p = CGMutablePath()
        let ang = atan2(dy, dx)
        p.move(to: CGPoint(x: a.0 + nx * ra, y: a.1 + ny * ra))
        p.addLine(to: CGPoint(x: b.0 + nx * rb, y: b.1 + ny * rb))
        p.addArc(center: CGPoint(x: b.0, y: b.1), radius: rb, startAngle: ang + .pi / 2, endAngle: ang - .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: a.0 - nx * ra, y: a.1 - ny * ra))
        p.addArc(center: CGPoint(x: a.0, y: a.1), radius: ra, startAngle: ang - .pi / 2, endAngle: ang + .pi / 2, clockwise: true)
        p.closeSubpath()
        // Light across the limb (from the side facing up-left).
        let mx = (a.0 + b.0) / 2, my = (a.1 + b.1) / 2
        let r = max(ra, rb)
        let s = ny >= 0 ? 1.0 : -1.0
        grad(p, c.light(0.28), c.dark(0.32), from: CGPoint(x: mx + nx * r * CGFloat(s), y: my + ny * r * CGFloat(s)), to: CGPoint(x: mx - nx * r * CGFloat(s), y: my - ny * r * CGFloat(s)), outline: outline, lw: lw)
    }

    /// Box seen slightly from above: front face plus a lighter top face receding up and to the right.
    func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, depth d: CGFloat, _ c: RGB, top: RGB? = nil, bevel: CGFloat = 0.6) {
        let dx = d * 0.45, dy = d * 0.55
        let tp = poly([(x + bevel, y + h), (x + w - bevel, y + h), (x + w - bevel + dx, y + h + dy), (x + bevel + dx, y + h + dy)])
        solid(tp, top ?? c.light(0.22), contrast: 0.5)
        let side = poly([(x + w, y), (x + w + dx, y + dy), (x + w + dx - bevel * 0.5, y + h + dy), (x + w - bevel, y + h)])
        solid(side, c.dark(0.3), contrast: 0.4)
        solid(roundRectPath(x, y, w, h, bevel), c)
    }

    /// Horizontal metal tube from x0 to x1 (barrels, launchers): lengthwise sheen and an end cap.
    func tube(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: RGB, cap: Bool = true) {
        let p = roundRectPath(x0, y - r, x1 - x0, r * 2, r * 0.5)
        grad(p, c.light(0.35), c.dark(0.45), from: CGPoint(x: x0, y: y + r), to: CGPoint(x: x0, y: y - r))
        line((x0 + r, y + r * 0.45), (x1 - r * 0.6, y + r * 0.45), c.light(0.45).alpha(0.5), max(0.3, r * 0.25))
        if cap { fill(ellipsePath(x1 - r * 0.25, y, r * 0.42, r * 0.85), RGB(0.04, 0.04, 0.05)) }
    }

    /// Shaded ball with an off-centre highlight (helmets, cores, joints, carapace).
    func ball(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: RGB, outline: RGB? = Pen.ink, lw: CGFloat = 0.75, shine: CGFloat = 0.5) {
        let p = ellipsePath(cx, cy, rx, ry)
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [c.light(0.45).cg, c.cg, c.dark(0.45).cg] as CFArray, locations: [0, 0.45, 1])!
        let h = CGPoint(x: cx - rx * 0.35, y: cy + ry * 0.4)
        ctx.drawRadialGradient(g, startCenter: h, startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: max(rx, ry) * 1.15, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        if shine > 0 { fill(ellipsePath(cx - rx * 0.38, cy + ry * 0.42, rx * 0.28, ry * 0.18), RGB(1, 1, 1, 0.45 * shine)) }
        if let o = outline { ctx.addPath(p); ctx.setStrokeColor(o.cg); ctx.setLineWidth(lw); ctx.strokePath() }
    }

    /// Thin engraved panel line with a highlight below it.
    func seam(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ base: RGB) {
        line(a, b, base.dark(0.55).alpha(0.8), 0.45)
        line((a.0, a.1 - 0.45), (b.0, b.1 - 0.45), base.light(0.35).alpha(0.5), 0.35)
    }

    func rivets(_ pts: [(CGFloat, CGFloat)], _ base: RGB) {
        for (x, y) in pts { dot(x, y, 0.42, base.light(0.45)); dot(x + 0.15, y - 0.15, 0.25, base.dark(0.4)) }
    }

    /// Emissive light (visor, cores, lamps): bright centre plus bloom.
    func lamp(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: RGB) {
        glow(cx, cy, r * 3, c.alpha(0.55))
        dot(cx, cy, r, c.light(0.35))
        dot(cx - r * 0.25, cy + r * 0.25, r * 0.4, RGB(1, 1, 1, 0.9))
    }
}
