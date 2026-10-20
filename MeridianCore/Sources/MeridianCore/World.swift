import Foundation

/// Precomputed ability flags per unit definition (avoids string lookups in the hot loop).
public struct UnitTraits: Sendable {
    public var worker = false
    public var detector = false, detectRange = 0.0
    public var cloak = false, cloakStationary = false
    public var healBio = false, repairMech = false, healRate = 0.0, healRange = 0.0
    public var emp = false
    public var jam = false, jamRadius = 0.0, jamMult = 1.0
    public var slowField = false, slowRadius = 0.0, slowMult = 1.0, fieldDps = 0.0
    public var sporeCloud = false, cloudRadius = 0.0, cloudDps = 0.0, cloudDuration = 0.0, cloudSlow = 1.0
    public var mines = false
    public var setup = false, setupTime = 0.0
    public var modes = 0
    public var capacity = 0
    public var chain = false, chainCount = 0, chainFalloff = 0.5, chainRange = 0.0
    public var pierce = false, pierceLength = 0.0
    public var shred = false, shredAmount = 0.0, shredDuration = 0.0
    public var networkNode = false, nodeRadius = 0.0
    public var bloomNode = false, bloomRadius = 0.0
    public var regenAura = false, auraRegen = 0.0, auraRadius = 0.0
    public var fieldRepair = false, repairRate = 0.0, repairRadius = 0.0
    public var canCapture = false

    init(_ u: UnitDef) {
        let ab = Set(u.abilities ?? [])
        let p = u.params ?? [:]
        worker = u.role == "worker"
        detector = ab.contains("detector"); detectRange = p["detectRange"] ?? 0
        cloak = ab.contains("cloak"); cloakStationary = ab.contains("cloakStationary")
        healBio = ab.contains("healBio"); repairMech = ab.contains("repairMech")
        healRate = p["healRate"] ?? 0; healRange = p["healRange"] ?? 0
        emp = ab.contains("emp")
        jam = ab.contains("jamField"); jamRadius = p["jamRadius"] ?? 0; jamMult = p["jamIntervalMult"] ?? 1
        slowField = ab.contains("slowField"); slowRadius = p["slowRadius"] ?? 0; slowMult = p["slowMult"] ?? 1; fieldDps = p["fieldDps"] ?? 0
        sporeCloud = ab.contains("sporeCloud"); cloudRadius = p["cloudRadius"] ?? 0; cloudDps = p["cloudDps"] ?? 0
        cloudDuration = p["cloudDuration"] ?? 0; cloudSlow = p["cloudSlow"] ?? 1
        mines = ab.contains("mines")
        setup = ab.contains("setup"); setupTime = p["setupTime"] ?? 0
        if ab.contains("modes") { modes = 2 }
        capacity = Int(p["capacity"] ?? 0)
        chain = ab.contains("chain"); chainCount = Int(p["chainCount"] ?? 0); chainFalloff = p["chainFalloff"] ?? 0.5; chainRange = p["chainRange"] ?? 0
        pierce = ab.contains("pierce"); pierceLength = p["pierceLength"] ?? 0
        shred = ab.contains("armorShred"); shredAmount = p["shredAmount"] ?? 0; shredDuration = p["shredDuration"] ?? 0
        networkNode = ab.contains("networkNode"); nodeRadius = p["nodeRadius"] ?? 0
        bloomNode = ab.contains("bloomNode"); bloomRadius = p["bloomRadius"] ?? 0
        regenAura = ab.contains("regenAura"); auraRegen = p["auraRegen"] ?? 0; auraRadius = p["auraRadius"] ?? 0
        fieldRepair = ab.contains("fieldRepair"); repairRate = p["repairRate"] ?? 0; repairRadius = p["repairRadius"] ?? 0
        canCapture = u.domain == .ground && !worker
    }
}

public struct MatchConfig: Sendable {
    public var factions: [Faction]
    public var layout: MapLayout
    public var seed: UInt64
    public var mapSize: Int
    public var swapStarts: Bool
    public init(factions: [Faction], layout: MapLayout = .crossroads, seed: UInt64 = 1, mapSize: Int = 112, swapStarts: Bool = false) {
        self.factions = factions; self.layout = layout; self.seed = seed; self.mapSize = mapSize; self.swapStarts = swapStarts
    }
}

