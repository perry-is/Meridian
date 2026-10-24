import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MeridianCore

/// Development tools for layered portraits (run from the macOS build):
///  - `--portrait-template <file.png>`        the artist's alignment template;
///  - `--portrait-fixtures <dir>`             stand-in layer sets for the pilot units, cut from the Swift-drawn
///                                            portraits (exercise every code path until painted art arrives);
///  - `--validate-portraits <out-dir> [dir]`  checks every unit with layers (in the app, or in a folder of new
///                                            artwork) and writes original-vs-painted comparison sheets.
enum PortraitPipeline {
    static let master = 1024
    static let pilots = ["m_arc", "a_colossus"]

    // MARK: Shared helpers

    static func writePNG(_ img: CGImage, _ url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
    }

    static func context(_ w: Int, _ h: Int) -> CGContext {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setLineJoin(.round); c.setLineCap(.round); c.interpolationQuality = .high
        return c
    }

    /// Grid → master pixels for a canvas that includes the overscan margin.
    static func g2p(_ g: CGFloat) -> CGFloat { (g + 20 * (LayeredPortrait.overscan - 1)) / (40 * LayeredPortrait.overscan) * CGFloat(master) }

    /// Renders the Swift-drawn portrait onto a master canvas that includes the overscan margin.
    static func render(_ id: String, _ pose: PortraitArt.Pose, team: RGB, hidePupils: Bool = false) -> CGImage {
        let c = context(master, master)
        let k = CGFloat(master) / (40 * LayeredPortrait.overscan)
        c.scaleBy(x: k, y: k); c.translateBy(x: 20 * (LayeredPortrait.overscan - 1), y: 20 * (LayeredPortrait.overscan - 1))
        PortraitArt.hidePupils = hidePupils
        PortraitArt.draw(Pen(c, 40, 40), unit: id, team: team, pose: pose)
        PortraitArt.hidePupils = false
        return c.makeImage()!
    }

    /// Draws on a transparent master canvas in grid coordinates.
    static func draw(_ body: (Pen) -> Void) -> CGImage {
        let c = context(master, master)
        let k = CGFloat(master) / (40 * LayeredPortrait.overscan)
        c.scaleBy(x: k, y: k); c.translateBy(x: 20 * (LayeredPortrait.overscan - 1), y: 20 * (LayeredPortrait.overscan - 1))
        body(Pen(c, 40, 40))
        return c.makeImage()!
    }

    /// Cuts `img` to a shape (grid coordinates): the patch every state of a feature shares.
    static func patch(_ img: CGImage, _ shape: CGPath) -> CGImage {
        let c = context(master, master)
        let k = CGFloat(master) / (40 * LayeredPortrait.overscan), o = 20 * (LayeredPortrait.overscan - 1)
        c.scaleBy(x: k, y: k); c.translateBy(x: o, y: o)
        c.addPath(shape); c.clip()
        c.translateBy(x: -o, y: -o); c.scaleBy(x: 1 / k, y: 1 / k)
        c.draw(img, in: CGRect(x: 0, y: 0, width: master, height: master))
        return c.makeImage()!
    }

    struct Bitmap {
        let w: Int, h: Int
        let px: [UInt8]
        init(_ img: CGImage) {
            w = img.width; h = img.height
            let c = PortraitPipeline.context(w, h)
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            px = Array(UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
        }
        @inline(__always) func a(_ i: Int) -> Int { Int(px[i * 4 + 3]) }
        /// Colour distance to another bitmap at pixel i (0…255 per channel, mean), compared as straight colour.
        func diff(_ o: Bitmap, _ i: Int) -> Int {
            let a1 = max(1, a(i)), a2 = max(1, o.a(i))
            var s = 0
            for ch in 0..<3 { s += abs(Int(px[i * 4 + ch]) * 255 / a1 - Int(o.px[i * 4 + ch]) * 255 / a2) }
            return s / 3
        }
    }

    /// Team layer: what the team colour adds, isolated by rendering with black and white team colours.
    static func teamLayer(_ id: String, _ pose: PortraitArt.Pose) -> CGImage? {
        let k = Bitmap(render(id, pose, team: RGB(0, 0, 0))), w = Bitmap(render(id, pose, team: RGB(1, 1, 1)))
        var out = [UInt8](repeating: 0, count: k.px.count)
        var any = false
        for i in 0..<(k.w * k.h) {
            let d = w.diff(k, i) * 3
            guard d > 6 else { continue }
            any = true
            let a = min(255, d)
            for ch in 0..<3 { out[i * 4 + ch] = UInt8(min(255, Int(w.px[i * 4 + ch]) * a / 255)) }
            out[i * 4 + 3] = UInt8(a)
        }
        guard any else { return nil }
        let c = context(k.w, k.h)
        out.withUnsafeBytes { memcpy(c.data!, $0.baseAddress!, out.count) }
        return c.makeImage()
    }

