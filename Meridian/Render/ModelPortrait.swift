import CoreGraphics
import Foundation
import ImageIO

/// Live portraits rendered from a unit's rigged 3D model (tools/blender/portraits.py): five head turns by three
/// mouth openings, each with a team-colour mask. The head crossfades between turns as the unit looks around, and
/// the jaw opens with each syllable of its radio line.
final class ModelPortrait {
    static let looks = 5, mouths = 3
    /// Team-tinted frames as [look][mouth], look 0 = turned to the viewer's left.
    let frames: [[CGImage]]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ModelPortrait?] = [:]

    static func has(_ id: String) -> Bool { url("p3d_\(id)_0_0") != nil }

    static func portrait(for id: String, team: RGB) -> ModelPortrait? {
        let key = "\(id)|\(team.r),\(team.g),\(team.b)"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let p = load(id, team: team)
        cache[key] = p
        return p
    }

    private static func load(_ id: String, team: RGB) -> ModelPortrait? {
        var frames: [[CGImage]] = []
        for l in 0..<looks {
            var row: [CGImage] = []
            for m in 0..<mouths {
                guard let b = image("p3d_\(id)_\(l)_\(m)"), let k = image("p3d_\(id)_\(l)_\(m)m") else { return nil }
                row.append(UnitModels.tinted(b, mask: k, team: team))
            }
            frames.append(row)
        }
        return ModelPortrait(frames: frames)
    }

    private init(frames: [[CGImage]]) { self.frames = frames }

    private static func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "jpg") }

    private static func image(_ name: String) -> CGImage? {
        guard let u = url(name), let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Draws into a context set up as the 40×40 portrait grid (origin bottom-left), like `PortraitArt.draw`.
    func draw(_ ctx: CGContext, pose f: PortraitArt.Pose) {
        ctx.saveGState()
        ctx.interpolationQuality = .medium
        // Breathing and a slight nod with vertical glances; the bake has a margin so the edges never show.
        let breathe = 1 + CGFloat(sin(f.t * 1.7)) * 0.012
        ctx.translateBy(x: 20, y: 20 + f.look.y * 0.5 + CGFloat(sin(f.t * 1.7)) * 0.15)
        ctx.scaleBy(x: breathe, y: breathe)
        let s: CGFloat = 40 * 1.08
        let r = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        let mi = min(Self.mouths - 1, Int((f.mouth * CGFloat(Self.mouths - 1)).rounded()))
        // Crossfade between the two nearest head turns.
        let u = (min(1, max(-1, f.look.x)) + 1) / 2 * CGFloat(Self.looks - 1)
        let i = min(Self.looks - 2, Int(u)), frac = u - CGFloat(i)
        ctx.draw(frames[i][mi], in: r)
        if frac > 0.02 {
            ctx.setAlpha(frac)
            ctx.draw(frames[i + 1][mi], in: r)
        }
        ctx.restoreGState()
    }
}