public final class World {
    public let data: GameData
    public let map: MapData
    public let nav: NavGrid
    public let config: MatchConfig
    public var players: [Player] = []
    public private(set) var entities: [Entity] = []
    var byID: [Entity?] = []
    public var projectiles: [Projectile] = []
    public var clouds: [Cloud] = []
    public var sites: [Site] = []
    public var tick = 0
    public var time = 0.0
    public let dt = 0.05
    public var rng: RNG
    public var events: [GameEvent] = []
    public var collectEvents = true
    public var winner: Int? = nil
    /// Sandbox worlds (combat simulations, stress tests) never end by elimination.
    public var sandbox = false
    public var victoryReason = ""
    public let traits: [UnitTraits]
    /// Tile -> building/resource id occupying it (-1 = none).
    public var occupant: [Int32]
    var nextID = 1

    // Spatial hash (rebuilt each tick)
    let cellSize = 4
    let cellsW: Int
    var cellStart: [Int32]
    var cellItems: [Int32]
    var cellCount: [Int32]

    public init(config: MatchConfig, data: GameData = .shared) {
        self.data = data
        self.config = config
        var m = MapData.generate(layout: config.layout, seed: config.seed, size: config.mapSize)
        if config.swapStarts { m.starts.swapAt(0, 1) }
        self.map = m
        self.nav = NavGrid(map: m)
        self.rng = RNG(seed: config.seed &* 7919)
        self.traits = data.units.map { UnitTraits($0) }
        occupant = Array(repeating: -1, count: m.size * m.size)
        cellsW = (m.size + cellSize - 1) / cellSize
        cellStart = Array(repeating: 0, count: cellsW * cellsW + 1)
        cellCount = Array(repeating: 0, count: cellsW * cellsW)
        cellItems = []
        setup()
    }

    // MARK: Setup

    private func setup() {
        for (i, f) in config.factions.enumerated() {
            players.append(Player(index: i, faction: f, data: data, mapSize: map.size))
        }
        let e = data.rules.economy
        for r in map.resources {
            let amt = r.kind == .iron ? e.ironNodeAmount : (r.kind == .gold ? e.goldNodeAmount : e.treeAmount)
            let ent = Entity(id: allocID(), kind: .resource, type: r.kind.rawValue, owner: -1,
                             x: Double(r.x) + 0.5, y: Double(r.y) + 0.5, hp: 1, radius: 0.5)
            ent.amount = amt
            ent.tileX = r.x; ent.tileY = r.y; ent.size = 1
            add(ent)
            occupy(ent, true)
        }
        for s in map.sites { sites.append(Site(x: s.x, y: s.y)) }
        for p in players {
            let st = map.starts[p.index % map.starts.count]
            let hqType = data.building(p.faction, .hq)
            let hq = spawnBuilding(hqType, owner: p.index, tileX: st.x, tileY: st.y, complete: true)
            let w = data.worker(p.faction)
            for k in 0..<e.startWorkers {
                let a = Double(k) / Double(e.startWorkers) * 2 * .pi
                let u = spawnUnit(w, owner: p.index, x: hq.x + cos(a) * 3.2, y: hq.y + sin(a) * 3.2)
                u.facing = a
            }
            // Starting workers begin mining the nearest iron.
            for u in units(of: p.index) {
                if let node = nearestResource(kind: .iron, x: u.x, y: u.y, maxDist: 14, owner: -1) { commandGather([u.id], node: node.id) }
            }
        }
        refreshZones()
        updateFog()
    }

    func allocID() -> Int { let i = nextID; nextID += 1; return i }

    func add(_ e: Entity) {
        entities.append(e)
        if byID.count <= e.id { byID.append(contentsOf: Array(repeating: nil, count: e.id - byID.count + 256)) }
        byID[e.id] = e
    }

    @inline(__always) public func entity(_ id: Int) -> Entity? {
        guard id >= 0, id < byID.count, let e = byID[id], e.alive else { return nil }
        return e
    }

    func occupy(_ e: Entity, _ on: Bool) {
        for y in e.tileY..<(e.tileY + e.size) {
            for x in e.tileX..<(e.tileX + e.size) where map.inBounds(x, y) {
                occupant[map.idx(x, y)] = on ? Int32(e.id) : -1
                nav.setBlocked(x, y, on)
            }
        }
    }