    // MARK: Template

    static func writeTemplate(to url: URL) {
        let S = CGFloat(master)
        let c = context(master, master)
        c.setFillColor(RGB(0.10, 0.11, 0.13).cg); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
        // Grid every 64 px.
        c.setStrokeColor(RGB(1, 1, 1, 0.07).cg); c.setLineWidth(1)
        for i in stride(from: 0, through: S, by: 64) { c.strokeLineSegments(between: [CGPoint(x: i, y: 0), CGPoint(x: i, y: S), CGPoint(x: 0, y: i), CGPoint(x: S, y: i)]) }
        // Overscan margin: may be cropped by idle motion.
        let m = S * (1 - 1 / LayeredPortrait.overscan) / 2
        c.setFillColor(RGB(0.9, 0.25, 0.2, 0.28).cg)
        c.fill([CGRect(x: 0, y: 0, width: S, height: m), CGRect(x: 0, y: S - m, width: S, height: m), CGRect(x: 0, y: 0, width: m, height: S), CGRect(x: S - m, y: 0, width: m, height: S)])
        // Chamfered corners of the portrait frame (cut 9 pt of 78 pt).
        let v = S - 2 * m, cut = v * 9 / 78
        c.setFillColor(RGB(0.9, 0.25, 0.2, 0.45).cg)
        for (x, y, dx, dy) in [(m, m, 1.0, 1.0), (S - m, m, -1.0, 1.0), (m, S - m, 1.0, -1.0), (S - m, S - m, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            c.beginPath(); c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + cut * dx, y: y)); c.addLine(to: CGPoint(x: x, y: y + cut * dy)); c.closePath(); c.fillPath()
        }
        // Speaking light (top right): keep key detail out.
        c.setFillColor(RGB(0.4, 1, 0.5, 0.25).cg); c.fill(CGRect(x: S - m - v * 0.16, y: S - m - v * 0.16, width: v * 0.16, height: v * 0.16))
        // Feature bands (from the top): eyes 28–48 %, mouth 55–78 %.
        func band(_ top: CGFloat, _ bottom: CGFloat, _ col: RGB) {
            c.setFillColor(col.cg); c.fill(CGRect(x: m, y: S * (1 - bottom), width: v, height: S * (bottom - top)))
        }
        band(0.28, 0.48, RGB(0.35, 0.8, 1, 0.12)); band(0.55, 0.78, RGB(1, 0.75, 0.3, 0.12))
        // Centre lines and visible frame.
        c.setStrokeColor(RGB(1, 1, 1, 0.35).cg); c.setLineWidth(2)
        c.strokeLineSegments(between: [CGPoint(x: S / 2, y: 0), CGPoint(x: S / 2, y: S), CGPoint(x: 0, y: S / 2), CGPoint(x: S, y: S / 2)])
        c.setStrokeColor(RGB(1, 1, 1, 0.8).cg); c.stroke(CGRect(x: m, y: m, width: v, height: v), width: 3)
        func label(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 22) {
            let attr = [kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil), kCTForegroundColorAttributeName: RGB(1, 1, 1, 0.85).cg] as [CFString: Any]
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attr as CFDictionary))
            c.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, c)
        }
        label("MERIDIAN PORTRAIT TEMPLATE  1024 × 1024  (master)", m + 16, S - m - 40, 24)
        label("Red margin: may be cropped by idle sway. Red corners: cut by the frame.", m + 16, S - m - 72, 18)
        label("Green box: speaking light. Keep key detail out.", m + 16, S - m - 98, 18)
        label("EYES band 28–48% from top", m + 16, S * 0.52 + 8, 20)
        label("MOUTH / JAW band 55–78% from top", m + 16, S * 0.22 + 8, 20)
        label("Shown at 66–78 pt (198–234 px on iPhone): check legibility at that size.", m + 16, m + 20, 18)
        writePNG(c.makeImage()!, url)
        print("wrote \(url.path)")
    }

    // MARK: Fixtures (stand-ins cut from the Swift-drawn portraits)

    static func writeFixtures(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let neutral = PortraitArt.Pose()
        let black = RGB(0, 0, 0)
        func save(_ id: String, _ name: String, _ img: CGImage?) { if let i = img { writePNG(i, dir.appendingPathComponent("\(id)_\(name).png")) } }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil) }

        // Arc Sentry: the sensor sphere's lens is the eye; speech lights a glow and the vox strip.
        do {
            let id = "m_arc", eye = circle(20, 25.5, 7.0)
            save(id, "base", render(id, neutral, team: black))
            save(id, "team", teamLayer(id, neutral))
            save(id, "eyes_open", patch(render(id, neutral, team: black, hidePupils: true), eye))
            save(id, "eyes_half", patch(render(id, PortraitArt.Pose(blink: 0.5), team: black, hidePupils: true), eye))
            save(id, "eyes_closed", patch(render(id, PortraitArt.Pose(blink: 1), team: black), eye))
            save(id, "pupils", draw { p in PortraitArt.lensIris(p, 20, 25.5, 6.2, flare: 1, color: UnitArt.cyan) })
            save(id, "eyes_mask", draw { p in p.fill(circle(20, 25.5, 6.2), RGB(1, 1, 1)) })
            save(id, "fx_speech", draw { p in
                p.glow(20, 25, 15, UnitArt.cyan.alpha(0.5))
                for k in 0..<3 {
                    let a = CGFloat(k) * 2.1 + 0.4
                    var pts: [(CGFloat, CGFloat)] = []
                    for s in 0..<5 { let r = 11.5 + CGFloat(s) * 1.4; let j = (CGFloat(PortraitArt.hash(s + k * 5, 3)) - 0.5) * 0.3; pts.append((20 + cos(a + j) * r, 25 + sin(a + j) * r)) }
                    for s in 0..<4 { p.line(pts[s], pts[s + 1], UnitArt.cyan.light(0.4), 0.45) }
                }
            })
            save(id, "fx_vox", draw { p in for k in 0..<4 { p.fill(p.roundRectPath(3 + CGFloat(k) * 1.3, 4, 0.8, 2, 0.3), UnitArt.cyan) } })
            let json = """
            {
              "eyes": { "pupilTravel": [72, 56], "halfAt": 0.25, "closedAt": 0.6 },
              "fx": [
                { "layer": "fx_speech", "blend": "add", "driver": "speech", "min": 0, "max": 0.9 },
                { "layer": "fx_vox", "blend": "add", "driver": "speech", "min": 0.1, "max": 1 }
              ],
              "motion": { "sway": 0.6, "breathe": 0.5, "lookShift": 1 }
            }
            """
            try? json.write(to: dir.appendingPathComponent("\(id)_portrait.json"), atomically: true, encoding: .utf8)
        }

        // Colossus: one bead eye under a brow, a jaw that opens in three steps.
        do {
            let id = "a_colossus", eye = circle(27.6, 19.2, 3.0)
            let jaw = CGPath(rect: CGRect(x: 9.5, y: -2, width: 33, height: 17.5), transform: nil)
            save(id, "base", render(id, neutral, team: black))
            save(id, "team", teamLayer(id, neutral))
            save(id, "eyes_open", patch(render(id, neutral, team: black, hidePupils: true), eye))
            save(id, "eyes_half", patch(render(id, PortraitArt.Pose(blink: 0.5), team: black, hidePupils: true), eye))
            save(id, "eyes_closed", patch(render(id, PortraitArt.Pose(blink: 1), team: black), eye))
            save(id, "pupils", draw { p in PortraitArt.beadIris(p, 27.6, 19.2, 2.1, glow: UnitArt.bio) })
            save(id, "eyes_mask", draw { p in p.fill(p.ellipsePath(27.6, 19.2, 2.1, 1.89), RGB(1, 1, 1)) })
            save(id, "mouth_closed", patch(render(id, neutral, team: black), jaw))
            save(id, "mouth_open1", patch(render(id, PortraitArt.Pose(mouth: 0.5), team: black), jaw))
            save(id, "mouth_open2", patch(render(id, PortraitArt.Pose(mouth: 1), team: black), jaw))
            save(id, "fx_eyeglow", draw { p in p.glow(27.6, 19.2, 6, UnitArt.bio.alpha(0.7)) })
            let json = """
            {
              "eyes": { "pupilTravel": [18, 11], "halfAt": 0.25, "closedAt": 0.6 },
              "mouth": { "thresholds": [0.15, 0.6] },
              "fx": [ { "layer": "fx_eyeglow", "blend": "add", "driver": "pulse", "rate": 0.35, "min": 0.15, "max": 0.55 } ],
              "motion": { "sway": 1, "breathe": 1, "lookShift": 1 }
            }
            """
            try? json.write(to: dir.appendingPathComponent("\(id)_portrait.json"), atomically: true, encoding: .utf8)
        }
        print("wrote fixtures to \(dir.path)")
    }

    // MARK: Validation

    struct Report { var lines: [String] = []; var fails = 0; var warns = 0
        mutating func pass(_ s: String) { lines.append("  PASS  " + s) }
        mutating func warn(_ s: String) { lines.append("  WARN  " + s); warns += 1 }
        mutating func fail(_ s: String) { lines.append("  FAIL  " + s); fails += 1 }
    }

    static let layerNames = ["base", "eyes_open", "eyes_half", "eyes_closed", "pupils", "eyes_mask", "mouth_closed", "mouth_open1", "mouth_open2", "team"]

    static func validate(out: URL, folder: URL?) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let source: LayeredPortrait.Source = folder.map { .folder($0) } ?? .bundle
        let ids = GameData.shared.units.map(\.id).filter { LayeredPortrait.hasLayers($0, in: source) }
        if ids.isEmpty { print("No units with portrait layers found in \(folder?.path ?? "the app bundle")."); return }
        var all: [String] = []
        for id in ids {
            var r = Report()
            r.lines.append("\(id)")
            check(id, source, &r)
            r.lines.append("  → \(r.fails == 0 ? (r.warns == 0 ? "OK" : "OK with \(r.warns) warning(s)") : "\(r.fails) problem(s)")")
            all += r.lines
            compareSheet(id, source, out.appendingPathComponent("\(id)_compare.png"))
        }
        let text = all.joined(separator: "\n")
        print(text)
        try? text.write(to: out.appendingPathComponent("portrait_report.txt"), atomically: true, encoding: .utf8)
    }

    static func check(_ id: String, _ source: LayeredPortrait.Source, _ r: inout Report) {
        var imgs: [String: CGImage] = [:]
        for n in layerNames { if let u = source.url("\(id)_\(n)", "png"), let i = LayeredPortrait.decode(u, nil) { imgs[n] = i } }
        guard let lp = LayeredPortrait.load(id, from: source, pixels: nil) else { r.fail("base layer missing or unreadable"); return }
        for f in lp.spec.fx ?? [] { if let u = source.url("\(id)_\(f.layer)", "png"), let i = LayeredPortrait.decode(u, nil) { imgs[f.layer] = i } else { r.fail("fx layer \(f.layer) listed in JSON but missing") } }
        if source.url("\(id)_portrait", "json") == nil { r.warn("no \(id)_portrait.json: defaults used (no pupil travel, standard thresholds)") }

        // 1. Canvas.
        let base = imgs["base"]!
        let sizes = Set(imgs.values.map { "\($0.width)x\($0.height)" })
        if sizes.count == 1 { r.pass("all \(imgs.count) layers share a \(base.width)×\(base.height) canvas") } else { r.fail("layers differ in size: \(sizes.sorted().joined(separator: ", "))") }
        if base.width != base.height { r.fail("canvas is not square") }
        if base.width < 768 { r.fail("master is \(base.width) px; supply at least 768 (1024 recommended)") }
        guard sizes.count == 1 else { return }

        let bm = imgs.mapValues(Bitmap.init)
        let b = bm["base"]!, n = b.w * b.h
        // 2. Base opaque.
        let opaque = (0..<n).filter { b.a($0) >= 250 }.count
        if Double(opaque) / Double(n) > 0.995 { r.pass("base is opaque edge to edge") } else { r.fail(String(format: "base is only %.1f%% opaque; it must fill the whole canvas", Double(opaque) / Double(n) * 100)) }

        // 3. Feature states share one footprint (no ghosting) and the neutral state matches the base.
        var footprints: [String: [Bool]] = [:]
        for (group, states) in [("eyes", ["eyes_open", "eyes_half", "eyes_closed"]), ("mouth", ["mouth_closed", "mouth_open1", "mouth_open2"])] {
            let present = states.filter { bm[$0] != nil }
            guard !present.isEmpty else { r.lines.append("  ----  no \(group) layers"); continue }
            let ref = bm[present[0]]!
            var foot = [Bool](repeating: false, count: n), area = 0
            for i in 0..<n where ref.a(i) >= 128 { foot[i] = true; area += 1 }
            footprints[group] = foot
            if area == 0 { r.fail("\(present[0]) is empty"); continue }
            for s in present.dropFirst() {
                let o = bm[s]!
                var bad = 0
                for i in 0..<n where abs(o.a(i) - ref.a(i)) > 24 && (o.a(i) >= 128 || ref.a(i) >= 128) { bad += 1 }
                let pct = Double(bad) / Double(area) * 100
                if pct < 0.5 { r.pass(String(format: "%@ covers the same footprint as %@ (%.2f%% off)", s, present[0], pct)) }
                else { r.fail(String(format: "%@ footprint differs from %@ by %.1f%%: base artwork would show through (ghosting)", s, present[0], pct)) }
            }
            // Neutral patch (with its pupils at rest) vs base inside the patch.
            var neutral = ref
            if group == "eyes", let pu = imgs["pupils"], let mk = imgs["eyes_mask"], let eo = imgs[present[0]] {
                let c = context(b.w, b.h), rect = CGRect(x: 0, y: 0, width: b.w, height: b.h)
                c.draw(eo, in: rect)
                c.beginTransparencyLayer(auxiliaryInfo: nil); c.draw(pu, in: rect); c.setBlendMode(.destinationIn); c.draw(mk, in: rect); c.endTransparencyLayer()
                neutral = Bitmap(c.makeImage()!)
            }
            var d = 0, cnt = 0
            for i in 0..<n where ref.a(i) >= 250 { d += neutral.diff(b, i); cnt += 1 }
            let mean = cnt > 0 ? Double(d) / Double(cnt) : 0
            if mean <= 10 { r.pass(String(format: "%@ matches the base under it (mean difference %.1f)", present[0], mean)) }
            else { r.warn(String(format: "%@ differs from the base under it (mean %.1f/255): paint the base with the same neutral %@", present[0], mean, group)) }
            // Feathered edges should blend into identical base pixels.
            var fe = 0, fc = 0
            for i in 0..<n where ref.a(i) > 8 && ref.a(i) < 247 { fe += ref.diff(b, i); fc += 1 }
            if fc > 0 && Double(fe) / Double(fc) > 25 { r.warn(String(format: "%@ has soft edges over differing base pixels (mean %.0f): seams may show", present[0], Double(fe) / Double(fc))) }
            // Visible area.
            let edge = Int(Double(b.w) * (1 - 1 / Double(LayeredPortrait.overscan)) / 2) + 4
            var outside = 0
            for i in 0..<n where foot[i] { let x = i % b.w, y = i / b.w; if x < edge || y < edge || x >= b.w - edge || y >= b.h - edge { outside += 1 } }
            if outside > area / 10 { r.warn("\(group) patch reaches into the overscan margin; parts may be cropped during sway") }
        }
        if let e = footprints["eyes"], let m = footprints["mouth"] {
            let overlap = (0..<n).filter { e[$0] && m[$0] }.count
            if overlap == 0 { r.pass("eye and mouth patches don't overlap: they animate independently") }
            else { r.fail("eye and mouth patches overlap by \(overlap) px: when both animate, one will cut into the other") }
        }
        // 4. Pupils.
        if let pu = bm["pupils"] {
            if let mk = bm["eyes_mask"], let eo = footprints["eyes"] {
                let maskOut = (0..<n).filter { mk.a($0) >= 128 && !eo[$0] }.count
                if maskOut == 0 { r.pass("eyes_mask lies inside the eye patch") } else { r.fail("eyes_mask extends \(maskOut) px beyond the eye patch: pupils would draw over the base's own eyes") }
                _ = pu
            } else if bm["eyes_mask"] == nil { r.fail("pupils supplied without eyes_mask (pupils would slide over the face)") }
            if (lp.spec.eyes?.pupilTravel ?? [0, 0]).allSatisfy({ $0 == 0 }) { r.warn("pupils supplied but pupilTravel is 0: they won't move") }
        }
        // 5. Team layer.
        if let t = bm["team"] {
            let tAll = (0..<n).filter { t.a($0) > 24 }
            let clash = tAll.filter { i in footprints.values.contains { $0[i] } }.count
            if clash > tAll.count / 20 { r.warn("team markings overlap a facial patch; markings there will be covered when it animates") } else { r.pass("team layer present (\(tAll.count) px) and clear of facial patches") }
        }
        // 6. Performance: draw time per frame at display size.
        let size = 234
        let disp = LayeredPortrait.load(id, from: source, pixels: LayeredPortrait.displayPixels)!
        func time(_ body: (CGContext, PortraitArt.Pose) -> Void) -> Double {
            let c = context(size, size)
            c.scaleBy(x: CGFloat(size) / 40, y: CGFloat(size) / 40)
            let t0 = CFAbsoluteTimeGetCurrent()
            for k in 0..<240 {
                let t = Double(k) / 30
                body(c, PortraitArt.Pose(look: PortraitArt.look(t, seed: 5), blink: PortraitArt.blink(t, seed: 5), mouth: CGFloat(0.5 + 0.5 * sin(t * 9)), t: t))
            }
            return (CFAbsoluteTimeGetCurrent() - t0) / 240 * 1000
        }
        let painted = time { c, p in disp.draw(c, pose: p, team: TeamColor.rgb(0)) }
        let original = time { c, p in PortraitArt.draw(Pen(c, 40, 40), unit: id, team: TeamColor.rgb(0), pose: p) }
        r.pass(String(format: "draw time per frame at 234 px (this Mac): painted %.2f ms, original %.2f ms", painted, original))
        let bytes = [disp.base, disp.eyesOpen, disp.eyesHalf, disp.eyesClosed, disp.pupils, disp.eyesMask, disp.team].compactMap { $0 }.map { $0.bytesPerRow * $0.height }.reduce(0, +)
            + disp.mouth.map { $0.bytesPerRow * $0.height }.reduce(0, +) + disp.fx.map { $0.1.bytesPerRow * $0.1.height }.reduce(0, +)
        r.pass(String(format: "memory while shown: %.1f MB (layers decoded at %d px)", Double(bytes) / 1_048_576, LayeredPortrait.displayPixels))
    }

    /// Original vs painted through the same poses, at real display size (234 px = 78 pt on a 3× iPhone).
    static func compareSheet(_ id: String, _ source: LayeredPortrait.Source, _ url: URL) {
        guard let lp = LayeredPortrait.load(id, from: source, pixels: LayeredPortrait.displayPixels) else { return }
        let poses: [(String, PortraitArt.Pose)] = [
            ("rest", .init()), ("look left", .init(look: CGPoint(x: -1, y: 0.3))), ("look right", .init(look: CGPoint(x: 1, y: -0.3))),
            ("half blink", .init(blink: 0.4)), ("blink", .init(blink: 1)), ("talk", .init(mouth: 0.45, t: 0.6)), ("talk wide", .init(look: CGPoint(x: 0.4, y: 0), mouth: 1, t: 1.4)),
        ]
        let cell = 234, pad = 14, labelH = 34
        let W = pad + poses.count * (cell + pad), H = labelH + 2 * (cell + pad) + pad + 30
        let c = context(W, H)
        c.setFillColor(RGB(0.06, 0.06, 0.08).cg); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 15) {
            let attr = [kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil), kCTForegroundColorAttributeName: RGB(1, 1, 1, 0.8).cg] as [CFString: Any]
            c.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attr as CFDictionary)), c)
        }
        text("\(id): top ORIGINAL (Swift-drawn), bottom PAINTED LAYERS, shown at 234 px = 78 pt @3x", CGFloat(pad), CGFloat(H - 24), 16)
        for (k, pose) in poses.enumerated() {
            let x = pad + k * (cell + pad)
            text(pose.0, CGFloat(x), CGFloat(H - labelH - 22))
            for row in 0..<2 {
                let y = H - labelH - 30 - (row + 1) * (cell + pad)
                c.saveGState()
                let rect = CGRect(x: x, y: y, width: cell, height: cell)
                let cut = CGFloat(cell) * 9 / 78
                let path = CGMutablePath()
                path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut)); path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut)); path.closeSubpath()
                c.addPath(path); c.clip()
                c.translateBy(x: rect.minX, y: rect.minY); c.scaleBy(x: CGFloat(cell) / 40, y: CGFloat(cell) / 40)
                if row == 0 { PortraitArt.draw(Pen(c, 40, 40), unit: id, team: TeamColor.rgb(0), pose: pose.1) }
                else { lp.draw(c, pose: pose.1, team: TeamColor.rgb(0)) }
                c.restoreGState()
            }
        }
        writePNG(c.makeImage()!, url)
    }
}
