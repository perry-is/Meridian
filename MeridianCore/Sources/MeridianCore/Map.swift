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
}

/// Static map description produced by the generator. Two-player maps are point-symmetric for fairness.
public struct MapData: Sendable {
    public let size: Int
    public var terrain: [UInt8]
    public var elevation: [UInt8]
    public var resources: [ResourceSpawn]
    /// HQ footprint origin tiles, one per start position.
    public var starts: [(x: Int, y: Int)]
    public var sites: [(x: Double, y: Double)]
    public var name: String

    @inline(__always) public func idx(_ x: Int, _ y: Int) -> Int { y * size + x }
    @inline(__always) public func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < size && y < size }
    public func terrainAt(_ x: Int, _ y: Int) -> Terrain { Terrain(rawValue: terrain[idx(x, y)]) ?? .grass }

    // MARK: Generation

    public static func generate(layout: MapLayout, seed: UInt64, size: Int = 112) -> MapData {
        var g = Generator(size: size, seed: seed &+ UInt64(layout.hashValueStable))
        return g.build(layout)
    }
}

extension MapLayout {
    var hashValueStable: Int {
        switch self { case .crossroads: return 11; case .riverbend: return 23; case .highlands: return 37; case .arena: return 41 }
    }
}

private struct Generator {
    let n: Int
    var rng: RNG
    var terrain: [UInt8]
    var elevation: [UInt8]
    var occupied: [Bool]        // resources and reserved tiles
    var protected: [Bool]       // never place obstacles here
    var resources: [ResourceSpawn] = []

    init(size: Int, seed: UInt64) {
        n = size
        rng = RNG(seed: seed)
        terrain = Array(repeating: Terrain.grass.rawValue, count: size * size)
        elevation = Array(repeating: 0, count: size * size)
        occupied = Array(repeating: false, count: size * size)
        protected = Array(repeating: false, count: size * size)
    }

    @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { y * n + x }
    @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool { x >= 1 && y >= 1 && x < n - 1 && y < n - 1 }
    func mirror(_ x: Int, _ y: Int) -> (Int, Int) { (n - 1 - x, n - 1 - y) }
    func mirrorD(_ x: Double, _ y: Double) -> (Double, Double) { (Double(n) - x, Double(n) - y) }

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

    mutating func setSym(_ x: Int, _ y: Int, _ t: Terrain) {
        guard inside(x, y) else { return }
        let (mx, my) = mirror(x, y)
        terrain[idx(x, y)] = t.rawValue
        terrain[idx(mx, my)] = t.rawValue
    }

    mutating func protect(_ cx: Double, _ cy: Double, _ r: Double) {
        let r2 = r * r
        for y in max(0, Int(cy - r))...min(n - 1, Int(cy + r)) {
            for x in max(0, Int(cx - r))...min(n - 1, Int(cx + r)) {
                if dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= r2 { protected[idx(x, y)] = true }
            }
        }
    }

    mutating func placeResourceSym(_ k: ResourceKind, _ x: Int, _ y: Int) {
        guard inside(x, y) else { return }
        let (mx, my) = mirror(x, y)
        let i = idx(x, y), j = idx(mx, my)
        guard !occupied[i], !occupied[j], Terrain(rawValue: terrain[i])!.groundPassable, Terrain(rawValue: terrain[j])!.groundPassable else { return }
        occupied[i] = true; occupied[j] = true
        resources.append(ResourceSpawn(kind: k, x: x, y: y))
        if i != j { resources.append(ResourceSpawn(kind: k, x: mx, y: my)) }
    }

    /// Arc of resource nodes around (cx,cy) facing angle a.
    mutating func resourceArc(_ k: ResourceKind, _ cx: Double, _ cy: Double, angle: Double, radius: Double, count: Int, spread: Double) {
        for i in 0..<count {
            let t = count == 1 ? 0 : (Double(i) / Double(count - 1) - 0.5) * spread
            let a = angle + t
            let x = Int(cx + cos(a) * radius), y = Int(cy + sin(a) * radius)
            placeResourceSym(k, x, y)
            if k == .wood { // forests are two rows deep
                let x2 = Int(cx + cos(a) * (radius + 1.2)), y2 = Int(cy + sin(a) * (radius + 1.2))
                placeResourceSym(k, x2, y2)
            }
        }
    }