    @discardableResult
    public func spawnUnit(_ type: Int, owner: Int, x: Double, y: Double) -> Entity {
        let d = data.units[type]
        let p = players[owner]
        let hp = d.hp * p.mods.unit[type].hp
        let e = Entity(id: allocID(), kind: .unit, type: type, owner: owner, x: x, y: y, hp: hp, radius: d.radius)
        e.isAir = d.domain == .air
        if !e.isAir { pushOutOfBlocked(e) }
        add(e)
        p.unitCount += 1
        p.stats.peakUnits = max(p.stats.peakUnits, p.unitCount)
        return e
    }

    @discardableResult
    public func spawnBuilding(_ type: Int, owner: Int, tileX: Int, tileY: Int, complete: Bool) -> Entity {
        let d = data.buildings[type]
        let s = Double(d.size)
        let p = players[owner]
        let maxHp = d.hp * p.mods.building[type].hp
        let e = Entity(id: allocID(), kind: .building, type: type, owner: owner,
                       x: Double(tileX) + s / 2, y: Double(tileY) + s / 2, hp: complete ? maxHp : maxHp * 0.1, radius: s * 0.5)
        e.maxHp = maxHp
        e.tileX = tileX; e.tileY = tileY; e.size = d.size
        e.complete = complete
        e.buildProgress = complete ? 1 : 0
        add(e)
        occupy(e, true)
        if d.kind == .tower { p.towerCount += 1 }
        if complete { buildingCompleted(e) }
        return e
    }

    func buildingCompleted(_ e: Entity) {
        let p = players[e.owner]
        let d = data.buildings[e.type]
        e.complete = true
        e.buildProgress = 1
        p.completeBuildings[d.kind, default: 0] += 1
        p.completeBuildingIDs.insert(e.type)
        p.stats.buildingsBuilt += 1
        emit(.built(id: e.id))
        refreshZonesSoon = true
    }

    var refreshZonesSoon = false

    // MARK: Definitions / effective stats

    @inline(__always) public func udef(_ e: Entity) -> UnitDef { data.units[e.type] }
    @inline(__always) public func bdef(_ e: Entity) -> BuildingDef { data.buildings[e.type] }
    @inline(__always) public func trait(_ e: Entity) -> UnitTraits { traits[e.type] }

    public func tags(_ e: Entity) -> [String] {
        switch e.kind {
        case .unit: return udef(e).tags
        case .building: return ["structure", "armored"]
        case .resource: return []
        }
    }

    public func speed(_ e: Entity) -> Double {
        guard e.isUnit else { return 0 }
        let d = udef(e)
        var s = d.speed * players[e.owner].mods.unit[e.type].speed * e.slowMult
        if e.inBloom { s *= 1 + data.rules.territory.alienSpeedBonus }
        if e.mode == 1 && e.type == data.unitIndex["h_bastion"] { s = 0 }
        return s
    }

    public func armor(_ e: Entity) -> Double {
        var a: Double
        switch e.kind {
        case .unit:
            a = udef(e).armor + players[e.owner].mods.unit[e.type].armor
            if e.mode == 1, let p = udef(e).params?["braceArmor"] { a += p }
        case .building: a = bdef(e).armor + players[e.owner].mods.building[e.type].armor
        case .resource: a = 0
        }
        if e.shredUntil > time { a -= e.shredAmount }
        return a
    }

    public func sight(_ e: Entity) -> Double {
        switch e.kind {
        case .unit: return udef(e).sight + players[e.owner].mods.unit[e.type].sight
        case .building: return e.complete ? bdef(e).sight : 3
        case .resource: return 0
        }
    }

    public struct EffWeapon {
        public var damage: Double
        public var interval: Double
        public var range: Double
        public var minRange: Double
        public var ground: Bool
        public var air: Bool
        public var splash: Double
        public var speed: Double
        public var bonus: [String: Double]?
        public var style: String
    }

