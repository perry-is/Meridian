import Foundation

/// Small deterministic PRNG (SplitMix64). All gameplay randomness goes through this so matches replay identically.
public struct RNG: Sendable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    public mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    public mutating func chance(_ p: Double) -> Bool { unit() < p }
}

@inline(__always) public func dist2(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let dx = ax - bx, dy = ay - by
    return dx * dx + dy * dy
}

@inline(__always) public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// FNV-1a style hash accumulator for determinism checks.
public struct StateHasher {
    public var h: UInt64 = 0xcbf29ce484222325
    public init() {}
    public mutating func add(_ v: UInt64) { h ^= v; h = h &* 0x100000001b3 }
    public mutating func add(_ v: Int) { add(UInt64(bitPattern: Int64(v))) }
    public mutating func add(_ v: Double) { add(v.bitPattern) }
}
