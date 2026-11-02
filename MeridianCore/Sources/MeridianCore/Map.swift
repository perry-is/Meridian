import Foundation

public enum Terrain: UInt8, Sendable {
    case grass = 0, dirt = 1, moss = 2, rock = 3, water = 4
    public var groundPassable: Bool { rawValue < 3 }
}

public struct ResourceSpawn: Sendable {
    public var kind: ResourceKind
    public var x: Int
    public var y: Int
}

public enum MapLayout: String, CaseIterable, Sendable {
    case crossroads, riverbend, highlands, arena
    public static var playable: [MapLayout] { [.crossroads, .riverbend, .highlands] }
    public var title: String {
        switch self {
        case .crossroads: return "Crossroads"
        case .riverbend: return "Riverbend"
        case .highlands: return "Shattered Highlands"
        case .arena: return "Test Arena"
        }
    }
    /// One line for the battle setup screen.
    public var blurb: String {
        switch self {
        case .crossroads: return "Open plains with rock ridges that funnel the roads between bases."
        case .riverbend: return "Rivers split the commanders apart; fight for the fords."
        case .highlands: return "Broken ground full of crags and pools: ambush country."
        case .arena: return "Flat test ground."
        }
    }
}

/// Static map description produced by the generator. Maps are rotationally symmetric around their centre
/// (one fold per player), so every commander starts with the same ground, resources and sites.
public struct MapData: Sendable {
    public let size: Int
    public var terrain: [UInt8]
    public var elevation: [UInt8]
    public var resources: [ResourceSpawn]
    /// HQ footprint origin tiles, one per start position.
    public var starts: [(x: Int, y: Int)]
    /// Strategic sites; index 0 is the centre.
    public var sites: [(x: Double, y: Double)]
    public var name: String

    @inline(__always) public func idx(_ x: Int, _ y: Int) -> Int { y * size + x }
    @inline(__always) public func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < size && y < size }
    public func terrainAt(_ x: Int, _ y: Int) -> Terrain { Terrain(rawValue: terrain[idx(x, y)]) ?? .grass }

    // MARK: Generation

    /// Generates a battlefield for 2–4 players. `size` should come from `MatchConfig.mapSize(players:quick:)`.
    public static func generate(layout: MapLayout, seed: UInt64, size: Int = 112, players: Int = 2) -> MapData {
        let k = max(2, min(MatchConfig.maxPlayers, players))
        var g = Generator(size: size, players: k, seed: seed &+ UInt64(layout.hashValueStable) &+ UInt64(k - 2) &* 1013)
        return g.build(layout)
    }
}

extension MapLayout {
    var hashValueStable: Int {
        switch self { case .crossroads: return 11; case .riverbend: return 23; case .highlands: return 37; case .arena: return 41 }
    }

    /// Start positions in polar coordinates around the centre: the angle of the first base and its distance
    /// as a fraction of the map side. (For two players these reproduce the original layouts.)
    func base(players k: Int) -> (angle: Double, radius: Double) {
        switch self {
        case .crossroads, .arena: return (angle: 1.25 * .pi, radius: k == 3 ? 0.38 : 0.495)      // corner (two: both corners)
        case .riverbend: return (angle: .pi, radius: k == 3 ? 0.37 : 0.39)                        // edge midpoint
        case .highlands: return (angle: 2.384, radius: k == 3 ? 0.38 : 0.495)                     // the other corner
        }
    }

