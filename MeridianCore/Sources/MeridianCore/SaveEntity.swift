import Foundation

// Save / resume support. GENERATED field lists for Entity mirror Entity.swift exactly
// (see testSnapshotCoversEveryEntityField, which fails if a field is added without updating this file).

/// Every stored field of an entity.
public struct EntitySnapshot: Codable {
    public var id: Int
    public var kind: EntityKind
    public var type: Int
    public var owner: Int
    public var x: Double
    public var y: Double
    public var px: Double
    public var py: Double
    public var hp: Double
    public var maxHp: Double
    public var alive: Bool
    public var radius: Double
    public var isAir: Bool
    public var order: OrderKind
    public var ox: Double
    public var oy: Double
    public var orderTarget: Int
    public var px2: Double
    public var py2: Double
    public var formationDX: Double
    public var formationDY: Double
    public var groupID: Int
    public var groupSpeed: Double
    public var hx: Double
    public var hy: Double
    public var losTimer: Int
    public var losClear: Bool
    public var sidestepUntil: Double
    public var sidestepSign: Double
    public var attackerCount: Int
    public var target: Int
    public var cooldown: Double
    public var facing: Double
    public var lastDamagedTime: Double
    public var lastAttackTime: Double
    public var retargetTimer: Double
    public var mode: Int
    public var setupTimer: Double
    public var abilityCooldown: Double
    public var mineTimer: Double
    public var disruptedUntil: Double
    public var shredUntil: Double
    public var shredAmount: Double
    public var slowMult: Double
    public var jammedMult: Double
    public var linked: Bool
    public var supplied: Bool
    public var inBloom: Bool
    public var revealedUntil: Double
    public var stuckTimer: Double
    public var lastProgressX: Double
    public var lastProgressY: Double
    public var cargo: [Int]
    public var carriedBy: Int
    public var carryKind: ResourceKind
    public var gatherKind: ResourceKind
    public var fleeing: Bool
    public var carryAmount: Int
    public var gatherNode: Int
    public var gatherTimer: Double
    public var amount: Int
    public var tileX: Int
    public var tileY: Int
    public var size: Int
    public var buildProgress: Double
    public var complete: Bool
    public var queue: [ProdItem]
    public var rallyX: Double
    public var rallyY: Double
    public var hasRally: Bool
    public var siteIndex: Int
    public var isMine: Bool
    public var lastFireTime: Double
    public var lastHitTime: Double
    /// Construction crew bookkeeping (optional so older saves still load).
    public var builderStamp: Double?
    public var buildersNow: Int?
    public var buildersLast: Int?
    public var moving: Bool
    init() { id = 0; kind = .unit; type = 0; owner = 0; x = 0; y = 0; px = 0; py = 0; hp = 0; maxHp = 0; alive = true; radius = 0; isAir = false; order = .idle; ox = 0; oy = 0; orderTarget = -1; px2 = 0; py2 = 0; formationDX = 0; formationDY = 0; groupID = 0; groupSpeed = 0; hx = 0; hy = 0; losTimer = 0; losClear = false; sidestepUntil = 0; sidestepSign = 1; attackerCount = 0; target = -1; cooldown = 0; facing = 0; lastDamagedTime = 0; lastAttackTime = 0; retargetTimer = 0; mode = 0; setupTimer = 0; abilityCooldown = 0; mineTimer = 0; disruptedUntil = 0; shredUntil = 0; shredAmount = 0; slowMult = 1; jammedMult = 1; linked = false; supplied = false; inBloom = false; revealedUntil = 0; stuckTimer = 0; lastProgressX = 0; lastProgressY = 0; cargo = []; carriedBy = -1; carryKind = .iron; gatherKind = .iron; fleeing = false; carryAmount = 0; gatherNode = -1; gatherTimer = 0; amount = 0; tileX = 0; tileY = 0; size = 0; buildProgress = 1; complete = true; queue = []; rallyX = 0; rallyY = 0; hasRally = false; siteIndex = -1; isMine = false; lastFireTime = 0; lastHitTime = 0; moving = false }
}

