import Foundation
import MeridianCore

/// Development setups for checking features by eye (and from UI tests) without playing up to them.
extension GameController {
    /// `-fogcheck`: the enemy HQ is seen at 60% health by a scout that then dies; the HQ drops to 25% in the fog.
    /// Selecting it should still show 60% and "last seen".
    func setupFogCheck() {
        guard let hq = world.buildings(of: enemyPlayer).first(where: { world.bdef($0).kind == .hq }) else { return }
        hq.hp = hq.maxHp * 0.6
        let scoutType = data.unitIDs(world.players[me].faction).first { data.units[$0].role == "scout" } ?? data.worker(world.players[me].faction)
        let o = world.nav.nearestOpen(Int(hq.x) + 4, Int(hq.y) + 4)
        let scout = world.spawnUnit(scoutType, owner: me, x: Double(o.0) + 0.5, y: Double(o.1) + 0.5)
        world.commandHold([scout.id])
        for _ in 0..<10 { match.step() }
        _ = isShown(hq)                         // what the renderer does each frame while it is in sight
        scout.hp = 0
        // Step until the scout is gone and the fog has closed over the HQ (fog refreshes every few ticks).
        var n = 0
        while (world.canSee(me, hq) || world.entity(scout.id) != nil) && n < 400 { match.step(); n += 1 }
        _ = isShown(hq)
        hq.hp = hq.maxHp * 0.25
        labFocus = (hq.x, hq.y)
        let id = hq.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.select([id]) }
    }

    /// `-beaconcheck`: the player holds the nearest neutral site with resources to spare; the site is selected so
    /// its installation menu shows, and the camera sits 14 tiles east of it (where a barracks should fit once a
    /// Beacon stands there).
    func setupBeaconCheck() {
        let p = world.players[me]
        p.res = [5000, 2000, 5000]
        guard let hq = world.buildings(of: me).first else { return }
        guard let i = world.sites.indices.filter({ world.sites[$0].owner < 0 })
            .min(by: { dist2(world.sites[$0].x, world.sites[$0].y, hq.x, hq.y) < dist2(world.sites[$1].x, world.sites[$1].y, hq.x, hq.y) }) else { return }
        world.sites[i].owner = me; world.sites[i].control = 1
        for _ in 0..<4 { match.step() }
        beaconCheckSite = i
        labFocus = (world.sites[i].x + 14, world.sites[i].y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.selectSite(i) }
    }

    /// Distance in tiles from the `-beaconcheck` site to the centre of the current placement ghost.
    var beaconCheckGhostDistance: Double? {
        guard let si = beaconCheckSite, let g = ghostTile, case .place(let t) = mode else { return nil }
        let s = Double(data.buildings[t].size)
        return dist2(Double(g.0) + s / 2, Double(g.1) + s / 2, world.sites[si].x, world.sites[si].y).squareRoot()
    }
}
