// Usage: swift tools/compare.swift <before-dir> <after-dir> <out-dir>
import AppKit
let a = CommandLine.arguments
let fm = FileManager.default
try? fm.createDirectory(atPath: a[3], withIntermediateDirectories: true)
for f in (try! fm.contentsOfDirectory(atPath: a[1])).sorted() where f.hasSuffix(".jpg") {
    guard let b = NSImage(contentsOfFile: a[1] + "/" + f), let c = NSImage(contentsOfFile: a[2] + "/" + f),
          let bc = b.cgImage(forProposedRect: nil, context: nil, hints: nil), let cc = c.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let w = bc.width, h = bc.height, gap = 24, label = 56
    let ctx = CGContext(data: nil, width: w * 2 + gap, height: h + label, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w * 2 + gap, height: h + label))
    ctx.draw(bc, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cc, in: CGRect(x: w + gap, y: 0, width: w, height: h))
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = ns
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .heavy), .foregroundColor: NSColor.white]
    NSAttributedString(string: "BEFORE (v0.1)", attributes: attrs).draw(at: CGPoint(x: 20, y: h + 12))
    NSAttributedString(string: "AFTER", attributes: attrs).draw(at: CGPoint(x: w + gap + 20, y: h + 12))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])!.write(to: URL(fileURLWithPath: a[3] + "/" + f))
    print("wrote", f)
}
