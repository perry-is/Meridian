import Foundation

/// Formation slot planning for group orders.
///
/// Ranks (front → rear): 0 frontline (heavy armour, assault, melee), 1 line (rifle infantry, fast raiders),
/// 2 support line (anti-armour, anti-air, healers, specialists), 3 rear (siege). Aircraft hold a wide band
/// above the middle of the formation. Each formation reshapes these ranks:
///  - balanced: straight ranks, standard spacing.
///  - assault: a forward wedge; fast units take the wings of the front rank; tighter depth.
///  - defensive: a curved front shielding a compact core; siege and support tucked in the middle rear.
extension World {

    func formationRank(_ u: Entity, _ f: Formation) -> Int {
        let d = udef(u)
        if u.isAir { return -1 }
        switch d.role {
        case "heavy", "assault": return 0
        case "fast": return f == .assault ? 0 : 1
        case "infantry": return weapon(u).map { $0.range <= 1.6 } ?? false ? 0 : 1   // melee "infantry" (Mantis) fights in front
        case "siege": return 3
        default: return 2
        }
    }

    /// Slot offsets (relative to the goal point) for each unit id.
    func formationSlots(_ units: [Entity], goalX: Double, goalY: Double, formation f: Formation) -> [Int: (Double, Double)] {
        var out: [Int: (Double, Double)] = [:]
        let n = Double(units.count)
        let cx = units.reduce(0) { $0 + $1.x } / n, cy = units.reduce(0) { $0 + $1.y } / n
        var fx = goalX - cx, fy = goalY - cy
        let fl = (fx * fx + fy * fy).squareRoot()
        if fl < 0.5 { fx = 1; fy = 0 } else { fx /= fl; fy /= fl }
        let lx = -fy, ly = fx
        // Group by rank.
        var ranks: [Int: [Entity]] = [:]
        for u in units { ranks[formationRank(u, f), default: []].append(u) }
        let ground = units.filter { !$0.isAir }.count
        let widthScale = f == .defensive ? 0.72 : (f == .assault ? 0.85 : 1.0)
        let maxCols = max(4, Int((Double(ground).squareRoot() * 1.7 * widthScale).rounded()))
        let gap = f == .assault ? 0.45 : (f == .defensive ? 0.5 : 0.75)
        var forward = 0.0
        var frontWidth = 4.0
        for r in [0, 1, 2, 3] {
            guard var list = ranks[r], !list.isEmpty else { continue }
            // Keep left-to-right order to avoid units crossing paths.
            list.sort { (($0.x - cx) * lx + ($0.y - cy) * ly, $0.id) < (($1.x - cx) * lx + ($1.y - cy) * ly, $1.id) }
            let spacing = (list.map { $0.radius }.max() ?? 0.35) * 2 + (f == .defensive ? 0.12 : 0.25)
            let cols = min(maxCols, list.count)
            let rows = (list.count + cols - 1) / cols
            if r == 0 { frontWidth = Double(cols) * spacing }
            for (i, u) in list.enumerated() {
                let row = i / cols
                let inRow = min(cols, list.count - row * cols)
                let col = i % cols
                var lat = (Double(col) - Double(inRow - 1) / 2) * spacing
                var fwd = forward - Double(row) * spacing
                switch f {
                case .assault where r <= 1:
                    fwd -= abs(lat) * 0.35                                   // wedge pointing at the enemy
                case .defensive where r == 0:
                    let half = max(1, frontWidth / 2)
                    fwd -= (lat / half) * (lat / half) * 1.6                  // curved shield wall
                case .defensive where r >= 2:
                    lat *= 0.8                                               // tuck vulnerable units in
                default: break
                }
                if r == 3, let w = weapon(u) {
                    // Artillery stays behind the line but within reach of the fight at the front.
                    fwd = max(fwd, -(w.range - 6))
                }
                _ = rows
                out[u.id] = (fx * fwd + lx * lat, fy * fwd + ly * lat)
            }
            forward -= Double(rows) * spacing + gap
        }
        // Aircraft: a wide band over the middle of the formation.
        if let air = ranks[-1], !air.isEmpty {
            let sorted = air.sorted { (($0.x - cx) * lx + ($0.y - cy) * ly, $0.id) < (($1.x - cx) * lx + ($1.y - cy) * ly, $1.id) }
            let spacing = 1.4
            let cols = max(3, min(sorted.count, Int(Double(sorted.count).squareRoot() * 2)))
            let mid = forward * 0.45
            for (i, u) in sorted.enumerated() {
                let row = i / cols, col = i % cols
                let inRow = min(cols, sorted.count - row * cols)
                let lat = (Double(col) - Double(inRow - 1) / 2) * spacing
                let fwd = mid - Double(row) * spacing + (f == .assault ? 1.5 : 0)
                out[u.id] = (fx * fwd + lx * lat, fy * fwd + ly * lat)
            }
        }
        // Centre the formation on the clicked point (ground slots' centroid at the goal).
        let groundSlots = units.filter { !$0.isAir }.compactMap { out[$0.id] }
        if !groundSlots.isEmpty {
            let mx = groundSlots.reduce(0) { $0 + $1.0 } / Double(groundSlots.count), my = groundSlots.reduce(0) { $0 + $1.1 } / Double(groundSlots.count)
            for (k, v) in out { out[k] = (v.0 - mx, v.1 - my) }
        }
        // Slots must be on walkable ground.
        for u in units where !u.isAir {
            guard let o = out[u.id] else { continue }
            let tx = Int(goalX + o.0), ty = Int(goalY + o.1)
            if nav.isBlocked(tx, ty) {
                let (ox, oy) = nav.nearestOpen(tx, ty)
                out[u.id] = (Double(ox) + 0.5 - goalX, Double(oy) + 0.5 - goalY)
            }
        }
        return out
    }
}
