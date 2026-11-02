import XCTest
@testable import MeridianCore

/// Multi-commander battlefields, teams and victory modes.
final class TeamTests: XCTestCase {
    let data = GameData.shared

    /// Flood fill over the navigation grid from a tile.
    func reachable(_ w: World, from x: Int, _ y: Int) -> [Bool] {
        let n = w.map.size
        var seen = [Bool](repeating: false, count: n * n)
        var stack = [(x, y)]
        seen[y * n + x] = true
        while let (cx, cy) = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < n, ny < n, !seen[ny * n + nx], !w.nav.isBlocked(nx, ny) else { continue }
                seen[ny * n + nx] = true; stack.append((nx, ny))
            }
        }
        return seen
    }

    func testBiggerMapsForMoreCommanders() {
        XCTAssertEqual(MatchConfig.mapSize(players: 2, quick: false), 112)
        XCTAssertGreaterThan(MatchConfig.mapSize(players: 3, quick: false), 112)
        XCTAssertGreaterThan(MatchConfig.mapSize(players: 4, quick: false), MatchConfig.mapSize(players: 3, quick: false))
        XCTAssertGreaterThan(MatchConfig.mapSize(players: 4, quick: true), MatchConfig.mapSize(players: 2, quick: true))
        XCTAssertEqual(MatchConfig(factions: [.humans, .aliens, .machines, .humans]).mapSize, MatchConfig.mapSize(players: 4, quick: false))
    }

    /// Four-player maps are symmetric under a quarter turn, tile for tile.
    func testFourPlayerMapsRotationallySymmetric() {
        for layout in MapLayout.playable {
            let m = MapData.generate(layout: layout, seed: 5, size: MatchConfig.mapSize(players: 4, quick: false), players: 4)
            let n = m.size
            XCTAssertEqual(m.starts.count, 4)
            XCTAssertEqual(m.sites.count, 9, "\(layout)")
            for y in 0..<n { for x in 0..<n {
                XCTAssertEqual(m.terrain[y * n + x], m.terrain[x * n + (n - 1 - y)], "\(layout) tile \(x),\(y)")
            } }
            // Resources rotate too.
            let set = Set(m.resources.map { $0.y * n + $0.x })
            for r in m.resources { XCTAssertTrue(set.contains(r.x * n + (n - 1 - r.y)), "\(layout) resource \(r.x),\(r.y) has no rotated twin") }
            XCTAssertGreaterThan(m.resources.filter { $0.kind == .gold }.count, 8)
        }
    }

    /// Every commander on 3- and 4-player maps starts with a full economy and can walk to every other base and site.
    func testMultiplayerStartsSuppliedAndConnected() {
        for players in [3, 4] {
            for layout in MapLayout.playable {
                for (seed, quick) in [(3, false), (42, false), (777, true)] as [(UInt64, Bool)] {
                    let factions = Array(repeating: Faction.humans, count: players)
                    let w = World(config: MatchConfig(factions: factions, layout: layout, seed: seed,
                                                      mapSize: MatchConfig.mapSize(players: players, quick: quick)), data: quick ? .quick : .shared)
                    XCTAssertEqual(w.map.starts.count, players)
                    XCTAssertEqual(w.sites.count, 2 * players + 1, "\(players)p \(layout) \(seed) sites")
                    let hq0 = w.buildings(of: 0)[0]
                    let r = reachable(w, from: Int(hq0.x) + 3, Int(hq0.y))
                    for p in 0..<players {
                        let hq = w.buildings(of: p)[0]
                        var c = [0, 0, 0]
                        for e in w.entities where e.isResource && e.alive && dist2(e.x, e.y, hq.x, hq.y) < 13 * 13 { c[e.type] += 1 }
                        XCTAssertGreaterThanOrEqual(c[0], 6, "\(players)p \(layout) \(seed) P\(p) iron")
                        XCTAssertGreaterThanOrEqual(c[1], 2, "\(players)p \(layout) \(seed) P\(p) gold")
                        XCTAssertGreaterThanOrEqual(c[2], 8, "\(players)p \(layout) \(seed) P\(p) wood")
                        XCTAssertTrue(r[w.tileIndex(hq.x + 3, hq.y)], "\(players)p \(layout) \(seed) P\(p) base unreachable")
                        XCTAssertEqual(w.players[p].team, p, "free-for-all by default")
                    }
                    for (i, s) in w.sites.enumerated() {
                        let (ox, oy) = w.nav.nearestOpen(Int(s.x), Int(s.y))
                        XCTAssertTrue(r[oy * w.map.size + ox], "\(players)p \(layout) \(seed) site \(i) unreachable")
                    }
                }
            }
        }
    }

    /// Allies share vision, never shoot each other and capture sites together.
    func testAlliesShareVisionAndCaptureTogether() {
        let w = World(config: MatchConfig(factions: [.humans, .machines, .aliens, .humans], teams: [0, 0, 1, 1], layout: .arena, seed: 2, mapSize: 64))
        w.sandbox = true; w.clearAll()
        XCTAssertTrue(w.isAlly(0, 1)); XCTAssertFalse(w.isEnemy(0, 1)); XCTAssertTrue(w.isEnemy(1, 2)); XCTAssertFalse(w.isAlly(0, 0))
        let scout = w.spawnUnit(data.unitIndex["m_runner"]!, owner: 1, x: 50, y: 50)
        let foe = w.spawnUnit(data.unitIndex["a_mantis"]!, owner: 2, x: 52, y: 50)
        w.commandHold([scout.id, foe.id])
        for _ in 0..<10 { w.step() }
        XCTAssertGreaterThan(w.players[0].visible[w.tileIndex(50, 50)], 0, "an ally's unit reveals the map for its teammate")
        XCTAssertTrue(w.canSee(0, foe), "a teammate's sighting is shared")
        XCTAssertFalse(w.canSee(3, scout) && w.players[3].visible[w.tileIndex(50, 50)] > 0, "enemies do not get the shared vision")

        // Two allied soldiers side by side stay unharmed; an enemy next to them does not.
        let a = w.spawnUnit(data.unitIndex["h_ranger"]!, owner: 0, x: 20, y: 20)
        let b = w.spawnUnit(data.unitIndex["m_arc"]!, owner: 1, x: 21, y: 20)
        for _ in 0..<60 { w.step() }
        XCTAssertEqual(a.hp, a.maxHp); XCTAssertEqual(b.hp, b.maxHp)
        let c = w.spawnUnit(data.unitIndex["a_skitter"]!, owner: 3, x: 22, y: 20)
        for _ in 0..<60 { w.step() }
        XCTAssertLessThan(c.hp, c.maxHp)
    }

    func testTeamSiteCapture() {
        let w = World(config: MatchConfig(factions: [.humans, .machines, .aliens], teams: [0, 0, 1], layout: .crossroads, seed: 5))
        let s = w.sites[0]
        let a = w.spawnUnit(data.unitIndex["h_ranger"]!, owner: 0, x: s.x - 0.5, y: s.y)
        let b = w.spawnUnit(data.unitIndex["m_arc"]!, owner: 1, x: s.x + 0.5, y: s.y)
        let bb = w.spawnUnit(data.unitIndex["m_arc"]!, owner: 1, x: s.x, y: s.y + 0.5)
        w.commandHold([a.id, b.id, bb.id])
        for _ in 0..<(20 * 25) { w.step() }
        XCTAssertFalse(w.sites[0].contested, "allies on one site do not contest it")
        XCTAssertEqual(w.sites[0].owner, 1, "the ally with the most units on the site takes it")
        XCTAssertEqual(w.sitesHeld(team: 0), 1)
    }

    /// A team wins once every enemy commander has lost their structures; eliminated commanders' forces disband.
    func testTeamVictoryAndElimination() {
        let w = World(config: MatchConfig(factions: [.humans, .machines, .aliens, .humans], teams: [0, 0, 1, 1], layout: .crossroads, seed: 9))
        let straggler = w.spawnUnit(data.unitIndex["a_mantis"]!, owner: 2, x: 30, y: 30)
        for b in w.buildings(of: 2) { w.kill(b, killer: 0) }
        for _ in 0..<25 { w.step() }
        XCTAssertTrue(w.players[2].defeated)
        XCTAssertFalse(straggler.alive, "an eliminated commander's units disband")
        XCTAssertNil(w.winner, "team 1 still has a commander standing")
        for b in w.buildings(of: 3) { w.kill(b, killer: 1) }
        for _ in 0..<25 { w.step() }
        XCTAssertEqual(w.winningTeam, 0)
        XCTAssertEqual(w.won(by: 1), true); XCTAssertEqual(w.won(by: 0), true); XCTAssertEqual(w.won(by: 3), false)
        XCTAssertEqual(w.victoryReason, "All enemies eliminated")
    }

    /// Dominance only ends matches in Dominance mode; in Annihilation holding every site wins nothing by itself.
    func testVictoryModes() {
        func holdEverything(_ victory: VictoryMode) -> World {
            let w = World(config: MatchConfig(factions: [.humans, .aliens], victory: victory, layout: .riverbend, seed: 4))
            for i in w.sites.indices { w.sites[i].owner = 0; w.sites[i].control = 1 }
            w.time = data.rules.territory.dominanceStart + 1
            for _ in 0..<Int((data.rules.territory.dominanceSeconds + 10) * 20) where w.winner == nil { w.step() }
            return w
        }
        XCTAssertNil(holdEverything(.annihilation).winner)
        let d = holdEverything(.dominance)
        XCTAssertEqual(d.winner, 0); XCTAssertEqual(d.victoryReason, "Territorial dominance")
    }

    /// Team settings survive a save and the restored match plays on identically.
    func testTeamSaveRoundTrip() throws {
        let cfg = MatchConfig(factions: [.humans, .machines, .aliens, .humans], teams: [0, 1, 1, 0], victory: .annihilation, layout: .highlands, seed: 11)
        let a = Match(config: cfg, ai: (1...3).map { (player: $0, difficulty: Difficulty.normal, strategy: AIStrategy.balanced) })
        for _ in 0..<(20 * 120) { a.step() }
        let b = Match.load(try JSONDecoder().decode(MatchSave.self, from: JSONEncoder().encode(a.save())))
        XCTAssertEqual(b.world.teamOf, [0, 1, 1, 0]); XCTAssertEqual(b.world.config.victory, .annihilation)
        XCTAssertEqual(b.world.map.size, a.world.map.size); XCTAssertEqual(b.ais.count, 3)
        a.world.nav.invalidate()
        for _ in 0..<(20 * 30) { a.step(); b.step() }
        XCTAssertEqual(a.world.stateHash(), b.world.stateHash())
    }

    /// Four computer commanders fight it out to a result.
    func testFourPlayerMatchFinishes() {
        let m = Match(config: MatchConfig(factions: [.humans, .machines, .aliens, .machines], teams: [0, 0, 1, 1], layout: .crossroads, seed: 13),
                      ai: (0..<4).map { (player: $0, difficulty: Difficulty.normal, strategy: AIStrategy.balanced) })
        m.timeLimit = 2400
        while m.world.winner == nil { m.step() }
        XCTAssertNotNil(m.world.winningTeam)
        XCTAssertTrue(m.world.players.allSatisfy { $0.stats.unitsProduced > 5 })
    }
}
