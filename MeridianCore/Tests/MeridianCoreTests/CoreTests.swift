import XCTest
@testable import MeridianCore

final class CoreTests: XCTestCase {
    let data = GameData.shared

    func testDataValid() {
        XCTAssertEqual(data.validate(), [])
        XCTAssertEqual(data.units.count, 45)
        for f in Faction.allCases {
            XCTAssertEqual(data.buildings.filter { $0.faction == f }.count, 8)
            // Every unit has a producer building of its faction.
            for u in data.units where u.faction == f {
                XCTAssertTrue(data.buildings.contains { $0.faction == f && $0.kind == u.producedAt }, u.id)
            }
        }
    }

    func testFactionMultipliersApplied() {
        let raw = try! GameData.load()
        _ = raw
        // Machines' Arc Sentry baseline 90 hp * 1.35; Aliens' Mantis 95 * 0.8.
        XCTAssertEqual(data.units[data.unitIndex["m_arc"]!].hp, (90 * 1.35).rounded())
        XCTAssertEqual(data.units[data.unitIndex["a_mantis"]!].hp, (95 * 0.8).rounded())
    }

    func testMapsSymmetricAndConnected() {
        for layout in MapLayout.playable {
            let m = MapData.generate(layout: layout, seed: 3)
            XCTAssertEqual(m.starts.count, 2)
            XCTAssertEqual(m.sites.count, 7)
            let n = m.size
            for y in 0..<n { for x in 0..<n { XCTAssertEqual(m.terrain[y * n + x], m.terrain[(n - 1 - y) * n + (n - 1 - x)]) } }
            XCTAssertGreaterThan(m.resources.filter { $0.kind == .gold }.count, 4)
        }
    }

    /// Every playable start has all three resources within reach of the HQ.
    func testStartsHaveNearbyResources() {
        for layout in MapLayout.playable {
            for seed in [1, 42, 99999] as [UInt64] {
                let w = World(config: MatchConfig(factions: [.humans, .aliens], layout: layout, seed: seed))
                for p in 0..<2 {
                    let hq = w.buildings(of: p)[0]
                    var c = [0, 0, 0]
                    for e in w.entities where e.isResource && e.alive && dist2(e.x, e.y, hq.x, hq.y) < 13 * 13 { c[e.type] += 1 }
                    XCTAssertGreaterThanOrEqual(c[0], 6, "\(layout) seed \(seed) P\(p) iron")
                    XCTAssertGreaterThanOrEqual(c[1], 2, "\(layout) seed \(seed) P\(p) gold")
                    XCTAssertGreaterThanOrEqual(c[2], 10, "\(layout) seed \(seed) P\(p) wood")
                }
            }
        }
    }

    func testDeterminism() {
        func run() -> UInt64 {
            let m = Match(config: MatchConfig(factions: [.humans, .aliens], layout: .riverbend, seed: 42),
                          ai: [(0, .normal, .balanced), (1, .normal, .aggressive)])
            for _ in 0..<(20 * 240) { m.step() }
            return m.world.stateHash()
        }
        XCTAssertEqual(run(), run())
    }

    func testWorkersGatherAndProduce() {
        let w = World(config: MatchConfig(factions: [.machines, .humans], seed: 2))
        let start = w.players[0].res[0]
        let workers = w.units(of: 0)
        let node = w.nearestResource(kind: .iron, x: workers[0].x, y: workers[0].y, maxDist: 20, owner: 0)!
        w.commandGather(workers.map { $0.id }, node: node.id)
        for _ in 0..<(20 * 40) { w.step() }
        XCTAssertGreaterThan(w.players[0].res[0], start + 40)
        let hq = w.buildings(of: 0)[0]
        XCTAssertNil(w.commandTrain(hq.id, unitType: data.worker(.machines)))
        let before = w.players[0].unitCount
        for _ in 0..<(20 * 20) { w.step() }
        XCTAssertEqual(w.players[0].unitCount, before + 1)
    }

    func testCombatArmorAndBonus() {
        let w = World(config: MatchConfig(factions: [.humans, .machines], layout: .arena, seed: 1, mapSize: 48))
        w.sandbox = true
        w.clearAll()
        let lancer = w.spawnUnit(data.unitIndex["h_lancer"]!, owner: 0, x: 10, y: 10)
        let walker = w.spawnUnit(data.unitIndex["m_bulwark"]!, owner: 1, x: 30, y: 30)
        let ranger = w.spawnUnit(data.unitIndex["h_ranger"]!, owner: 0, x: 12, y: 10)
        w.applyDamage(walker, 28, bonus: data.units[lancer.type].weapon!.bonus, attackerOwner: 0, sourceID: lancer.id)
        // 28 * 1.9 (armored) - 5 armor = 48.2
        XCTAssertEqual(walker.maxHp - walker.hp, 48.2, accuracy: 0.01)
        let hp = walker.hp
        w.applyDamage(walker, 9, bonus: nil, attackerOwner: 0, sourceID: ranger.id)
        // 9 - 5 = 4, above the 25% floor (2.25)
        XCTAssertEqual(hp - walker.hp, 4, accuracy: 0.01)
    }

