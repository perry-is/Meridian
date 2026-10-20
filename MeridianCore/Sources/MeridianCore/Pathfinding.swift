import Foundation

/// Distance field toward a goal set, shared by every unit heading to the same place.
public final class FlowField {
    public let dist: [Float]
    var lastUsed: Int
    init(dist: [Float], tick: Int) { self.dist = dist; self.lastUsed = tick }
}

/// Ground navigation grid with an LRU cache of Dijkstra flow fields.
public final class NavGrid {
    public let n: Int
    public private(set) var blocked: [Bool]
    public private(set) var terrainBlocked: [Bool]
    public var version = 0
    private var cache: [Int: FlowField] = [:]
    private var heap = MinHeap()
    public var fieldsBuiltThisTick = 0
    public var fieldBudgetPerTick = 16
    public var totalFieldsBuilt = 0
    var tick = 0

    init(map: MapData) {
        n = map.size
        terrainBlocked = map.terrain.map { !(Terrain(rawValue: $0)?.groundPassable ?? true) }
        blocked = terrainBlocked
    }

    @inline(__always) public func isBlocked(_ x: Int, _ y: Int) -> Bool {
        x < 0 || y < 0 || x >= n || y >= n || blocked[y * n + x]
    }

    func setBlocked(_ x: Int, _ y: Int, _ b: Bool) {
        guard x >= 0, y >= 0, x < n, y < n else { return }
        let i = y * n + x
        let v = b || terrainBlocked[i]
        if blocked[i] != v { blocked[i] = v; invalidate() }
    }

    func invalidate() { version += 1; cache.removeAll(keepingCapacity: true) }

    /// Straight-line walkability using a conservative supercover walk over tiles.
    public func lineClear(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
        let dx = bx - ax, dy = by - ay
        let len = max(abs(dx), abs(dy))
        if len < 0.01 { return true }
        let steps = Int(len * 2.5) + 1
        for s in 1...steps {
            let t = Double(s) / Double(steps)
            if isBlocked(Int(ax + dx * t), Int(ay + dy * t)) { return false }
        }
        return true
    }

    /// Nearest unblocked tile to (x,y) by expanding rings.
    public func nearestOpen(_ x: Int, _ y: Int) -> (Int, Int) {
        if !isBlocked(x, y) { return (x, y) }
        for r in 1..<n {
            var best: (Int, Int)? = nil
            var bd = Int.max
            for yy in (y - r)...(y + r) {
                for xx in (x - r)...(x + r) where abs(xx - x) == r || abs(yy - y) == r {
                    if !isBlocked(xx, yy) {
                        let d = (xx - x) * (xx - x) + (yy - y) * (yy - y)
                        if d < bd { bd = d; best = (xx, yy) }
                    }
                }
            }
            if let b = best { return b }
        }
        return (x, y)
    }

    /// Field to a single tile. Returns nil when the per-tick budget is exhausted (caller steers directly).
    func field(toTileX gx: Int, _ gy: Int) -> FlowField? {
        let (ox, oy) = nearestOpen(clamp(gx, 0, n - 1), clamp(gy, 0, n - 1))
        let key = oy * n + ox
        if let f = cache[key] { f.lastUsed = tick; return f }
        guard fieldsBuiltThisTick < fieldBudgetPerTick else { return nil }
        let f = FlowField(dist: build(goals: [key]), tick: tick)
        store(key, f)
        return f
    }

    /// Field toward the ring of open tiles around a rectangular footprint (buildings, resource nodes).
    func field(toRectX x0: Int, _ y0: Int, size: Int) -> FlowField? {
        let key = -(1 + (y0 * n + x0) * 8 + size)
        if let f = cache[key] { f.lastUsed = tick; return f }
        guard fieldsBuiltThisTick < fieldBudgetPerTick else { return nil }
        var goals: [Int] = []
        for y in (y0 - 1)...(y0 + size) {
            for x in (x0 - 1)...(x0 + size) where x == x0 - 1 || y == y0 - 1 || x == x0 + size || y == y0 + size {
                if !isBlocked(x, y) { goals.append(y * n + x) }
            }
        }
        if goals.isEmpty { let (ox, oy) = nearestOpen(x0, y0); goals = [oy * n + ox] }
        let f = FlowField(dist: build(goals: goals), tick: tick)
        store(key, f)
        return f
    }

