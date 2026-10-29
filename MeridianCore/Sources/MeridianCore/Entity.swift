import Foundation

public enum EntityKind: UInt8, Sendable { case unit, building, resource }

public enum OrderKind: UInt8, Sendable {
    case idle, move, attackMove, attack, gather, returnCargo, build, repair, hold, load, unload, patrol
}

public struct ProdItem: Sendable {
    public var isUpgrade: Bool
    public var index: Int
    public var remaining: Double
    public var total: Double
    public var paid: Cost
}

public final class Entity {
    public let id: Int
    public let kind: EntityKind
    /// Unit def index, building def index, or ResourceKind raw value.
    public let type: Int
    public var owner: Int
    public var x: Double
    public var y: Double
    public var px: Double
    public var py: Double
    public var hp: Double
    public var maxHp: Double
    public var alive = true
    public var radius: Double
    public var isAir = false

    // Orders
    public var order: OrderKind = .idle
    public var ox: Double = 0
    public var oy: Double = 0
    public var orderTarget: Int = -1
    /// Construction: workers building this tick and last tick (for diminishing returns on extra builders).
    var builderStamp: Double = -1
    var buildersNow = 0
    var buildersLast = 1
    /// Follow-up order after the current one completes (patrol / queued move).
    public var px2: Double = 0
    public var py2: Double = 0
    public var formationDX: Double = 0
    public var formationDY: Double = 0
    /// Group cohesion: units issued the same move share a group id and speed cap.
    public var groupID: Int = 0
    public var groupSpeed: Double = 0
    /// Smoothed heading (anti-jitter) and cached line-of-travel test.
    public var hx: Double = 0
    public var hy: Double = 0
    public var losTimer: Int = 0
    public var losClear = false
    public var sidestepUntil: Double = 0
    public var sidestepSign: Double = 1
    /// How many enemies currently target this unit (spreads target selection).
    public var attackerCount: Int = 0

    // Combat
    public var target: Int = -1
    public var cooldown: Double = 0
    public var facing: Double = 0.5
    public var lastDamagedTime: Double = -100
    public var lastAttackTime: Double = -100
    public var retargetTimer: Double = 0
    public var mode: Int = 0
    public var setupTimer: Double = 0
    public var abilityCooldown: Double = 0
    public var mineTimer: Double = 0
    public var disruptedUntil: Double = 0
    public var shredUntil: Double = 0
    public var shredAmount: Double = 0
    public var slowMult: Double = 1
    public var jammedMult: Double = 1
    public var linked = false
    public var supplied = false
    public var inBloom = false
    public var revealedUntil: Double = 0
    public var stuckTimer: Double = 0
    public var lastProgressX: Double = 0
    public var lastProgressY: Double = 0

    // Transport
    public var cargo: [Int] = []
    public var carriedBy: Int = -1

    // Economy
    public var carryKind: ResourceKind = .iron
    public var gatherKind: ResourceKind = .iron
    /// Worker retreating from danger; resumes gathering on arrival.
    public var fleeing = false
    public var carryAmount: Int = 0
    public var gatherNode: Int = -1
    public var gatherTimer: Double = 0
    public var amount: Int = 0          // resource nodes

    // Buildings
    public var tileX: Int = 0
    public var tileY: Int = 0
    public var size: Int = 0
    public var buildProgress: Double = 1
    public var complete = true
    public var queue: [ProdItem] = []
    public var rallyX: Double = 0
    public var rallyY: Double = 0
    public var hasRally = false
    public var siteIndex: Int = -1      // for site bulwark towers
    public var isMine = false

    // Renderer feedback
    public var lastFireTime: Double = -100
    public var lastHitTime: Double = -100
    public var moving = false

    init(id: Int, kind: EntityKind, type: Int, owner: Int, x: Double, y: Double, hp: Double, radius: Double) {
        self.id = id; self.kind = kind; self.type = type; self.owner = owner
        self.x = x; self.y = y; self.px = x; self.py = y
        self.hp = hp; self.maxHp = hp; self.radius = radius
    }

    public var isUnit: Bool { kind == .unit }
    public var isBuilding: Bool { kind == .building }
    public var isResource: Bool { kind == .resource }
    public var inTransport: Bool { carriedBy >= 0 }
    public var onMap: Bool { alive && carriedBy < 0 }
}

public struct Projectile: Sendable {
    public var x: Double, y: Double
    public var tx: Double, ty: Double
    public var sx: Double, sy: Double
    public var target: Int
    public var owner: Int
    public var source: Int
    public var speed: Double
    public var damage: Double
    public var splash: Double
    public var hitsGround: Bool
    public var hitsAir: Bool
    public var targetAir: Bool
    public var style: String
    public var sourceType: Int          // unit def index or -1-buildingDef
    public var age: Double = 0
    public var total: Double = 0
}

public struct Cloud: Sendable {
    public var x: Double, y: Double
    public var radius: Double
    public var dps: Double
    public var slow: Double
    public var remaining: Double
    public var owner: Int
}

public struct Site: Sendable {
    public var x: Double, y: Double
    public var owner: Int = -1
    /// 0...1 control strength of `owner` (or of `capturer` while neutral).
    public var control: Double = 0
    public var capturer: Int = -1
    public var contested = false
    public var installation: Installation = .none
    public var bulwarkID: Int = -1
    public var incomeAcc: [Double] = [0, 0, 0]
}

public enum Installation: Int, Sendable, CaseIterable { case none, extractor, watchpost, bulwark
    public var title: String { ["None", "Extractor", "Watchpost", "Bulwark"][rawValue] }
}

/// Transient visual events for the renderer.
public enum GameEvent: Sendable {
    case shot(from: Int, fx: Double, fy: Double, tx: Double, ty: Double, style: String, owner: Int, air: Bool)
    /// power = raw weapon damage; surface = what was hit ("metal", "flesh", "structure", "ground") for impact styling.
    case impact(x: Double, y: Double, radius: Double, style: String, air: Bool, power: Double, surface: String)
    case death(x: Double, y: Double, big: Bool, owner: Int, air: Bool, building: Bool)
    case heal(x: Double, y: Double)
    case emp(x: Double, y: Double, radius: Double)
    case captured(site: Int, owner: Int)
    case built(id: Int)
    case produced(id: Int)
    case researched(owner: Int, upgrade: Int)
    case message(owner: Int, text: String)
}