    /// Strategic sites of the first player's sector as (angle offset from the base, distance fraction).
    /// Two-player maps keep their three sites per side; bigger maps have a home flank and a contested site
    /// on the boundary with the next commander.
    func sectorSites(players k: Int) -> [(Double, Double)] {
        let boundary = Double.pi / Double(k)
        let scale = k == 3 ? 0.85 : 1.0
        switch self {
        case .crossroads, .arena:
            return k == 2 ? [(0.424, 0.396), (-0.424, 0.396), (-boundary, 0.368)] : [(0.42, 0.37 * scale), (-boundary, 0.36 * scale)]
        case .riverbend:
            // The boundary site sits on the river's outer ford (0.37 of the side), so it is never scaled.
            return k == 2 ? [(0.883, 0.362), (-0.883, 0.362), (boundary, 0.37)] : [(0.8, 0.33 * scale), (boundary, 0.37)]
        case .highlands:
            return k == 2 ? [(0.578, 0.335), (-0.536, 0.364), (1.653, 0.32)] : [(0.55, 0.34 * scale), (boundary, 0.33 * scale)]
        }
    }
}

private struct Generator {
    let n: Int
    /// Symmetry order = player count.
    let k: Int
    var rng: RNG
    var terrain: [UInt8]
    var elevation: [UInt8]
    var occupied: [Bool]        // resources and reserved tiles
    var protected: [Bool]       // never place obstacles here
    var resources: [ResourceSpawn] = []
    /// Angle from the centre to the first player's base.
    var baseAngle = 0.0

    init(size: Int, players: Int, seed: UInt64) {
        n = size
        k = players
        rng = RNG(seed: seed)
        terrain = Array(repeating: Terrain.grass.rawValue, count: size * size)
        elevation = Array(repeating: 0, count: size * size)
        occupied = Array(repeating: false, count: size * size)
        protected = Array(repeating: false, count: size * size)
    }