    mutating func forestClump(_ cx: Double, _ cy: Double, _ count: Int) {
        for _ in 0..<count {
            let a = rng.range(0, 2 * .pi), r = rng.range(0, 3.2)
            let x = Int(cx + cos(a) * r), y = Int(cy + sin(a) * r)
            if inside(x, y) && !protected[idx(x, y)] { placeResourceSym(.wood, x, y) }
        }
    }

    mutating func blob(_ cx: Double, _ cy: Double, _ r: Double, _ t: Terrain) {
        let r2 = r * r
        for y in max(1, Int(cy - r - 1))...min(n - 2, Int(cy + r + 1)) {
            for x in max(1, Int(cx - r - 1))...min(n - 2, Int(cx + r + 1)) {
                let wob = noise(Double(x) * 0.35, Double(y) * 0.35, 99) * 0.8 + 0.6
                if dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= r2 * wob {
                    let (mx, my) = mirror(x, y)
                    if !protected[idx(x, y)] && !protected[idx(mx, my)] && !occupied[idx(x, y)] && !occupied[idx(mx, my)] {
                        setSym(x, y, t)
                    }
                }
            }
        }
    }

    mutating func carve(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, width: Double) {
        let steps = Int(max(abs(bx - ax), abs(by - ay)) * 2) + 1
        for s in 0...steps {
            let t = Double(s) / Double(steps)
            let cx = ax + (bx - ax) * t, cy = ay + (by - ay) * t
            for y in Int(cy - width)...Int(cy + width) {
                for x in Int(cx - width)...Int(cx + width) where inside(x, y) {
                    if dist2(Double(x) + 0.5, Double(y) + 0.5, cx, cy) <= width * width {
                        let (mx, my) = mirror(x, y)
                        for (px, py) in [(x, y), (mx, my)] {
                            let i = idx(px, py)
                            if !Terrain(rawValue: terrain[i])!.groundPassable { terrain[i] = Terrain.dirt.rawValue }
                        }
                    }
                }
            }
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

    mutating func build(_ layout: MapLayout) -> MapData {
        let N = Double(n)
        if layout == .arena {
            // Open battlefield: purely cosmetic passable variety (dirt and moss), no obstacles.
            let s1 = rng.next()
            for y in 0..<n { for x in 0..<n {
                let v = noise(Double(x) * 0.07, Double(y) * 0.07, s1)
                terrain[idx(x, y)] = (v > 0.62 ? Terrain.dirt : (v < 0.2 ? Terrain.moss : Terrain.grass)).rawValue
            } }
            return MapData(size: n, terrain: terrain, elevation: elevation, resources: [],
                           starts: [(x: 4, y: 4), (x: n - 8, y: n - 8)], sites: [], name: layout.title)
        }
        var start0: (Double, Double)
        var sitesHalf: [(Double, Double)] = []   // mirrored
        let center = (N / 2, N / 2)
        switch layout {
        case .crossroads:
            start0 = (0.15 * N, 0.15 * N)
            sitesHalf = [(0.36 * N, 0.13 * N), (0.13 * N, 0.36 * N), (0.24 * N, 0.76 * N)]
        case .riverbend:
            start0 = (0.11 * N, 0.5 * N)
            sitesHalf = [(0.27 * N, 0.22 * N), (0.27 * N, 0.78 * N), (0.5 * N, 0.13 * N)]
        case .highlands, .arena:
            start0 = (0.14 * N, 0.84 * N)
            sitesHalf = [(0.17 * N, 0.56 * N), (0.4 * N, 0.85 * N), (0.30 * N, 0.25 * N)]
        }
        let start1 = mirrorD(start0.0, start0.1)

        // Ground texture variation.
        let s1 = rng.next(), s2 = rng.next()
        for y in 0..<n {
            for x in 0..<n {
                let v = noise(Double(x) * 0.08, Double(y) * 0.08, s1) * 0.7 + noise(Double(x) * 0.22, Double(y) * 0.22, s1 &+ 5) * 0.3
                let (mx, my) = mirror(x, y)
                if x + y * n > mx + my * n { continue }  // write each symmetric pair once
                let t: Terrain = v > 0.68 ? .dirt : (v < 0.3 ? .moss : .grass)
                terrain[idx(x, y)] = t.rawValue; terrain[idx(mx, my)] = t.rawValue
                let e = noise(Double(x) * 0.05, Double(y) * 0.05, s2) > 0.62 ? UInt8(1) : 0
                elevation[idx(x, y)] = e; elevation[idx(mx, my)] = e
            }
        }

        // Protected zones: bases, sites, center.
        protect(start0.0, start0.1, 13); protect(start1.0, start1.1, 13)
        protect(center.0, center.1, 6)
        for s in sitesHalf { protect(s.0, s.1, 6); let m = mirrorD(s.0, s.1); protect(m.0, m.1, 6) }
        for y in 0..<n { for x in 0..<n where protected[idx(x, y)] { elevation[idx(x, y)] = 0 } }

        // Base resources: iron arc facing away from center, gold on the side, forest behind.
        let away = atan2(start0.1 - center.1, start0.0 - center.0)
        resourceArc(.iron, start0.0, start0.1, angle: away, radius: 7.5, count: 8, spread: 1.6)
        resourceArc(.gold, start0.0, start0.1, angle: away + 1.75, radius: 8, count: 2, spread: 0.25)
        resourceArc(.wood, start0.0, start0.1, angle: away - 1.6, radius: 9.5, count: 9, spread: 1.0)

        // Site resources.
        for (i, s) in sitesHalf.enumerated() {
            let a = atan2(s.1 - center.1, s.0 - center.0) + (i % 2 == 0 ? 0.6 : -0.6)
            resourceArc(.iron, s.0, s.1, angle: a, radius: 5, count: 5, spread: 1.2)
            resourceArc(.wood, s.0, s.1, angle: a + 2.2, radius: 5.5, count: 4, spread: 0.8)
            resourceArc(.gold, s.0, s.1, angle: a - 1.9, radius: 5, count: 2, spread: 0.4)   // every site has gold worth taking
        }
        // Contested gold in the center.
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            let x = Int(center.0 + cos(a) * 5.5), y = Int(center.1 + sin(a) * 5.5)
            if k < 2 { placeResourceSym(.gold, x, y) }
        }

        // Obstacles.
        switch layout {
        case .riverbend:
            for y in 0..<n {
                let wob = sin(Double(y) * 0.11) * 4 + noise(0.5, Double(y) * 0.1, s1) * 3
                let cx = N / 2 + wob
                for x in Int(cx - 2.5)...Int(cx + 2.5) where inside(x, y) {
                    let fy = Double(y) / N
                    let ford = abs(fy - 0.5) < 0.05 || abs(fy - 0.13) < 0.04 || abs(fy - 0.87) < 0.04 || abs(fy - 0.31) < 0.025 || abs(fy - 0.69) < 0.025
                    let (mx, my) = mirror(x, y)
                    if !ford && !occupied[idx(x, y)] && !occupied[idx(mx, my)] { setSym(x, y, .water) }
                }
            }
            for _ in 0..<10 { blob(rng.range(8, N / 2 - 6), rng.range(8, N - 8), rng.range(1.5, 3.5), .rock) }
        case .crossroads:
            for _ in 0..<12 {
                let x = rng.range(10, N - 10), y = rng.range(10, N - 10)
                if x + y > N { continue }
                blob(x, y, rng.range(2, 4.5), rng.chance(0.25) ? .water : .rock)
            }
            // Ridges that funnel the diagonal.
            blob(0.32 * N, 0.52 * N, 4, .rock); blob(0.52 * N, 0.30 * N, 3.5, .rock)
        case .highlands, .arena:
            for _ in 0..<16 {
                let x = rng.range(8, N - 8), y = rng.range(8, N - 8)
                blob(x, y, rng.range(1.5, 5), rng.chance(0.35) ? .water : .rock)
            }
        }

        // Scattered forests.
        for _ in 0..<14 {
            let x = rng.range(8, N - 8), y = rng.range(8, N - 8)
            if !protected[idx(Int(x), Int(y))] { forestClump(x, y, rng.int(8) + 6) }
        }

        // Guarantee connectivity between both bases and all sites.
        let s0x = Int(start0.0), s0y = Int(start0.1)
        var targets: [(Double, Double)] = [start1, center]
        for s in sitesHalf { targets.append(s); targets.append(mirrorD(s.0, s.1)) }
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
        for s in sitesHalf { sites.append((s.0, s.1)); let m = mirrorD(s.0, s.1); sites.append((m.0, m.1)) }
        let hq0 = (x: Int(start0.0) - 2, y: Int(start0.1) - 2)
        let hq1 = (x: n - 4 - hq0.x, y: n - 4 - hq0.y)
        return MapData(size: n, terrain: terrain, elevation: elevation, resources: resources,
                       starts: [hq0, hq1], sites: sites, name: layout.title)
    }
}
