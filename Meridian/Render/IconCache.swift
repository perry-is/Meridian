import CoreGraphics
import Foundation
import MeridianCore

/// Unit and building icons for menus (command card, tech tree, selection tiles).
/// Icons used to be read from whichever texture bank happened to be cached, and that bank is swapped
/// when the menu backdrop or a new match builds its own. That made menu images drop in and out. Icons
/// now live here permanently: seeded from each bank as it is built, otherwise drawn on first use.
enum IconCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var units: [Int: CGImage] = [:]
    nonisolated(unsafe) private static var buildings: [Int: CGImage] = [:]

    static func unit(_ i: Int) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = units[i] { return c }
        let d = GameData.shared
        guard d.units.indices.contains(i) else { return nil }
        let img = UnitArt.render(d.units[i], team: TeamColor.rgb(0))
        units[i] = img
        return img
    }

    static func building(_ i: Int) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = buildings[i] { return c }
        let d = GameData.shared
        guard d.buildings.indices.contains(i) else { return nil }
        let img = WorldArt.building(d.buildings[i], team: TeamColor.rgb(0))
        buildings[i] = img
        return img
    }

    /// Keeps icons a texture bank already drew (the player's colours), so menus never redraw them.
    static func seed(units u: [Int: CGImage], buildings b: [Int: CGImage]) {
        lock.lock(); defer { lock.unlock() }
        for (k, v) in u where units[k] == nil { units[k] = v }
        for (k, v) in b where buildings[k] == nil { buildings[k] = v }
    }

    /// Draws every icon of a faction ahead of time (called while a match loads).
    static func warm(_ f: Faction) {
        let d = GameData.shared
        for u in d.unitIDs(f) { _ = unit(u) }
        for b in d.buildingIDs(f) { _ = building(b) }
    }
}
