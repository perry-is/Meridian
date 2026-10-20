import SpriteKit
import MeridianCore

/// Spectator camera that follows the heat of combat.
/// - Tracks a decaying heat map of impacts (weighted by damage).
/// - Commits to an engagement for a minimum dwell time and only switches when another fight is clearly hotter,
///   so it doesn't ping-pong between distant skirmishes.
/// - Auto-zooms to frame the units around the focus.
/// - Any manual pan/pinch suspends tracking for a few seconds.
final class BattleCamera {
    struct Heat { var x: Double; var y: Double; var w: Double; var t: Double }
    var enabled = true
    var autoZoom = true
    private(set) var manualUntil: Double = 0
    private var heat: [Heat] = []
    private var focus: (Double, Double)? = nil
    private var focusSince: Double = 0
    private var coldSince: Double = 0
    private var velocity = CGVector.zero
    private var zoomVelocity: CGFloat = 0

    var isTracking: Bool { enabled && CACurrentMediaTime() >= manualUntil }

    func record(_ x: Double, _ y: Double, weight: Double, time: Double) {
        heat.append(Heat(x: x, y: y, w: max(1, weight), t: time))
        if heat.count > 600 { heat.removeFirst(heat.count - 600) }
    }

    func manualOverride(seconds: Double = 6) { manualUntil = CACurrentMediaTime() + seconds }

    private func heatNear(_ x: Double, _ y: Double, _ r: Double, now: Double) -> (Double, Double, Double) {
        var w = 0.0, sx = 0.0, sy = 0.0
        for h in heat {
            let d2 = (h.x - x) * (h.x - x) + (h.y - y) * (h.y - y)
            if d2 > r * r { continue }
            let k = h.w * exp(-(now - h.t) / 1.5)
            w += k; sx += h.x * k; sy += h.y * k
        }
        return w > 0 ? (w, sx / w, sy / w) : (0, x, y)
    }

    func update(_ scene: GameScene, dt: Double) {
        let world = scene.world
        let now = world.time
        heat.removeAll { now - $0.t > 4 }
        guard isTracking else { velocity = .zero; zoomVelocity = 0; return }

        // Hottest region: coarse grid search, then refine with a weighted centroid.
        var best: (Double, Double, Double) = (0, 0, 0)
        if !heat.isEmpty {
            var grid: [Int: Double] = [:]
            for h in heat { grid[Int(h.x / 8) * 1000 + Int(h.y / 8), default: 0] += h.w * exp(-(now - h.t) / 1.5) }
            if let top = grid.max(by: { $0.value < $1.value }) {
                let cx = Double(top.key / 1000) * 8 + 4, cy = Double(top.key % 1000) * 8 + 4
                let (w, x, y) = heatNear(cx, cy, 11, now: now)
                best = (w, x, y)
            }
        }
        if let f = focus {
            let (cw, fx, fy) = heatNear(f.0, f.1, 11, now: now)
            if cw > 0 { focus = (f.0 + (fx - f.0) * min(1, dt * 1.5), f.1 + (fy - f.1) * min(1, dt * 1.5)); coldSince = now }
            let dwell = now - focusSince
            let farAway = dist2(best.1, best.2, f.0, f.1) > 14 * 14
            if best.0 > 0 && farAway && ((best.0 > cw * 1.7 && dwell > 3.5) || now - coldSince > 2.5) {
                focus = (best.1, best.2); focusSince = now
            }
        } else if best.0 > 0 {
            focus = (best.1, best.2); focusSince = now; coldSince = now
        }
        // Before any fighting: frame the armies.
        let target: (Double, Double)
        if let f = focus { target = f } else {
            let us = world.entities.filter { $0.isUnit && $0.onMap && !$0.isMine }
            guard !us.isEmpty else { return }
            target = (us.reduce(0) { $0 + $1.x } / Double(us.count), us.reduce(0) { $0 + $1.y } / Double(us.count))
        }
        // Critically damped spring toward the target.
        let goal = Iso.scene(target.0, target.1)
        let k: CGFloat = 3.2
        let dx = goal.x - scene.cam.position.x, dy = goal.y - scene.cam.position.y
        let a = CGVector(dx: dx * k * k - 2 * k * velocity.dx, dy: dy * k * k - 2 * k * velocity.dy)
        velocity.dx += a.dx * CGFloat(dt); velocity.dy += a.dy * CGFloat(dt)
        scene.cam.position.x += velocity.dx * CGFloat(dt)
        scene.cam.position.y += velocity.dy * CGFloat(dt)
        scene.clampCamera()

        guard autoZoom else { return }
        // Frame units engaged near the focus.
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity, minY = CGFloat.infinity, maxY = -CGFloat.infinity
        var n = 0
        for e in world.entities where e.isUnit && e.onMap && !e.isMine && dist2(e.x, e.y, target.0, target.1) < 8 * 8 {
            let p = Iso.scene(e.x, e.y)
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y + (e.isAir ? 40 : 0))
            n += 1
        }
        guard n > 0, scene.size.width > 0 else { return }
        let need = max((maxX - minX + 160) / scene.size.width, (maxY - minY + 220) / (scene.size.height * 0.6))
        // Readability cap: on a narrow phone screen stay close enough that infantry remain legible.
        let cap: CGFloat = scene.size.width < 520 ? 1.6 : 2.1
        let desired = min(cap, max(0.85, need))
        let zk: CGFloat = 1.6
        let za = (desired - scene.zoom) * zk * zk - 2 * zk * zoomVelocity
        zoomVelocity += za * CGFloat(dt)
        scene.zoom += zoomVelocity * CGFloat(dt)
        scene.applyZoom()
    }
}