    public func weapon(_ e: Entity) -> EffWeapon? {
        var base: WeaponDef
        var mods: StatMods
        switch e.kind {
        case .unit:
            guard let w = udef(e).weapon else { return nil }
            base = w; mods = players[e.owner].mods.unit[e.type]
        case .building:
            guard e.complete, let w = bdef(e).weapon else { return nil }
            base = w; mods = players[e.owner].mods.building[e.type]
            if e.siteIndex >= 0 { base = data.rules.territory.bulwarkWeapon }
        case .resource: return nil
        }
        var w = EffWeapon(damage: base.damage * mods.damage, interval: base.interval * mods.interval, range: base.range + mods.range,
                          minRange: base.minRange ?? 0, ground: base.targetsGround, air: base.targetsAir,
                          splash: base.splash ?? 0, speed: base.projectileSpeed ?? 0, bonus: base.bonus, style: base.projectile ?? "bullet")
        // Configurable modes.
        if e.mode != 0 {
            if e.isUnit {
                let p = udef(e).params ?? [:]
                if let alt = p["altDamage"] { // Skyguard ground mode
                    w.damage = alt * mods.damage; w.range = (p["altRange"] ?? w.range) + mods.range; w.ground = true; w.air = false; w.bonus = nil
                } else if let br = p["braceRange"] { // Bastion brace
                    w.range += br
                }
            } else if bdef(e).kind == .tower {
                if e.mode == 1 { w.damage *= 1.5; w.air = false; w.range += 0.5 }
                if e.mode == 2 { w.damage *= 1.6; w.ground = false; w.range += 1 }
            }
        }
        if e.linked {
            if e.isBuilding { w.damage *= 1.25; w.range += 1 }
            else { w.damage *= 1 + data.rules.combat.networkDamageBonus + players[e.owner].mods.linkBonus }
        }
        if e.supplied { w.damage *= 1.1 }
        w.interval *= e.jammedMult
        return w
    }

    public func isCloaked(_ e: Entity) -> Bool {
        if e.isMine { return true }
        guard e.isUnit else { return false }
        let t = traits[e.type]
        if t.cloak { return e.revealedUntil <= time }
        if t.cloakStationary { return !e.moving && e.revealedUntil <= time }
        return false
    }

    @inline(__always) public func tileIndex(_ x: Double, _ y: Double) -> Int {
        let tx = clamp(Int(x), 0, map.size - 1), ty = clamp(Int(y), 0, map.size - 1)
        return ty * map.size + tx
    }

    /// Whether `viewer` can currently see (and therefore target) entity e.
    public func canSee(_ viewer: Int, _ e: Entity) -> Bool {
        if e.owner == viewer { return true }
        let p = players[viewer]
        if e.isBuilding {
            // Any visible tile of the footprint.
            for y in e.tileY..<(e.tileY + e.size) { for x in e.tileX..<(e.tileX + e.size) where map.inBounds(x, y) {
                if p.visible[map.idx(x, y)] > 0 { return true } } }
            return false
        }
        let i = tileIndex(e.x, e.y)
        if p.visible[i] == 0 { return false }
        if isCloaked(e) && !p.detected[i] { return false }
        return true
    }

    @inline(__always) func isEnemy(_ a: Int, _ b: Int) -> Bool { a >= 0 && b >= 0 && a != b }

    func emit(_ ev: GameEvent) { if collectEvents { events.append(ev) } }

    // MARK: Spatial hash

    func rebuildSpatial() {
        let total = cellsW * cellsW
        for i in 0..<total { cellCount[i] = 0 }
        var cnt = 0
        for e in entities where e.onMap && e.kind != .resource {
            cellCount[cellOf(e.x, e.y)] += 1; cnt += 1
        }
        var acc: Int32 = 0
        for i in 0..<total { cellStart[i] = acc; acc += cellCount[i]; cellCount[i] = 0 }
        cellStart[total] = acc
        if cellItems.count < cnt { cellItems = Array(repeating: 0, count: cnt * 2) }
        for e in entities where e.onMap && e.kind != .resource {
            let c = cellOf(e.x, e.y)
            cellItems[Int(cellStart[c] + cellCount[c])] = Int32(e.id)
            cellCount[c] += 1
        }
    }

    @inline(__always) func cellOf(_ x: Double, _ y: Double) -> Int {
        let cx = clamp(Int(x) / cellSize, 0, cellsW - 1), cy = clamp(Int(y) / cellSize, 0, cellsW - 1)
        return cy * cellsW + cx
    }