    func testTerritoryCapture() {
        let w = World(config: MatchConfig(factions: [.aliens, .humans], seed: 5))
        let s = w.sites[0]
        var ids: [Int] = []
        for k in 0..<3 { ids.append(w.spawnUnit(data.unitIndex["a_mantis"]!, owner: 0, x: s.x + Double(k) * 0.5, y: s.y).id) }
        for _ in 0..<(20 * 25) { w.step() }
        XCTAssertEqual(w.sites[0].owner, 0)
        // Contest: enemies present freeze progress.
        let h = w.spawnUnit(data.unitIndex["h_ranger"]!, owner: 1, x: s.x + 1, y: s.y + 1)
        w.step(); w.step(); w.step(); w.step(); w.step()
        XCTAssertTrue(w.sites[0].contested || !h.alive)
    }

    func testTowerCostEscalates() {
        let w = World(config: MatchConfig(factions: [.humans, .aliens], seed: 1))
        let t = data.building(.humans, .tower)
        let c0 = w.buildingCost(0, t)
        w.players[0].towerCount = 2
        let c2 = w.buildingCost(0, t)
        XCTAssertGreaterThan(c2.iron, c0.iron)
    }

    func testFullAIMatchFinishes() {
        let m = Match(config: MatchConfig(factions: [.machines, .aliens], layout: .crossroads, seed: 7),
                      ai: [(0, .normal, .balanced), (1, .normal, .balanced)])
        m.timeLimit = 3600
        while m.world.winner == nil { m.step() }
        XCTAssertNotNil(m.world.winner)
        XCTAssertTrue(m.world.players.allSatisfy { $0.stats.unitsProduced > 10 })
    }
}

final class TacticsTests: XCTestCase {
    let data = GameData.shared

    func arena(_ f: [Faction] = [.humans, .machines]) -> World {
        let w = World(config: MatchConfig(factions: f, layout: .arena, seed: 3, mapSize: 64))
        w.sandbox = true; w.clearAll(); w.unlockAll(0); w.unlockAll(1)
        return w
    }

    /// Balanced formation: siege behind heavies/assault relative to the direction of travel.
    func testFormationRanksByRole() {
        let w = arena()
        var ids: [Int] = []
        for (k, id) in ["h_mortar", "h_mortar", "h_bastion", "h_breacher", "h_ranger", "h_ranger", "h_lancer", "h_medic"].enumerated() {
            ids.append(w.spawnUnit(data.unitIndex[id]!, owner: 0, x: 10 + Double(k % 3), y: 30 + Double(k / 3)).id)
        }
        w.commandMove(ids, x: 50, y: 30, attack: false, formation: .balanced)
        // Forward axis is +x: compare slot forward offsets.
        func fwd(_ name: String) -> Double { ids.compactMap { w.entity($0) }.filter { data.units[$0.type].id == name }.map { $0.formationDX }.reduce(0, +) / 2 }
        let mortar = ids.compactMap { w.entity($0) }.filter { data.units[$0.type].id == "h_mortar" }.map { $0.formationDX }.max()!
        let bastion = ids.compactMap { w.entity($0) }.first { data.units[$0.type].id == "h_bastion" }!.formationDX
        let ranger = ids.compactMap { w.entity($0) }.filter { data.units[$0.type].id == "h_ranger" }.map { $0.formationDX }.max()!
        XCTAssertGreaterThan(bastion, ranger, "front rank should lead the rifle line")
        XCTAssertGreaterThan(ranger, mortar, "artillery should trail the rifle line")
        _ = fwd
    }

    func testFormationsDeterministicAndDistinct() {
        func slots(_ f: Formation) -> [Double] {
            let w = arena()
            var ids: [Int] = []
            for k in 0..<24 { ids.append(w.spawnUnit(TacticalScenario.rosterUnits(.humans, 24, data: data)[k], owner: 0, x: 10 + Double(k % 6), y: 25 + Double(k / 6)).id) }
            w.commandMove(ids, x: 45, y: 30, attack: true, formation: f)
            return ids.compactMap { w.entity($0) }.flatMap { [$0.formationDX, $0.formationDY] }
        }
        XCTAssertEqual(slots(.balanced), slots(.balanced))
        XCTAssertNotEqual(slots(.balanced), slots(.assault))
        XCTAssertNotEqual(slots(.balanced), slots(.defensive))
    }

    /// Movement scenarios complete: everyone reaches the far side of a gapped wall.
    func testGroupNavigatesWall() {
        let w = World(config: MatchConfig(factions: [.humans, .machines], layout: .arena, seed: 21, mapSize: 112))
        let setup = TacticalScenario.wall.setup(w)
        let g = setup.groups[0]
        for _ in 0..<(20 * 45) { w.step() }
        let past = g.ids.compactMap { w.entity($0) }.filter { $0.x > Double(w.map.size) / 2 + 2 }.count
        XCTAssertEqual(past, g.ids.count, "all units should get through the gaps")
    }

    /// Ranged units give ground to slower melee attackers that target them.
    func testRangedKitesSlowMelee() {
        let w = arena([.humans, .machines])
        let r = w.spawnUnit(data.unitIndex["h_ranger"]!, owner: 0, x: 30, y: 30)
        let m = w.spawnUnit(data.unitIndex["m_shockframe"]!, owner: 1, x: 34, y: 30)
        w.commandHold([m.id]); m.order = .idle
        w.commandMove([m.id], x: 20, y: 30, attack: true)
        w.commandMove([r.id], x: 40, y: 30, attack: true)
        let x0 = r.x
        for _ in 0..<(20 * 4) { w.step() }
        XCTAssertLessThan(r.x, x0 + 1, "ranger should not walk into the shockframe")
    }
}
