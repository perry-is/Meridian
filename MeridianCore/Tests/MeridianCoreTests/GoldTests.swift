import XCTest
@testable import MeridianCore

/// Every base and every strategic site has gold nearby.
final class GoldSurvey: XCTestCase {
    func testGoldAtBasesAndSites() {
        for layout in MapLayout.playable { for seed in [3, 42, 777, 1234, 99] as [UInt64] { for quick in [false, true] {
            let w = World(config: MatchConfig(factions: [.humans, .machines], layout: layout, seed: seed, mapSize: quick ? GameData.quickMapSize : MatchConfig.defaultMapSize), data: quick ? .quick : .shared)
            func gold(_ x: Double, _ y: Double, _ r: Double) -> Int { w.entities.filter { $0.isResource && $0.alive && $0.type == ResourceKind.gold.rawValue && dist2($0.x, $0.y, x, y) < r * r }.count }
            let bases = (0..<2).map { p -> Int in let h = w.buildings(of: p)[0]; return gold(h.x, h.y, 13) }
            let sites = w.sites.map { gold($0.x, $0.y, 9) }
            let total = w.entities.filter { $0.isResource && $0.type == ResourceKind.gold.rawValue }.count
            XCTAssertTrue(bases.allSatisfy { $0 >= 2 } && sites.allSatisfy { $0 >= 2 }, "\(layout) \(seed) gold bases \(bases) sites \(sites)")
            print("SURVEY \(layout) \(seed): bases \(bases) sites \(sites) total \(total)")
        } } }
    }
}