extension Entity {
    func snapshot() -> EntitySnapshot {
        var s = EntitySnapshot()
        s.id = id
        s.kind = kind
        s.type = type
        s.owner = owner
        s.x = x
        s.y = y
        s.px = px
        s.py = py
        s.hp = hp
        s.maxHp = maxHp
        s.alive = alive
        s.radius = radius
        s.isAir = isAir
        s.order = order
        s.ox = ox
        s.oy = oy
        s.orderTarget = orderTarget
        s.px2 = px2
        s.py2 = py2
        s.formationDX = formationDX
        s.formationDY = formationDY
        s.groupID = groupID
        s.groupSpeed = groupSpeed
        s.hx = hx
        s.hy = hy
        s.losTimer = losTimer
        s.losClear = losClear
        s.sidestepUntil = sidestepUntil
        s.sidestepSign = sidestepSign
        s.attackerCount = attackerCount
        s.target = target
        s.cooldown = cooldown
        s.facing = facing
        s.lastDamagedTime = lastDamagedTime
        s.lastAttackTime = lastAttackTime
        s.retargetTimer = retargetTimer
        s.mode = mode
        s.setupTimer = setupTimer
        s.abilityCooldown = abilityCooldown
        s.mineTimer = mineTimer
        s.disruptedUntil = disruptedUntil
        s.shredUntil = shredUntil
        s.shredAmount = shredAmount
        s.slowMult = slowMult
        s.jammedMult = jammedMult
        s.linked = linked
        s.supplied = supplied
        s.inBloom = inBloom
        s.revealedUntil = revealedUntil
        s.stuckTimer = stuckTimer
        s.lastProgressX = lastProgressX
        s.lastProgressY = lastProgressY
        s.cargo = cargo
        s.carriedBy = carriedBy
        s.carryKind = carryKind
        s.gatherKind = gatherKind
        s.fleeing = fleeing
        s.carryAmount = carryAmount
        s.gatherNode = gatherNode
        s.gatherTimer = gatherTimer
        s.amount = amount
        s.tileX = tileX
        s.tileY = tileY
        s.size = size
        s.buildProgress = buildProgress
        s.complete = complete
        s.queue = queue
        s.rallyX = rallyX
        s.rallyY = rallyY
        s.hasRally = hasRally
        s.siteIndex = siteIndex
        s.isMine = isMine
        s.lastFireTime = lastFireTime
        s.lastHitTime = lastHitTime
        s.builderStamp = builderStamp; s.buildersNow = buildersNow; s.buildersLast = buildersLast
        s.moving = moving
        return s
    }

    static func restore(_ s: EntitySnapshot) -> Entity {
        let e = Entity(id: s.id, kind: s.kind, type: s.type, owner: s.owner, x: s.x, y: s.y, hp: s.hp, radius: s.radius)
        e.owner = s.owner
        e.x = s.x
        e.y = s.y
        e.px = s.px
        e.py = s.py
        e.hp = s.hp
        e.maxHp = s.maxHp
        e.alive = s.alive
        e.radius = s.radius
        e.isAir = s.isAir
        e.order = s.order
        e.ox = s.ox
        e.oy = s.oy
        e.orderTarget = s.orderTarget
        e.px2 = s.px2
        e.py2 = s.py2
        e.formationDX = s.formationDX
        e.formationDY = s.formationDY
        e.groupID = s.groupID
        e.groupSpeed = s.groupSpeed
        e.hx = s.hx
        e.hy = s.hy
        e.losTimer = s.losTimer
        e.losClear = s.losClear
        e.sidestepUntil = s.sidestepUntil
        e.sidestepSign = s.sidestepSign
        e.attackerCount = s.attackerCount
        e.target = s.target
        e.cooldown = s.cooldown
        e.facing = s.facing
        e.lastDamagedTime = s.lastDamagedTime
        e.lastAttackTime = s.lastAttackTime
        e.retargetTimer = s.retargetTimer
        e.mode = s.mode
        e.setupTimer = s.setupTimer
        e.abilityCooldown = s.abilityCooldown
        e.mineTimer = s.mineTimer
        e.disruptedUntil = s.disruptedUntil
        e.shredUntil = s.shredUntil
        e.shredAmount = s.shredAmount
        e.slowMult = s.slowMult
        e.jammedMult = s.jammedMult
        e.linked = s.linked
        e.supplied = s.supplied
        e.inBloom = s.inBloom
        e.revealedUntil = s.revealedUntil
        e.stuckTimer = s.stuckTimer
        e.lastProgressX = s.lastProgressX
        e.lastProgressY = s.lastProgressY
        e.cargo = s.cargo
        e.carriedBy = s.carriedBy
        e.carryKind = s.carryKind
        e.gatherKind = s.gatherKind
        e.fleeing = s.fleeing
        e.carryAmount = s.carryAmount
        e.gatherNode = s.gatherNode
        e.gatherTimer = s.gatherTimer
        e.amount = s.amount
        e.tileX = s.tileX
        e.tileY = s.tileY
        e.size = s.size
        e.buildProgress = s.buildProgress
        e.complete = s.complete
        e.queue = s.queue
        e.rallyX = s.rallyX
        e.rallyY = s.rallyY
        e.hasRally = s.hasRally
        e.siteIndex = s.siteIndex
        e.isMine = s.isMine
        e.lastFireTime = s.lastFireTime
        e.lastHitTime = s.lastHitTime
        e.builderStamp = s.builderStamp ?? -1; e.buildersNow = s.buildersNow ?? 0; e.buildersLast = s.buildersLast ?? 1
        e.moving = s.moving
        return e
    }
}
