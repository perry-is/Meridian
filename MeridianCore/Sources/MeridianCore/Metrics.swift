import Foundation

/// Read-only battlefield analysis used by the tactical test harness. Never mutates simulation state.
public struct TacticalSample: Sendable {
    public var units = 0
    /// Ground units whose body intrudes into another ground unit by more than 15% of the combined radii.
    public var deepOverlaps = 0
    /// Largest number of ground units whose centres lie within 1.5 tiles of a single unit.
    public var maxDensity = 0
    /// Average number of neighbours within 1.5 tiles.
    public var meanDensity = 0.0
    /// Armed units that currently have a valid target inside weapon range.
    public var inRange = 0
    /// Armed units that have a target but are outside weapon range (chasing / blocked).
    public var outOfRange = 0
    /// Ground units intruding into an ENEMY ground unit (opposing lines interpenetrating).
    public var enemyIntrusions = 0
}

public struct UnitTrack: Sendable {
    public var x: Double, y: Double, t: Double
}

extension World {

    public func tacticalSample() -> TacticalSample {
        var s = TacticalSample()
        var densitySum = 0
        for e in entities where e.isUnit && e.onMap && !e.isMine {
            s.units += 1
            if let w = weapon(e), let t = entity(e.target), t.onMap {
                if edgeDist(e, t) <= w.range { s.inRange += 1 } else { s.outOfRange += 1 }
            }
            guard !e.isAir else { continue }
            var near = 0
            var deep = false
            var intr = false
            forEachNear(e.x, e.y, 1.5) { o in
                guard o.id != e.id, o.isUnit, !o.isAir, !o.isMine, o.onMap else { return }
                let d = dist2(e.x, e.y, o.x, o.y).squareRoot()
                if d <= 1.5 { near += 1 }
                if d < (e.radius + o.radius) * 0.85 { deep = true; if o.owner != e.owner { intr = true } }
            }
            if deep { s.deepOverlaps += 1 }
            if intr { s.enemyIntrusions += 1 }
            densitySum += near
            s.maxDensity = max(s.maxDensity, near)
        }
        let ground = entities.filter { $0.isUnit && $0.onMap && !$0.isAir && !$0.isMine }.count
        s.meanDensity = ground > 0 ? Double(densitySum) / Double(ground) : 0
        return s
    }

    /// Stamp an impassable rock rectangle (sandbox scenarios). Updates terrain and navigation.
    public func sandboxRock(x0: Int, y0: Int, x1: Int, y1: Int) {
        for y in max(0, y0)...min(map.size - 1, y1) {
            for x in max(0, x0)...min(map.size - 1, x1) {
                map.terrain[map.idx(x, y)] = Terrain.rock.rawValue
                nav.setTerrainBlocked(x, y)
            }
        }
    }

    /// Damage dealt is not stored per unit; harness uses value killed/lost from player stats.
    public func armedUnitCount(_ owner: Int) -> Int {
        entities.filter { $0.isUnit && $0.onMap && !$0.isMine && $0.owner == owner && weapon($0) != nil }.count
    }
}
