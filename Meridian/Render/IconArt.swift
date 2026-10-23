import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The app icon, drawn in code like everything else: a floating island of the battlefield at dusk,
/// a capture-site ring in the three faction colours, and a beacon spire on the meridian line of light.
enum IconArt {
    static func render(size S: CGFloat = 1024) -> CGImage {
        Pen.image(S, S, scale: 1) { p in
            let k = S / 1024
            p.ctx.scaleBy(x: k, y: k)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            // Dusk sky.
            let sky = CGGradient(colorsSpace: cs, colors: [RGB(0.14, 0.26, 0.36).cg, RGB(0.05, 0.09, 0.16).cg, RGB(0.02, 0.03, 0.06).cg] as CFArray, locations: [0, 0.5, 1])!
            p.ctx.drawRadialGradient(sky, startCenter: CGPoint(x: 512, y: 520), startRadius: 0, endCenter: CGPoint(x: 512, y: 520), endRadius: 760, options: [.drawsAfterEndLocation])
            for i in 0..<60 {
                let x = hnoise(i, 1, 9) * 1024, y = 560 + hnoise(i, 2, 9) * 464
                p.dot(x, y, 1.2 + hnoise(i, 3, 9) * 2.2, RGB(1, 1, 1, 0.25 + hnoise(i, 4, 9) * 0.5))
            }
            // The meridian: a beam of light through the whole icon.
            p.glow(512, 520, 420, RGB(0.35, 0.9, 1, 0.22))
            p.fill(p.roundRectPath(504, 40, 16, 944, 8), RGB(0.7, 0.95, 1, 0.25))
            p.fill(p.roundRectPath(509, 40, 6, 944, 3), RGB(1, 1, 1, 0.85))
            // Floating island.
            let cx: CGFloat = 512, cy: CGFloat = 400, hw: CGFloat = 340, hh: CGFloat = 170, depth: CGFloat = 92
            let top = p.poly([(cx - hw, cy), (cx, cy + hh), (cx + hw, cy), (cx, cy - hh)])
            let left = p.poly([(cx - hw, cy), (cx, cy - hh), (cx, cy - hh - depth), (cx - hw + 40, cy - depth * 0.9)])
            let right = p.poly([(cx, cy - hh), (cx + hw, cy), (cx + hw - 40, cy - depth * 0.9), (cx, cy - hh - depth)])
            p.grad(left, RGB(0.55, 0.40, 0.27), RGB(0.30, 0.20, 0.14), from: CGPoint(x: cx - hw, y: cy), to: CGPoint(x: cx, y: cy - hh - depth), outline: RGB(0.05, 0.04, 0.05), lw: 6)
            p.grad(right, RGB(0.36, 0.25, 0.17), RGB(0.18, 0.12, 0.09), from: CGPoint(x: cx, y: cy - hh), to: CGPoint(x: cx + hw, y: cy - depth), outline: RGB(0.05, 0.04, 0.05), lw: 6)
            for k in 0..<5 { p.line((cx - hw + 60 + CGFloat(k) * 58, cy - 40 - CGFloat(k) * 28), (cx - hw + 80 + CGFloat(k) * 58, cy - 80 - CGFloat(k) * 28), RGB(0.2, 0.13, 0.09, 0.6), 4) }   // strata
            p.grad(top, RGB(0.42, 0.62, 0.30), RGB(0.18, 0.38, 0.20), from: CGPoint(x: cx - hw * 0.5, y: cy + hh), to: CGPoint(x: cx + hw * 0.6, y: cy - hh), outline: RGB(0.05, 0.06, 0.05), lw: 6)
            p.line((cx - hw, cy), (cx, cy + hh), RGB(0.75, 0.95, 0.55, 0.7), 4)
            // Capture-site ring in faction colours.
            let rx: CGFloat = 220, ry: CGFloat = 110
            p.fill(p.ellipsePath(cx, cy, rx, ry), RGB(0.08, 0.12, 0.12, 0.55))
            for (i, c) in [RGB(0.95, 0.72, 0.3), RGB(0.35, 0.9, 1.0), RGB(0.6, 1.0, 0.4)].enumerated() {
                let a0 = CGFloat(i) * 2 * .pi / 3 + 0.25, a1 = a0 + 2 * .pi / 3 - 0.5
                let arc = CGMutablePath()
                arc.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: false, transform: CGAffineTransform(a: rx, b: 0, c: 0, d: ry, tx: cx, ty: cy))
                p.stroke(arc, c.alpha(0.35), 34)
                p.stroke(arc, c, 16)
                p.stroke(arc, c.light(0.5), 5)
            }
            // Gold crystals on the near rim.
            for (x, y, s) in [(300.0, 330.0, 1.0), (720.0, 336.0, 0.85)] as [(CGFloat, CGFloat, CGFloat)] {
                for j in 0..<3 {
                    let dx = CGFloat(j - 1) * 22 * s, h = (90 - CGFloat(abs(j - 1)) * 28) * s
                    let shard = p.poly([(x + dx - 14 * s, y), (x + dx - 4 * s, y + h), (x + dx + 10 * s, y + h * 0.82), (x + dx + 14 * s, y)])
                    p.grad(shard, RGB(1, 0.9, 0.5), RGB(0.85, 0.5, 0.12), from: CGPoint(x: x + dx, y: y + h), to: CGPoint(x: x + dx, y: y), outline: RGB(0.25, 0.12, 0.02), lw: 4)
                }
                p.glow(x, y + 40 * s, 70 * s, RGB(1, 0.8, 0.3, 0.45))
            }
            // Beacon spire.
            let bw: CGFloat = 62, bh: CGFloat = 400, by = cy - 10
            let leftF = p.poly([(cx - bw, by), (cx - bw * 0.5, by + bh), (cx, by + bh + 46), (cx, by - 26)])
            let rightF = p.poly([(cx, by - 26), (cx, by + bh + 46), (cx + bw * 0.5, by + bh), (cx + bw, by)])
            p.grad(leftF, RGB(0.45, 0.5, 0.62), RGB(0.2, 0.22, 0.3), from: CGPoint(x: cx - bw, y: by + bh), to: CGPoint(x: cx, y: by), outline: RGB(0.03, 0.04, 0.06), lw: 7)
            p.grad(rightF, RGB(0.2, 0.22, 0.3), RGB(0.08, 0.09, 0.13), from: CGPoint(x: cx, y: by + bh), to: CGPoint(x: cx + bw, y: by), outline: RGB(0.03, 0.04, 0.06), lw: 7)
            p.line((cx, by + 10), (cx, by + bh - 10), RGB(0.35, 0.95, 1, 0.45), 16)
            p.line((cx, by + 10), (cx, by + bh - 10), RGB(0.8, 1, 1, 1), 5)
            p.line((cx - bw * 0.5, by + bh), (cx, by + bh + 46), RGB(0.8, 0.9, 1, 0.7), 4)
            // Orb.
            let oy = by + bh + 120
            p.glow(cx, oy, 190, RGB(0.4, 0.95, 1, 0.75))
            p.ball(cx, oy, 50, 50, RGB(0.55, 0.97, 1), outline: RGB(0.05, 0.2, 0.25), lw: 5, shine: 1)
            p.dot(cx - 14, oy + 16, 14, RGB(1, 1, 1, 0.95))
            let ring = CGMutablePath()
            ring.addEllipse(in: CGRect(x: cx - 120, y: oy - 26, width: 240, height: 52))
            p.stroke(ring, RGB(0.6, 0.95, 1, 0.85), 7)
        }
    }

    static func write(to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, render(), nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}