    private func store(_ key: Int, _ f: FlowField) {
        fieldsBuiltThisTick += 1
        totalFieldsBuilt += 1
        if cache.count >= 64 {
            if let oldest = cache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key { cache.removeValue(forKey: oldest) }
        }
        cache[key] = f
    }

    private func build(goals: [Int]) -> [Float] {
        var dist = [Float](repeating: .infinity, count: n * n)
        heap.removeAll()
        for g in goals { dist[g] = 0; heap.push(0, Int32(g)) }
        let n = self.n
        blocked.withUnsafeBufferPointer { blk in
            dist.withUnsafeMutableBufferPointer { d in
                while let (c, i32) = heap.pop() {
                    let i = Int(i32)
                    if c > d[i] { continue }
                    let x = i % n, y = i / n
                    // 8-neighbourhood without corner cutting
                    for k in 0..<8 {
                        let dx = NavGrid.dxs[k], dy = NavGrid.dys[k]
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || ny < 0 || nx >= n || ny >= n { continue }
                        let j = ny * n + nx
                        if blk[j] { continue }
                        if dx != 0 && dy != 0 && (blk[y * n + nx] || blk[ny * n + x]) { continue }
                        let nc = c + (dx != 0 && dy != 0 ? 1.4142 : 1)
                        if nc < d[j] { d[j] = nc; heap.push(nc, Int32(j)) }
                    }
                }
            }
        }
        return dist
    }

    static let dxs = [1, -1, 0, 0, 1, 1, -1, -1]
    static let dys = [0, 0, 1, -1, 1, -1, 1, -1]

    /// Direction to steer at world position (x,y) following the field. Returns nil if unreachable.
    func direction(_ f: FlowField, _ x: Double, _ y: Double) -> (Double, Double)? {
        let tx = Int(x), ty = Int(y)
        guard tx >= 0, ty >= 0, tx < n, ty < n else { return nil }
        let here = f.dist[ty * n + tx]
        var best = here
        var bx = 0, by = 0
        for k in 0..<8 {
            let dx = NavGrid.dxs[k], dy = NavGrid.dys[k]
            let nx = tx + dx, ny = ty + dy
            if nx < 0 || ny < 0 || nx >= n || ny >= n { continue }
            if dx != 0 && dy != 0 && (isBlocked(nx, ty) || isBlocked(tx, ny)) { continue }
            let v = f.dist[ny * n + nx]
            if v < best { best = v; bx = dx; by = dy }
        }
        if bx == 0 && by == 0 {
            if here.isInfinite { return nil }
            return (0, 0)
        }
        // Aim at the neighbouring tile centre; this naturally slides units around corners.
        let cx = Double(tx + bx) + 0.5 - x, cy = Double(ty + by) + 0.5 - y
        let l = (cx * cx + cy * cy).squareRoot()
        return l > 0 ? (cx / l, cy / l) : (0, 0)
    }
}

/// Binary min-heap of (cost, index).
struct MinHeap {
    var keys: [Float] = []
    var vals: [Int32] = []
    mutating func removeAll() { keys.removeAll(keepingCapacity: true); vals.removeAll(keepingCapacity: true) }
    mutating func push(_ k: Float, _ v: Int32) {
        keys.append(k); vals.append(v)
        var i = keys.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if keys[p] <= keys[i] { break }
            keys.swapAt(p, i); vals.swapAt(p, i); i = p
        }
    }
    mutating func pop() -> (Float, Int32)? {
        guard !keys.isEmpty else { return nil }
        let r = (keys[0], vals[0])
        let lk = keys.removeLast(), lv = vals.removeLast()
        if !keys.isEmpty {
            keys[0] = lk; vals[0] = lv
            var i = 0
            let c = keys.count
            while true {
                let l = 2 * i + 1, rr = l + 1
                var m = i
                if l < c && keys[l] < keys[m] { m = l }
                if rr < c && keys[rr] < keys[m] { m = rr }
                if m == i { break }
                keys.swapAt(m, i); vals.swapAt(m, i); i = m
            }
        }
        return r
    }
}