    /// Calls body for every non-resource entity whose position lies within r (+ margin for big buildings) of (x,y).
    @inline(__always) func forEachNear(_ x: Double, _ y: Double, _ r: Double, _ body: (Entity) -> Void) {
        let rr = r + 2.5
        let x0 = clamp(Int(x - rr) / cellSize, 0, cellsW - 1), x1 = clamp(Int(x + rr) / cellSize, 0, cellsW - 1)
        let y0 = clamp(Int(y - rr) / cellSize, 0, cellsW - 1), y1 = clamp(Int(y + rr) / cellSize, 0, cellsW - 1)
        for cy in y0...y1 {
            for cx in x0...x1 {
                let c = cy * cellsW + cx
                var k = Int(cellStart[c])
                let end = k + Int(cellCount[c])
                while k < end {
                    if let e = byID[Int(cellItems[k])], e.alive { body(e) }
                    k += 1
                }
            }
        }
    }

    /// Edge-to-edge distance between entity e and point/entity.
    @inline(__always) public func edgeDist(_ a: Entity, _ b: Entity) -> Double {
        if b.isBuilding {
            // distance to rectangle
            let s = Double(b.size)
            let nx = clamp(a.x, Double(b.tileX), Double(b.tileX) + s), ny = clamp(a.y, Double(b.tileY), Double(b.tileY) + s)
            return max(0, dist2(a.x, a.y, nx, ny).squareRoot() - a.radius)
        }
        return max(0, dist2(a.x, a.y, b.x, b.y).squareRoot() - a.radius - b.radius)
    }

    // MARK: Tick

    public func step() {
        guard winner == nil else { return }
        nav.tick = tick
        nav.fieldsBuiltThisTick = 0
        for e in entities where e.isUnit { e.px = e.x; e.py = e.y }

        if tick % 5 == 0 { updateFog() }
        if refreshZonesSoon || tick % 20 == 0 { refreshZones(); refreshZonesSoon = false }
        rebuildSpatial()
        if tick % 4 == 0 { updateAuras() }
        updateOrders()
        separate()
        updateCombat()
        updateProjectiles()
        updateClouds()
        updateEconomyTimers()
        updateSupport()
        if tick % 5 == 0 { updateTerritory(dt * 5) }
        cleanup()
        if tick % 20 == 0 { checkVictory() }
        tick += 1
        time += dt
    }

    func cleanup() {
        var anyDead = false
        for e in entities where !e.alive { anyDead = true; break }
        guard anyDead else { return }
        entities.removeAll { !$0.alive && $0.carriedBy < 0 }
    }

    func pushOutOfBlocked(_ e: Entity) {
        if nav.isBlocked(Int(e.x), Int(e.y)) {
            let (ox, oy) = nav.nearestOpen(Int(e.x), Int(e.y))
            e.x = Double(ox) + 0.5; e.y = Double(oy) + 0.5
        }
    }

    // MARK: Queries for UI/AI

    /// Remove every entity (used by sandbox tools).
    public func clearAll() {
        for e in entities where e.alive {
            if e.isBuilding || e.isResource { occupy(e, false) }
            e.alive = false
        }
        entities.removeAll()
        projectiles.removeAll()
        clouds.removeAll()
        for p in players { p.unitCount = 0; p.towerCount = 0; p.completeBuildings = [:]; p.completeBuildingIDs = [] }
    }

    /// Grant all requirements (sandbox tools).
    public func unlockAll(_ player: Int) {
        let p = players[player]
        for b in data.buildingIDs(p.faction) { p.completeBuildingIDs.insert(b) }
        for (i, g) in data.upgrades.enumerated() where g.faction == p.faction && g.tier >= 2 && g.effects.isEmpty { p.completedUpgrades.insert(i) }
    }

    public func units(of owner: Int) -> [Entity] { entities.filter { $0.isUnit && $0.onMap && $0.owner == owner } }
    public func buildings(of owner: Int) -> [Entity] { entities.filter { $0.isBuilding && $0.alive && $0.owner == owner } }

    /// Deterministic digest of the simulation state (used by determinism tests).
    public func stateHash() -> UInt64 {
        var h = StateHasher()
        h.add(tick)
        for e in entities where e.alive {
            h.add(e.id); h.add(e.x); h.add(e.y); h.add(e.hp); h.add(e.owner)
        }
        for p in players { for r in p.res { h.add(r) } }
        for s in sites { h.add(s.owner); h.add(s.control) }
        return h.h
    }
}