    var c: Double { Double(n) / 2 }
    @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * n + x }
    @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool { x >= 1 && y >= 1 && x < n - 1 && y < n - 1 }
    @inline(__always) func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n }

    // MARK: Symmetry

    /// Rotates a point by `j` sectors about the centre. Quarter turns are exact (tile centres land on tile centres),
    /// so two- and four-player maps are symmetric tile for tile.
    func rot(_ x: Double, _ y: Double, _ j: Int) -> (Double, Double) {
        let jj = ((j % k) + k) % k
        if jj == 0 { return (x, y) }
        var dx = x - c, dy = y - c
        if k == 2 || k == 4 {
            for _ in 0..<(k == 2 ? jj * 2 : jj) { (dx, dy) = (-dy, dx) }
        } else {
            let a = Double(jj) * 2 * .pi / Double(k)
            (dx, dy) = (dx * cos(a) - dy * sin(a), dx * sin(a) + dy * cos(a))
        }
        return (c + dx, c + dy)
    }

    /// The tile under a continuous point.
    @inline(__always) func tile(_ p: (Double, Double)) -> (Int, Int) { (Int(floor(p.0)), Int(floor(p.1))) }

    /// All rotated copies of a tile (off-map copies dropped; only possible on three-player maps).
    func orbit(_ x: Int, _ y: Int) -> [(Int, Int)] {
        (0..<k).map { tile(rot(Double(x) + 0.5, Double(y) + 0.5, $0)) }.filter { inBounds($0.0, $0.1) }
    }

    /// Representative of a tile's orbit: the copy with the lowest index. Symmetric decisions are made here.
    func rep(_ x: Int, _ y: Int) -> (Int, Int) {
        var best = (x, y)
        for (ox, oy) in orbit(x, y) where idx(ox, oy) < idx(best.0, best.1) { best = (ox, oy) }
        return best
    }

    /// Whether a point lies in the first player's sector (within half a turn-slice of the base direction).
    func inSector(_ x: Double, _ y: Double) -> Bool {
        var d = atan2(y - c, x - c) - baseAngle
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return abs(d) < .pi / Double(k)
    }

    /// Distance from a point to the nearest sector boundary ray (the border between two commanders' halves).
    func distToBoundary(_ x: Double, _ y: Double) -> Double {
        var best = Double.infinity
        for j in 0..<k {
            let a = baseAngle + .pi / Double(k) + Double(j) * 2 * .pi / Double(k)
            let ux = cos(a), uy = sin(a)
            let dx = x - c, dy = y - c
            let along = dx * ux + dy * uy
            let d = along < 0 ? (dx * dx + dy * dy).squareRoot() : abs(dx * uy - dy * ux)
            best = min(best, d)
        }
        return best
    }

    /// Three-player maps are played inside the inscribed circle (the corners cannot be made symmetric).
    var playRadius: Double { k == 3 ? c - 1 : Double.infinity }
    func inPlay(_ x: Double, _ y: Double) -> Bool { dist2(x, y, c, c) < playRadius * playRadius }

    /// A random point inside the first sector, `margin` tiles from the edges.
    mutating func randomInSector(margin: Double) -> (Double, Double) {
        for _ in 0..<64 {
            let x = rng.range(margin, Double(n) - margin), y = rng.range(margin, Double(n) - margin)
            if inSector(x, y) && dist2(x, y, c, c) < (playRadius - margin) * (playRadius - margin) { return (x, y) }
        }
        let a = baseAngle + rng.range(-0.8, 0.8) * .pi / Double(k)
        let r = rng.range(8, min(c - margin, playRadius - margin))
        return (c + cos(a) * r, c + sin(a) * r)
    }

    /// A point `r` tiles from the centre at `angle`.
    func polar(_ angle: Double, _ r: Double) -> (Double, Double) { (c + cos(angle) * r, c + sin(angle) * r) }

    // Hash-based value noise, deterministic for a seed.
    func noise(_ x: Double, _ y: Double, _ s: UInt64) -> Double {
        func h(_ ix: Int, _ iy: Int) -> Double {
            var r = RNG(seed: s &+ UInt64(bitPattern: Int64(ix &* 73856093 ^ iy &* 19349663)))
            return r.unit()
        }
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = h(x0, y0), b = h(x0 + 1, y0), c = h(x0, y0 + 1), d = h(x0 + 1, y0 + 1)
        return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    }

    // MARK: Painting (every operation is applied to all rotated copies)

    mutating func setSym(_ x: Int, _ y: Int, _ t: Terrain) {
        guard inside(x, y) else { return }
        for (ox, oy) in orbit(x, y) where inside(ox, oy) { terrain[idx(ox, oy)] = t.rawValue }
    }

    mutating func protect(_ px: Double, _ py: Double, _ r: Double) {
        let r2 = r * r
        for j in 0..<k {
            let (cx, cy) = rot(px, py, j)
            guard let ys = span(cy - r, cy + r, 0, n - 1), let xs = span(cx - r, cx + r, 0, n - 1) else { continue }
            for y in ys { for x in xs where dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= r2 { protected[idx(x, y)] = true } }
        }
    }

    /// Clamped tile range covering [lo, hi], or nil when it misses the map.
    func span(_ lo: Double, _ hi: Double, _ minT: Int, _ maxT: Int) -> ClosedRange<Int>? {
        let a = max(minT, Int(floor(lo))), b = min(maxT, Int(floor(hi)))
        return a <= b ? a...b : nil
    }

    /// Places a resource node under a continuous point and under each of its rotated copies.
    /// Every copy must be free and walkable, so the copies stay identical.
    mutating func placeResource(_ kind: ResourceKind, at px: Double, _ py: Double) {
        var tiles: [(Int, Int)] = []
        for j in 0..<k {
            let (x, y) = tile(rot(px, py, j))
            guard inside(x, y), inPlay(Double(x) + 0.5, Double(y) + 0.5) else { return }
            let i = idx(x, y)
            guard !occupied[i], Terrain(rawValue: terrain[i])!.groundPassable, !tiles.contains(where: { $0 == (x, y) }) else { return }
            tiles.append((x, y))
        }
        for (x, y) in tiles {
            occupied[idx(x, y)] = true
            resources.append(ResourceSpawn(kind: kind, x: x, y: y))
        }
    }

    /// Arc of resource nodes around (cx,cy) facing angle a.
    mutating func resourceArc(_ kind: ResourceKind, _ cx: Double, _ cy: Double, angle: Double, radius: Double, count: Int, spread: Double) {
        for i in 0..<count {
            let t = count == 1 ? 0 : (Double(i) / Double(count - 1) - 0.5) * spread
            let a = angle + t
            placeResource(kind, at: cx + cos(a) * radius, cy + sin(a) * radius)
            if kind == .wood { // forests are two rows deep
                placeResource(kind, at: cx + cos(a) * (radius + 1.2), cy + sin(a) * (radius + 1.2))
            }
        }
    }

    mutating func forestClump(_ cx: Double, _ cy: Double, _ count: Int) {
        for _ in 0..<count {
            let a = rng.range(0, 2 * .pi), r = rng.range(0, 3.2)
            let x = cx + cos(a) * r, y = cy + sin(a) * r
            let (tx, ty) = tile((x, y))
            if inside(tx, ty) && !protected[idx(tx, ty)] { placeResource(.wood, at: x, y) }
        }
    }

    /// An irregular patch of terrain centred on (bx,by) and on each rotated copy. The wobble is sampled at the
    /// orbit representative so all copies take the same shape.
    mutating func blob(_ bx: Double, _ by: Double, _ r: Double, _ t: Terrain) {
        let r2 = r * r
        for j in 0..<k {
            let (cx, cy) = rot(bx, by, j)
            guard let ys = span(cy - r - 1, cy + r + 1, 1, n - 2), let xs = span(cx - r - 1, cx + r + 1, 1, n - 2) else { continue }
            for y in ys {
                for x in xs {
                    let (rx, ry) = rep(x, y)
                    let wob = noise(Double(rx) * 0.35, Double(ry) * 0.35, 99) * 0.8 + 0.6
                    guard dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= r2 * wob else { continue }
                    let i = idx(x, y)
                    if !protected[i] && !occupied[i] { terrain[i] = t.rawValue }
                }
            }
        }
    }

    /// Opens a walkable corridor from a to b (and between their rotated copies).
    mutating func carve(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, width: Double) {
        let steps = Int(max(abs(bx - ax), abs(by - ay)) * 2) + 1
        for j in 0..<k {
            let (a0, a1) = rot(ax, ay, j), (b0, b1) = rot(bx, by, j)
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let cx = a0 + (b0 - a0) * t, cy = a1 + (b1 - a1) * t
                guard let ys = span(cy - width, cy + width, 1, n - 2), let xs = span(cx - width, cx + width, 1, n - 2) else { continue }
                for y in ys {
                    for x in xs where dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= width * width {
                        let i = idx(x, y)
                        if !Terrain(rawValue: terrain[i])!.groundPassable { terrain[i] = Terrain.dirt.rawValue }
                    }
                }
            }
        }
    }

    /// A winding river along each sector boundary, from the centre to the map edge, with fords.
    mutating func rivers(_ s1: UInt64) {
        let N = Double(n)
        let fords: [(Double, Double)] = [(0, 0.05 * N), (0.19 * N, 0.025 * N), (0.37 * N, 0.04 * N)]
        let reach = (k == 3 ? playRadius : N * 0.75) + 3
        var d = 0.0
        while d < reach {
            let wob = sin(d * 0.11) * 4 + noise(0.5, d * 0.1, s1) * 3
            let ford = fords.contains { abs(d - $0.0) < $0.1 }
            if !ford {
                for j in 0..<k {
                    let a = baseAngle + .pi / Double(k) + Double(j) * 2 * .pi / Double(k)
                    let cx = c + cos(a) * d - sin(a) * wob, cy = c + sin(a) * d + cos(a) * wob
                    guard let ys = span(cy - 2.6, cy + 2.6, 1, n - 2), let xs = span(cx - 2.6, cx + 2.6, 1, n - 2) else { continue }
                    for y in ys {
                        for x in xs where dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= 2.6 * 2.6 {
                            let i = idx(x, y)
                            if !occupied[i] { terrain[i] = Terrain.water.rawValue }
                        }
                    }
                }
            }
            d += 0.5
        }
    }

    func reachable(from sx: Int, _ sy: Int) -> [Bool] {
        var seen = Array(repeating: false, count: n * n)
        var stack = [(sx, sy)]
        seen[idx(sx, sy)] = true
        while let (x, y) = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                let i = idx(nx, ny)
                if !seen[i] && Terrain(rawValue: terrain[i])!.groundPassable && !occupied[i] {
                    seen[i] = true; stack.append((nx, ny))
                }
            }
        }
        return seen
    }

    /// HQ footprint origin (4×4) for the start rotated into sector j.
    func hqOrigin(_ start: (Double, Double), _ j: Int) -> (x: Int, y: Int) {
        // The footprint centre is an integer point; rotating it keeps every copy on the same sub-tile phase.
        let centre = (Double(Int(start.0)), Double(Int(start.1)))
        let (x, y) = rot(centre.0, centre.1, j)
        return (x: Int(x.rounded()) - 2, y: Int(y.rounded()) - 2)
    }

    // MARK: Build

    mutating func build(_ layout: MapLayout) -> MapData {
        let N = Double(n)
        if layout == .arena {
            // Open battlefield: purely cosmetic passable variety (dirt and moss), no obstacles.
            let s1 = rng.next()
            for y in 0..<n { for x in 0..<n {
                let v = noise(Double(x) * 0.07, Double(y) * 0.07, s1)
                terrain[idx(x, y)] = (v > 0.62 ? Terrain.dirt : (v < 0.2 ? Terrain.moss : Terrain.grass)).rawValue
            } }
            let corners = [(x: 4, y: 4), (x: n - 8, y: n - 8), (x: n - 8, y: 4), (x: 4, y: n - 8)]
            return MapData(size: n, terrain: terrain, elevation: elevation, resources: [],
                           starts: Array(corners.prefix(k)), sites: [], name: layout.title)
        }
        let base = layout.base(players: k)
        baseAngle = base.angle
        let start0 = polar(base.angle, base.radius * N)
        let center = (c, c)
        let sitesSector = layout.sectorSites(players: k).map { polar(base.angle + $0.0, $0.1 * N) }

        // Ground texture variation (decided at each tile's orbit representative so it rotates with the map).
        let s1 = rng.next(), s2 = rng.next()
        for y in 0..<n {
            for x in 0..<n {
                let (rx, ry) = rep(x, y)
                let v = noise(Double(rx) * 0.08, Double(ry) * 0.08, s1) * 0.7 + noise(Double(rx) * 0.22, Double(ry) * 0.22, s1 &+ 5) * 0.3
                let t: Terrain = v > 0.68 ? .dirt : (v < 0.3 ? .moss : .grass)
                terrain[idx(x, y)] = t.rawValue
                elevation[idx(x, y)] = noise(Double(rx) * 0.05, Double(ry) * 0.05, s2) > 0.62 ? 1 : 0
            }
        }

        // Protected zones: bases, sites, centre.
        protect(start0.0, start0.1, 13)
        protect(center.0, center.1, 6)
        for s in sitesSector { protect(s.0, s.1, 6) }
        for y in 0..<n { for x in 0..<n where protected[idx(x, y)] { elevation[idx(x, y)] = 0 } }

        // Base resources: iron arc facing away from centre, gold on the side, forest behind.
        let away = base.angle
        resourceArc(.iron, start0.0, start0.1, angle: away, radius: 7.5, count: 8, spread: 1.6)
        resourceArc(.gold, start0.0, start0.1, angle: away + 1.75, radius: 8, count: 2, spread: 0.25)
        resourceArc(.wood, start0.0, start0.1, angle: away - 1.6, radius: 9.5, count: 9, spread: 1.0)

        // Site resources: every site has gold worth taking.
        for (i, s) in sitesSector.enumerated() {
            let a = atan2(s.1 - center.1, s.0 - center.0) + (i % 2 == 0 ? 0.6 : -0.6)
            resourceArc(.iron, s.0, s.1, angle: a, radius: 5, count: 5, spread: 1.2)
            resourceArc(.wood, s.0, s.1, angle: a + 2.2, radius: 5.5, count: 4, spread: 0.8)
            resourceArc(.gold, s.0, s.1, angle: a - 1.9, radius: 5, count: 2, spread: 0.4)
        }
        // Contested gold in the centre (two nodes per commander).
        for a in [base.angle + .pi / 4, base.angle - .pi / 4] {
            let p = polar(a, 5.5)
            placeResource(.gold, at: p.0, p.1)
        }

        // Obstacles (per sector; the symmetry supplies the rest).
        switch layout {
        case .riverbend:
            rivers(s1)
            var placed = 0, tries = 0
            while placed < 10 && tries < 60 {
                tries += 1
                let (x, y) = randomInSector(margin: 8)
                if distToBoundary(x, y) < 7 { continue }     // keep the river banks and fords open
                blob(x, y, rng.range(1.5, 3.5), .rock); placed += 1
            }
        case .crossroads:
            for _ in 0..<6 {
                let (x, y) = randomInSector(margin: 10)
                blob(x, y, rng.range(2, 4.5), rng.chance(0.25) ? .water : .rock)
            }
            // Ridges that funnel the road from each base to the centre.
            let r1 = polar(base.angle - 0.89, 0.181 * N), r2 = polar(base.angle + 0.89, 0.201 * N)
            blob(r1.0, r1.1, 4, .rock); blob(r2.0, r2.1, 3.5, .rock)
        case .highlands, .arena:
            for _ in 0..<16 {
                let (x, y) = randomInSector(margin: 8)
                blob(x, y, rng.range(1.5, 5), rng.chance(0.35) ? .water : .rock)
            }
        }
        // Three commanders share a round battlefield: the corners beyond it are crag.
        if k == 3 {
            for y in 0..<n { for x in 0..<n where !inPlay(Double(x) + 0.5, Double(y) + 0.5) {
                let i = idx(x, y)
                if !occupied[i] { terrain[i] = Terrain.rock.rawValue }
            } }
        }

        // Scattered forests.
        for _ in 0..<14 {
            let (x, y) = randomInSector(margin: 8)
            let (tx, ty) = tile((x, y))
            if inBounds(tx, ty) && !protected[idx(tx, ty)] { forestClump(x, y, rng.int(8) + 6) }
        }

        // Guarantee connectivity between every base and every site.
        let s0x = Int(start0.0), s0y = Int(start0.1)
        var targets: [(Double, Double)] = [center]
        for j in 1..<k { targets.append(rot(start0.0, start0.1, j)) }
        for s in sitesSector { for j in 0..<k { targets.append(rot(s.0, s.1, j)) } }
        for _ in 0..<4 {
            let r = reachable(from: s0x, s0y)
            var ok = true
            for t in targets where !r[idx(Int(t.0), Int(t.1))] {
                ok = false
                carve(t.0, t.1, center.0, center.1, width: 1.6)
                carve(start0.0, start0.1, center.0, center.1, width: 1.6)
            }
            if ok { break }
        }
        // Remove resource nodes stranded by obstacles.
        let r = reachable(from: s0x, s0y)
        let nn = n
        resources.removeAll { res in
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = res.x + dx, y = res.y + dy
                if x >= 0, y >= 0, x < nn, y < nn, r[y * nn + x] { return false }
            }
            return true
        }

        var sites: [(x: Double, y: Double)] = [(center.0, center.1)]
        for s in sitesSector { for j in 0..<k { let p = rot(s.0, s.1, j); sites.append((p.0, p.1)) } }
        let starts = (0..<k).map { hqOrigin(start0, $0) }
        return MapData(size: n, terrain: terrain, elevation: elevation, resources: resources,
                       starts: starts, sites: sites, name: layout.title)
    }
}
