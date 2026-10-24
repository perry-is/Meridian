import CoreGraphics
import Foundation
import ImageIO

/// Painted portraits: one master image plus independent facial layers, animated by the same pose
/// (look, blink, mouth, clock) that drives the Swift-drawn portraits, so voice sync and idle timing are unchanged.
///
/// Layers (PNG, all the same square canvas, named `<unitID>_<layer>.png`; see docs/portraits/PORTRAIT_SPEC.md):
///  - `base`            required. The complete portrait with a neutral face, opaque edge to edge.
///  - `eyes_open`       eye patch, neutral. `eyes_half` (optional) and `eyes_closed` replace it when blinking.
///  - `pupils` + `eyes_mask`  optional. The moving part of the eyes, slid by the gaze and clipped to the mask.
///  - `mouth_closed`, `mouth_open1`, `mouth_open2`  mouth patches picked by speech level (open2 optional).
///  - `team`            optional. Team markings painted light on transparent; tinted with the owner's colour.
///  - `fx_<name>`       optional. Glows driven by speech, a pulse or the blink (listed in the JSON).
/// Every state of a feature covers exactly the same footprint with opaque pixels, so swapping states can
/// never show the base's own eyes or mouth underneath (no ghosting). Eyes, mouth and effects animate at once.
final class LayeredPortrait {
    struct Spec: Decodable {
        struct Eyes: Decodable {
            /// Largest pupil travel in master pixels (x, y) at full gaze.
            var pupilTravel: [Double]?
            var halfAt: Double?
            var closedAt: Double?
        }
        struct Mouth: Decodable {
            /// Speech levels at which open1 and open2 take over.
            var thresholds: [Double]?
        }
        struct FX: Decodable {
            var layer: String
            /// "add" (default), "screen" or "normal".
            var blend: String?
            /// "speech" (default), "pulse", "blink" or "always".
            var driver: String?
            var min: Double?
            var max: Double?
            /// Pulses per second for the "pulse" driver.
            var rate: Double?
        }
        struct Motion: Decodable {
            var sway: Double?
            var breathe: Double?
            var lookShift: Double?
        }
        var eyes: Eyes?
        var mouth: Mouth?
        var fx: [FX]?
        var motion: Motion?
    }

    let unitID: String
    let spec: Spec
    /// Master canvas size in pixels.
    let masterSize: CGFloat
    let base: CGImage
    let eyesOpen: CGImage?, eyesHalf: CGImage?, eyesClosed: CGImage?
    let pupils: CGImage?, eyesMask: CGImage?
    let mouth: [CGImage]
    let team: CGImage?
    let fx: [(Spec.FX, CGImage)]

    /// Pixel size layers are decoded at for display: the 78 pt box at 3× plus the overscan margin
    /// (drawing near 1:1 keeps it sharp and cheap).
    static let displayPixels = 256
    /// Layers are drawn slightly larger than the frame so sway and breathing never reveal an edge.
    static let overscan: CGFloat = 1.06

    // MARK: Loading

    /// Where layer files come from: the app bundle, or a folder (for checking new artwork before adding it).
    enum Source {
        case bundle
        case folder(URL)
        func url(_ name: String, _ ext: String) -> URL? {
            switch self {
            case .bundle: return Bundle.main.url(forResource: name, withExtension: ext)
            case .folder(let dir):
                let u = dir.appendingPathComponent("\(name).\(ext)")
                return FileManager.default.fileExists(atPath: u.path) ? u : nil
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: LayeredPortrait?] = [:]

    /// Show the original Swift-drawn portraits even where painted ones exist (toggled by long-pressing a portrait).
    nonisolated(unsafe) static var preferOriginal: Bool = UserDefaults.standard.bool(forKey: "portrait.original")
        || ProcessInfo.processInfo.arguments.contains("-originalportraits") {
        didSet { UserDefaults.standard.set(preferOriginal, forKey: "portrait.original") }
    }

    /// The painted portrait for a unit, or nil to fall back to the Swift-drawn one. Cached after first use.
    static func portrait(for id: String) -> LayeredPortrait? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[id] { return hit }
        let p = load(id, from: .bundle, pixels: displayPixels)
        cache[id] = p
        return p
    }

    static func hasLayers(_ id: String, in source: Source = .bundle) -> Bool { source.url("\(id)_base", "png") != nil }

    /// Loads a unit's layers. `pixels` nil keeps the master resolution (validation); otherwise layers are
    /// decoded straight to that size with high-quality filtering.
    static func load(_ id: String, from source: Source, pixels: Int?) -> LayeredPortrait? {
        guard let baseURL = source.url("\(id)_base", "png"), let base = decode(baseURL, pixels) else { return nil }
        func layer(_ name: String) -> CGImage? { source.url("\(id)_\(name)", "png").flatMap { decode($0, pixels) } }
        var spec = Spec()
        if let j = source.url("\(id)_portrait", "json"), let d = try? Data(contentsOf: j) {
            do { spec = try JSONDecoder().decode(Spec.self, from: d) } catch { print("PORTRAIT \(id): bad JSON — \(error)") }
        }
        let master = CGFloat((CGImageSourceCreateWithURL(baseURL as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyPixelWidth] as? Int) ?? base.width)
        let mouth = ["mouth_closed", "mouth_open1", "mouth_open2"].compactMap(layer)
        let fx = (spec.fx ?? []).compactMap { f in layer(f.layer).map { (f, $0) } }
        return LayeredPortrait(unitID: id, spec: spec, masterSize: master, base: base,
                               eyesOpen: layer("eyes_open"), eyesHalf: layer("eyes_half"), eyesClosed: layer("eyes_closed"),
                               pupils: layer("pupils"), eyesMask: layer("eyes_mask"), mouth: mouth, team: layer("team"), fx: fx)
    }

    static func decode(_ url: URL, _ pixels: Int?) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let px = pixels else { return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: px,
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private init(unitID: String, spec: Spec, masterSize: CGFloat, base: CGImage, eyesOpen: CGImage?, eyesHalf: CGImage?, eyesClosed: CGImage?,
                 pupils: CGImage?, eyesMask: CGImage?, mouth: [CGImage], team: CGImage?, fx: [(Spec.FX, CGImage)]) {
        self.unitID = unitID; self.spec = spec; self.masterSize = masterSize; self.base = base
        self.eyesOpen = eyesOpen; self.eyesHalf = eyesHalf; self.eyesClosed = eyesClosed
        self.pupils = pupils; self.eyesMask = eyesMask; self.mouth = mouth; self.team = team; self.fx = fx
    }

    // MARK: Drawing

    private var tintCache: (key: [CGFloat], image: CGImage)?

    /// The team layer multiplied by the owner's colour (made once per colour, not every frame).
    func tinted(_ color: RGB) -> CGImage? {
        guard let t = team else { return nil }
        let key = [color.r, color.g, color.b]
        if let c = tintCache, c.key == key { return c.image }
        let w = t.width, h = t.height, rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(t, in: rect)
        c.setBlendMode(.multiply); c.setFillColor(color.cg); c.fill(rect)
        c.setBlendMode(.destinationIn); c.draw(t, in: rect)
        guard let img = c.makeImage() else { return nil }
        tintCache = (key, img)
        return img
    }

    /// Which eye and mouth states a pose shows (also used by the validator's sheets).
    func eyeState(_ blink: CGFloat) -> CGImage? {
        let e = spec.eyes
        if blink >= CGFloat(e?.closedAt ?? 0.6), let c = eyesClosed { return c }
        if blink >= CGFloat(e?.halfAt ?? 0.2), let h = eyesHalf { return h }
        return eyesOpen
    }

    func mouthState(_ level: CGFloat) -> CGImage? {
        guard !mouth.isEmpty else { return nil }
        let t = spec.mouth?.thresholds ?? [0.12, 0.55]
        var i = 0
        if level >= CGFloat(t.first ?? 0.12) { i = 1 }
        if t.count > 1 && level >= CGFloat(t[1]) { i = 2 }
        return mouth[min(i, mouth.count - 1)]
    }

    /// Draws into a context set up as the 40×40 portrait grid (origin bottom-left), like `PortraitArt.draw`.
    func draw(_ ctx: CGContext, pose f: PortraitArt.Pose, team color: RGB) {
        let m = spec.motion
        let sw = CGFloat(m?.sway ?? 1), br = CGFloat(m?.breathe ?? 1), ls = CGFloat(m?.lookShift ?? 1)
        ctx.saveGState()
        ctx.interpolationQuality = .medium
        // Idle motion about the bottom centre: the same rhythm as the drawn portraits.
        let sway = CGFloat(sin(f.t * 0.8)) * 0.018 * sw + f.look.x * 0.025 * sw
        let breathe = 1 + CGFloat(sin(f.t * 1.7)) * 0.01 * br
        ctx.translateBy(x: 20 + f.look.x * 0.6 * ls, y: 2 + f.look.y * 0.35 * ls)
        ctx.rotate(by: -sway)
        ctx.scaleBy(x: breathe, y: breathe)
        ctx.translateBy(x: -20, y: -2)
        let o = Self.overscan
        let r = CGRect(x: -20 * (o - 1), y: -20 * (o - 1), width: 40 * o, height: 40 * o)
        let px = 40 * o / masterSize          // master pixels → grid units

        ctx.draw(base, in: r)
        if let t = tinted(color) { ctx.draw(t, in: r) }
        if let mo = mouthState(f.mouth) { ctx.draw(mo, in: r) }
        let eye = eyeState(f.blink)
        if let e = eye { ctx.draw(e, in: r) }
        if eye === eyesOpen || eye == nil, let p = pupils {
            let tr = spec.eyes?.pupilTravel ?? [0, 0]
            let dx = f.look.x * CGFloat(tr.first ?? 0) * px, dy = f.look.y * CGFloat(tr.count > 1 ? tr[1] : 0) * px
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.draw(p, in: r.offsetBy(dx: dx, dy: dy))
            if let mask = eyesMask { ctx.setBlendMode(.destinationIn); ctx.draw(mask, in: r) }
            ctx.endTransparencyLayer()
        }
        for (s, img) in fx {
            let v: Double
            switch s.driver ?? "speech" {
            case "pulse": v = 0.5 + 0.5 * sin(f.t * 2 * .pi * (s.rate ?? 0.5))
            case "blink": v = Double(f.blink)
            case "always": v = 1
            default: v = Double(f.mouth)
            }
            let a = (s.min ?? 0) + ((s.max ?? 1) - (s.min ?? 0)) * v
            guard a > 0.01 else { continue }
            ctx.saveGState()
            ctx.setAlpha(CGFloat(a))
            ctx.setBlendMode(s.blend == "normal" ? .normal : (s.blend == "screen" ? .screen : .plusLighter))
            ctx.draw(img, in: r)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}
