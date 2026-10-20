import Foundation
import SwiftUI
import MeridianCore

/// Isometric projection shared by the renderer and input. World tiles are 64x32 points.
enum Iso {
    static let hw: CGFloat = 32, hh: CGFloat = 16
    @inline(__always) static func scene(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: hw * CGFloat(x + y), y: hh * CGFloat(y - x))
    }
    @inline(__always) static func world(_ p: CGPoint) -> (Double, Double) {
        let a = Double(p.x / hw), b = Double(p.y / hh)
        return ((a - b) / 2, (a + b) / 2)
    }
    /// Depth: larger = closer to the viewer.
    @inline(__always) static func depth(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x - y) }
}

struct GameSettings {
    var playerFaction: Faction = .humans
    var aiFaction: Faction = .machines
    var difficulty: Difficulty = .normal
    var strategy: AIStrategy = .balanced
    var layout: MapLayout = .crossroads
    var seed: UInt64 = UInt64(Date().timeIntervalSince1970) % 100_000
}

enum InputMode: Equatable {
    case normal, attackMove, patrol, place(Int), unload, emp, rally
}

struct CommandButton: Identifiable {
    let id: String
    var title: String
    var symbol: String
    var cost: Cost? = nil
    var enabled = true
    var reason: String? = nil
    var highlighted = false
    var badge: String? = nil
    var hotkey: Character? = nil
    var action: () -> Void
}

struct QueueEntry: Identifiable {
    let id: Int
    var title: String
    var progress: Double
    var isUpgrade: Bool
}

struct Toast: Identifiable {
    let id = UUID()
    var text: String
    var time: Date
    var warning: Bool
}

/// Snapshot published to SwiftUI a few times per second (cheap to diff, never touches the sim directly).
struct HUDState {
    var res = [0, 0, 0]
    var income = [0.0, 0.0, 0.0]
    var units = 0
    var cap = 200
    var time = 0.0
    var sitesOwned = 0
    var sitesEnemy = 0
    var sitesTotal = 7
    var dominanceNeed = 5
    var myDominance = 0.0
    var enemyDominance = 0.0
    var dominanceSeconds = 180.0
    var dominanceActive = false
    var selectionTitle = ""
    var selectionSubtitle = ""
    var selectionDetail = ""
    var selectionHP: (Double, Double)? = nil
    var selectionCount = 0
    var selectionIcons: [(type: Int, count: Int, building: Bool)] = []
    var queue: [QueueEntry] = []
    var buttons: [CommandButton] = []
    var menuTitle: String? = nil
    var placing: String? = nil
    var placementValid = false
    var placementReason: String? = nil
}

@MainActor
final class GameController: ObservableObject {
    let settings: GameSettings
    let match: Match
    var world: World { match.world }
    let me = 0
    let data = GameData.shared

    @Published var hud = HUDState()
    @Published var toasts: [Toast] = []
    @Published var paused = false
    @Published var speed: Double = 1.0
    @Published var gameOver: (won: Bool, reason: String)? = nil
    @Published var showTech = false
    @Published var minimapVersion = 0

    var spectating = false
    var selection: [Int] = []
    var selectedSite: Int? = nil
    var mode: InputMode = .normal { didSet { refreshHUD() } }
    var buildMenu = false { didSet { refreshHUD() } }
    var ghostTile: (Int, Int)? = nil
    var controlGroups: [Int: [Int]] = [:]
    var accumulator = 0.0
    var lastHUD = 0.0
    var lastAttackAlert = -100.0
    var lastRes = [0, 0, 0]
    var incomeWindow: [(Double, [Int])] = []
    /// Camera hooks provided by the scene.
    var focusCamera: ((Double, Double) -> Void)?
    var cameraWorldRect: (() -> [(Double, Double)])?
    var attackPings: [(x: Double, y: Double, t: Double)] = []

    init(settings: GameSettings, spectate: Bool = false) {
        self.settings = settings
        let cfg = MatchConfig(factions: [settings.playerFaction, settings.aiFaction], layout: settings.layout, seed: settings.seed)
        var ai: [(player: Int, difficulty: Difficulty, strategy: AIStrategy)] = [(1, settings.difficulty, settings.strategy)]
        if spectate { ai.insert((0, settings.difficulty, .balanced), at: 0) }
        spectating = spectate
        match = Match(config: cfg, ai: ai)
        refreshHUD()
    }

    /// Renderer stress scenario: N units per side fighting mid-map with towers (development).
    func setupStress(_ perSide: Int) {
        world.sandbox = true
        world.unlockAll(0); world.unlockAll(1)
        var r = RNG(seed: 7)
        let mid = Double(world.map.size) / 2
        for p in 0..<2 {
            let pool = data.unitIDs(world.players[p].faction).filter { data.units[$0].role != "worker" && data.units[$0].role != "transport" }
            for _ in 0..<perSide {
                var x = mid + (p == 0 ? -12 : 12) + r.range(-8, 8), y = mid + r.range(-8, 8)
                if world.nav.isBlocked(Int(x), Int(y)) { let o = world.nav.nearestOpen(Int(x), Int(y)); x = Double(o.0) + 0.5; y = Double(o.1) + 0.5 }
                world.spawnUnit(pool[r.int(pool.count)], owner: p, x: x, y: y)
            }
        }
        for p in 0..<2 {
            world.commandMove(world.units(of: p).filter { !world.traits[$0.type].worker }.map { $0.id }, x: mid + (p == 0 ? 20 : -20), y: mid, attack: true)
        }
        stressMode = true
    }
    var stressMode = false

    /// Fast-forward the simulation (development / demo).
    func warp(seconds: Double) {
        world.collectEvents = false
        while world.time < seconds && world.winner == nil { match.step() }
        world.collectEvents = true
        world.events.removeAll()
    }

    // MARK: Simulation clock

    func advance(_ realDt: Double) {
        guard !paused, gameOver == nil else { return }
        accumulator += min(realDt, 0.25) * speed
        var steps = 0
        while accumulator >= world.dt && steps < 8 {
            match.step()
            accumulator -= world.dt
            steps += 1
        }
        processEvents()
        if world.time - lastHUD > 0.2 { lastHUD = world.time; refreshHUD() }
        if let w = world.winner, gameOver == nil {
            gameOver = (w == me, world.victoryReason)
        }
    }

    var interpolation: Double { accumulator / world.dt }

    /// Events the renderer does not consume (toasts, alerts) are handled here; the scene reads the rest first.
    func processEvents() {
        for ev in world.events {
            switch ev {
            case .captured(let site, let owner):
                if owner == me { toast("Site captured") } else { toast("Enemy captured a site", warning: true) }
                _ = site
            case .researched(let owner, let u):
                if owner == me { toast("Research complete: \(data.upgrades[u].name)") }
            case .message(let owner, let text):
                if owner == me { toast(text, warning: true) }
            default: break
            }
        }
        // Under-attack alerts.
        for e in world.entities where e.alive && e.owner == me && world.time - e.lastDamagedTime < 0.06 && !e.isMine {
            if world.time - lastAttackAlert > 12 {
                lastAttackAlert = world.time
                toast(e.isBuilding ? "Your base is under attack" : "Your forces are under attack", warning: true)
                attackPings.append((e.x, e.y, world.time))
            }
            break
        }
        attackPings.removeAll { world.time - $0.t > 6 }
    }

    func toast(_ s: String, warning: Bool = false) {
        toasts.append(Toast(text: s, time: Date(), warning: warning))
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
    }

    func pruneToasts() {
        let now = Date()
        let kept = toasts.filter { now.timeIntervalSince($0.time) < 4 }
        if kept.count != toasts.count { toasts = kept }
    }

    // MARK: Selection

    var selectedEntities: [Entity] { selection.compactMap { world.entity($0) } }

    func select(_ ids: [Int]) {
        selection = ids.filter { world.entity($0) != nil }
        selectedSite = nil
        buildMenu = false
        if case .place = mode { mode = .normal }
        mode = .normal
        refreshHUD()
    }

    func selectSite(_ i: Int) {
        selection = []; selectedSite = i; buildMenu = false; mode = .normal; refreshHUD()
    }

    func clearSelection() { select([]) }

    /// Pick the best entity at a world point (units over buildings over resources), honoring fog.
    func pick(_ x: Double, _ y: Double, radius: Double) -> Entity? {
        var best: Entity? = nil
        var bd = Double.infinity
        for e in world.entities where e.alive && e.onMap && !e.isMine {
            if e.owner != me && e.owner >= 0 && !isShown(e) { continue }
            var d: Double
            if e.isBuilding {
                let s = Double(e.size)
                if x >= Double(e.tileX) - 0.3 && x <= Double(e.tileX) + s + 0.3 && y >= Double(e.tileY) - 0.3 && y <= Double(e.tileY) + s + 0.3 { d = 0.5 } else { continue }
            } else if e.isResource {
                d = dist2(x, y, e.x, e.y).squareRoot() + 0.4
                if !world.players[me].explored[world.tileIndex(e.x, e.y)] { continue }
            } else {
                // Air units are drawn higher up the screen; compensate.
                let ox = e.isAir ? e.x - 0.75 : e.x, oy = e.isAir ? e.y + 0.75 : e.y
                d = dist2(x, y, ox, oy).squareRoot() - e.radius * 0.5
            }
            if d < radius && d < bd { bd = d; best = e }
        }
        return best
    }

    func pickSite(_ x: Double, _ y: Double) -> Int? {
        for (i, s) in world.sites.enumerated() where dist2(s.x, s.y, x, y) < 2.2 * 2.2 { return i }
        return nil
    }

    /// Fog check used for drawing and picking enemy objects.
    var seenBuildings = Set<Int>()
    func isShown(_ e: Entity) -> Bool {
        if e.owner == me || e.owner < 0 || spectating { return true }
        if world.canSee(me, e) {
            if e.isBuilding { seenBuildings.insert(e.id) }
            return true
        }
        return e.isBuilding && seenBuildings.contains(e.id)
    }

    func selectBox(_ a: (Double, Double), _ b: (Double, Double), screenRect: Bool = true, corners: [(Double, Double)]? = nil) {
        // corners: world-space quad of the screen-space rectangle.
        guard let c = corners else { return }
        func inside(_ x: Double, _ y: Double) -> Bool {
            var sign = 0.0
            for i in 0..<4 {
                let (x1, y1) = c[i], (x2, y2) = c[(i + 1) % 4]
                let cr = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
                if cr != 0 { if sign == 0 { sign = cr } else if (cr > 0) != (sign > 0) { return false } }
            }
            return true
        }
        var units = world.entities.filter { $0.isUnit && $0.onMap && !$0.isMine && $0.owner == me && inside($0.x, $0.y) }
        // Prefer army over workers when both are boxed.
        if units.contains(where: { !world.traits[$0.type].worker }) { units.removeAll { world.traits[$0.type].worker } }
        if !units.isEmpty { select(units.map { $0.id }) }
    }

    func selectSameType(as e: Entity, visibleOnly corners: [(Double, Double)]?) {
        guard e.owner == me else { return }
        let all = world.entities.filter { $0.alive && $0.onMap && !$0.isMine && $0.owner == me && $0.kind == e.kind && $0.type == e.type }
        select(all.map { $0.id })
    }

    func selectArmy() {
        select(world.units(of: me).filter { !world.traits[$0.type].worker && !$0.isMine }.map { $0.id })
    }

    func selectIdleWorker() {
        let idle = world.units(of: me).filter { world.traits[$0.type].worker && $0.order == .idle }
        if let w = idle.first { select([w.id]); focusCamera?(w.x, w.y) } else { toast("No idle workers") }
    }

    func groupAssign(_ n: Int) { controlGroups[n] = selection; toast("Group \(n) assigned") }
    func groupRecall(_ n: Int) {
        guard let g = controlGroups[n] else { return }
        let alive = g.filter { world.entity($0) != nil }
        if selection == alive, let f = alive.compactMap({ world.entity($0) }).first { focusCamera?(f.x, f.y) }
        select(alive)
    }

    // MARK: Map interaction

    /// Tap / left click on the map.
    func tap(worldX x: Double, y: Double, zoom: Double) {
        let r = 0.7 * max(1, zoom * 0.8)
        switch mode {
        case .place(let type):
            let s = data.buildings[type].size
            ghostTile = (Int(x - Double(s) / 2 + 0.5), Int(y - Double(s) / 2 + 0.5))
            refreshHUD()
            return
        case .attackMove, .patrol:
            let ids = myUnitSelection()
            if let t = pick(x, y, radius: r), world.isEnemyPublic(me, t.owner) { world.commandAttack(ids, target: t.id) }
            else { world.commandMove(ids, x: x, y: y, attack: true, patrol: mode == .patrol) }
            mode = .normal
            return
        case .unload:
            for e in selectedEntities where world.traits[e.type].capacity > 0 { world.commandUnload(e.id, x: x, y: y) }
            mode = .normal; return
        case .emp:
            world.commandEMP(selection, x: x, y: y); mode = .normal; return
        case .rally:
            for e in selectedEntities where e.isBuilding { world.setRally(e.id, x: x, y: y) }
            mode = .normal; toast("Rally point set"); return
        case .normal: break
        }
        let hit = pick(x, y, radius: r)
        if let h = hit, h.owner == me {
            // Tapping own stuff: select it (transport + selected units => load handled via smart command).
            if !selection.isEmpty && !h.isBuilding && world.traits[h.type].capacity > 0 && selectedEntities.contains(where: { $0.isUnit && !$0.isAir && $0.id != h.id }) {
                command(at: x, y: y, target: h); return
            }
            if !selection.isEmpty && selectedEntities.allSatisfy({ $0.isUnit && world.traits[$0.type].worker }) && h.isBuilding && (!h.complete || h.hp < h.maxHp) {
                command(at: x, y: y, target: h); return
            }
            select([h.id]); return
        }
        if selection.isEmpty || !selectedEntities.contains(where: { $0.owner == me }) {
            if let h = hit { select([h.id]); return }
            if let s = pickSite(x, y) { selectSite(s); return }
            clearSelection(); return
        }
        command(at: x, y: y, target: hit)
    }

    /// Right click / tap with a selection: contextual order.
    func command(at x: Double, y: Double, target: Entity?) {
        guard !selection.isEmpty else { return }
        if selectedEntities.allSatisfy({ $0.isBuilding }) {
            for e in selectedEntities { world.setRally(e.id, x: x, y: y) }
            toast("Rally point set"); return
        }
        world.commandSmart(selection, x: x, y: y, targetID: target?.id, player: me)
        commandPing = (x, y, target.map { world.isEnemyPublic(me, $0.owner) } ?? false, world.time)
    }
    var commandPing: (Double, Double, Bool, Double)? = nil

    func myUnitSelection() -> [Int] { selectedEntities.filter { $0.isUnit && $0.owner == me }.map { $0.id } }

    // Building placement.
    func moveGhost(worldX x: Double, y: Double) {
        guard case .place(let type) = mode else { return }
        let s = data.buildings[type].size
        ghostTile = (Int(x - Double(s) / 2 + 0.5), Int(y - Double(s) / 2 + 0.5))
        refreshHUD()
    }

    func confirmPlacement() {
        guard case .place(let type) = mode, let g = ghostTile else { return }
        let workers = selectedEntities.filter { $0.isUnit && world.traits[$0.type].worker }
        // Use the closest selected worker (others keep working).
        let w = workers.min { dist2($0.x, $0.y, Double(g.0), Double(g.1)) < dist2($1.x, $1.y, Double(g.0), Double(g.1)) }
        if let err = world.commandBuild(w.map { [$0.id] } ?? [], type: type, tileX: g.0, tileY: g.1) {
            toast(err, warning: true)
        } else {
            mode = .normal
            ghostTile = nil
            buildMenu = false
        }
    }

    func cancelMode() { mode = .normal; ghostTile = nil; buildMenu = false }

    // MARK: HUD

    func refreshHUD() {
        var h = HUDState()
        let p = world.players[me]
        h.res = p.res
        h.units = p.unitCount
        h.cap = data.rules.combat.unitCap
        h.time = world.time
        h.sitesTotal = world.sites.count
        h.sitesOwned = world.sites.filter { $0.owner == me && $0.control >= 1 }.count
        h.sitesEnemy = world.sites.filter { $0.owner >= 0 && $0.owner != me && $0.control >= 1 }.count
        h.dominanceNeed = world.dominanceRequirement
        h.myDominance = p.dominanceTimer
        h.enemyDominance = world.players.filter { $0.index != me }.map { $0.dominanceTimer }.max() ?? 0
        h.dominanceSeconds = data.rules.territory.dominanceSeconds
        h.dominanceActive = world.time >= data.rules.territory.dominanceStart
        // Income per minute from a sliding window.
        incomeWindow.append((world.time, p.stats.gathered.enumerated().map { $0.element + Int(p.stats.territoryIncome[$0.offset]) }))
        incomeWindow.removeAll { world.time - $0.0 > 60 }
        if let first = incomeWindow.first, let last = incomeWindow.last, last.0 - first.0 > 5 {
            let span = last.0 - first.0
            h.income = (0..<3).map { Double(last.1[$0] - first.1[$0]) / span * 60 }
        }
        describeSelection(&h)
        h.buttons = buildButtons(&h)
        if case .place(let t) = mode {
            h.placing = data.buildings[t].name
            if let g = ghostTile {
                h.placementReason = world.placementError(me, t, tileX: g.0, tileY: g.1)
                if h.placementReason == nil && !p.canAfford(world.buildingCost(me, t)) { h.placementReason = "Not enough resources" }
                h.placementValid = h.placementReason == nil
            } else { h.placementReason = "Tap the map to position" }
        }
        hud = h
        pruneToasts()
    }

    func describeSelection(_ h: inout HUDState) {
        if let si = selectedSite {
            let s = world.sites[si]
            h.selectionTitle = "Strategic Site"
            let owner = s.owner < 0 ? "Neutral" : (s.owner == me ? "Yours" : "Enemy")
            h.selectionSubtitle = "\(owner) · control \(Int(s.control * 100))%" + (s.contested ? " · CONTESTED" : "")
            let tr = data.rules.territory
            let f = world.players[me].faction
            let perk: String
            switch f {
            case .humans: perk = "Forward logistics: drop-off point, repairs units within \(Int(tr.humanStagingRadius)) tiles"
            case .machines: perk = "Network node: links machines within \(Int(tr.machineNodeRadius)) tiles"
            case .aliens: perk = "Bloom: regeneration and +\(Int(tr.alienSpeedBonus * 100))% speed within \(Int(tr.alienBloomRadius)) tiles"
            }
            h.selectionDetail = "Income +\(fmt(tr.income[0] * 60))/\(fmt(tr.income[1] * 60))/\(fmt(tr.income[2] * 60)) iron/gold/wood per min. Vision \(Int(tr.vision)). \(perk). Installation: \(s.installation.title)."
            return
        }
        let ents = selectedEntities
        h.selectionCount = ents.count
        guard let first = ents.first else { return }
        if ents.count == 1 {
            let e = first
            h.selectionHP = (e.hp, e.maxHp)
            if e.isUnit {
                let d = world.udef(e)
                h.selectionTitle = d.name
                var sub = "\(world.players[e.owner].faction == .humans ? "Concord" : world.players[e.owner].faction == .machines ? "Lattice" : "Brood") · \(d.role.capitalized)"
                if let m = world.modeName(e) { sub += " · \(m)" }
                if e.linked { sub += " · LINKED" }
                if e.inBloom { sub += " · IN BLOOM" }
                if e.supplied { sub += " · SUPPLIED" }
                if !e.cargo.isEmpty { sub += " · cargo \(e.cargo.count)" }
                h.selectionSubtitle = sub
                var det = "Armor \(fmt(world.armor(e)))  Speed \(fmt(world.speed(e)))"
                if let w = world.weapon(e) {
                    det += "  Dmg \(fmt(w.damage)) / \(fmt(w.interval))s  Range \(fmt(w.range))"
                    det += w.ground && w.air ? "  [G+A]" : (w.air ? "  [Air]" : "  [Ground]")
                }
                det += "\n" + d.description + "\nStrong vs: \(d.strongVs)  Weak vs: \(d.weakVs)"
                if e.carryAmount > 0 { det = "Carrying \(e.carryAmount) \(e.carryKind.name)\n" + det }
                h.selectionDetail = det
            } else if e.isBuilding {
                let d = world.bdef(e)
                h.selectionTitle = d.name
                h.selectionSubtitle = e.complete ? (world.modeName(e).map { "Mode: \($0)" } ?? d.kind.rawValue.capitalized) : "Under construction \(Int(e.buildProgress * 100))%"
                var det = d.description
                if let w = world.weapon(e) { det = "Dmg \(fmt(w.damage))  Range \(fmt(w.range))" + (e.linked ? " (network linked)" : "") + "\n" + det }
                h.selectionDetail = det
                h.queue = e.queue.enumerated().map { i, q in
                    QueueEntry(id: i, title: q.isUpgrade ? data.upgrades[q.index].name : data.units[q.index].name,
                               progress: i == 0 ? 1 - q.remaining / q.total : 0, isUpgrade: q.isUpgrade)
                }
            } else {
                let k = ResourceKind(rawValue: e.type)!
                h.selectionTitle = k == .wood ? "Timber Grove" : (k == .iron ? "Iron Deposit" : "Gold Vein")
                h.selectionSubtitle = "\(e.amount) \(k.name) remaining"
                h.selectionHP = nil
            }
        } else {
            var counts: [Int: Int] = [:]
            for e in ents where e.isUnit { counts[e.type, default: 0] += 1 }
            h.selectionTitle = "\(ents.count) selected"
            h.selectionIcons = counts.sorted { $0.value > $1.value }.map { (type: $0.key, count: $0.value, building: false) }
            let hp = ents.reduce(0) { $0 + $1.hp }, mx = ents.reduce(0) { $0 + $1.maxHp }
            h.selectionHP = (hp, mx)
            h.selectionSubtitle = counts.sorted { $0.value > $1.value }.prefix(4).map { "\($0.value)× \(data.units[$0.key].name)" }.joined(separator: ", ")
        }
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    func buildButtons(_ h: inout HUDState) -> [CommandButton] {
        let p = world.players[me]
        var b: [CommandButton] = []
        if case .place = mode {
            h.menuTitle = "Place building"
            b.append(CommandButton(id: "confirm", title: "Confirm", symbol: "checkmark.circle.fill", enabled: h.placementValid || ghostTile != nil, hotkey: "\r") { [weak self] in self?.confirmPlacement() })
            b.append(CommandButton(id: "cancel", title: "Cancel", symbol: "xmark.circle", hotkey: "\u{1b}") { [weak self] in self?.cancelMode() })
            return b
        }
        if mode != .normal {
            h.menuTitle = { switch mode { case .attackMove: return "Attack-move: tap target"; case .patrol: return "Patrol: tap point"; case .unload: return "Unload: tap point"; case .emp: return "EMP: tap target"; case .rally: return "Rally: tap point"; default: return "" } }()
            b.append(CommandButton(id: "cancel", title: "Cancel", symbol: "xmark.circle", hotkey: "\u{1b}") { [weak self] in self?.cancelMode() })
            return b
        }
        if let si = selectedSite {
            let s = world.sites[si]
            if s.owner == me && s.control >= 1 && s.installation == .none {
                h.menuTitle = "Configure installation"
                let c = data.rules.territory.installCost
                let items: [(Installation, String, String)] = [(.extractor, "Extractor", "shippingbox.fill"), (.watchpost, "Watchpost", "eye.fill"), (.bulwark, "Bulwark", "shield.lefthalf.filled")]
                for (inst, title, sym) in items {
                    b.append(CommandButton(id: "inst\(inst.rawValue)", title: title, symbol: sym, cost: c, enabled: p.canAfford(c), reason: p.canAfford(c) ? nil : "Not enough resources") { [weak self] in
                        guard let self = self else { return }
                        if let err = self.world.configureSite(si, player: self.me, installation: inst) { self.toast(err, warning: true) }
                        self.refreshHUD()
                    })
                }
            }
            return b
        }
        let ents = selectedEntities.filter { $0.owner == me }
        guard !ents.isEmpty else { return b }

        // Single own building: production + research.
        if ents.count == 1, let e = ents.first, e.isBuilding {
            let d = world.bdef(e)
            if !e.complete {
                b.append(CommandButton(id: "cancelBuild", title: "Cancel", symbol: "xmark.octagon", hotkey: "\u{1b}") { [weak self] in
                    self?.world.commandCancelConstruction(e.id); self?.clearSelection() })
                return b
            }
            for u in data.unitIDs(p.faction) where data.units[u].producedAt == d.kind {
                let ud = data.units[u]
                let reason = world.unitAvailability(me, u) ?? (p.canAfford(ud.cost) ? nil : "Not enough resources")
                b.append(CommandButton(id: "u\(u)", title: ud.name, symbol: "unit:\(u)", cost: ud.cost, enabled: reason == nil, reason: reason,
                                       badge: ud.batch.map { "×\($0)" }) { [weak self] in
                    guard let self = self else { return }
                    if let err = self.world.commandTrain(e.id, unitType: u) { self.toast(err, warning: true) }
                    self.refreshHUD()
                })
            }
            for g in data.upgradeIDs(p.faction) where data.upgrades[g].researchedAt == d.kind {
                let gd = data.upgrades[g]
                if p.completedUpgrades.contains(g) { continue }
                let reason = world.upgradeAvailability(me, g) ?? (p.canAfford(gd.cost) ? nil : "Not enough resources")
                b.append(CommandButton(id: "g\(g)", title: gd.name, symbol: "upgrade:\(gd.tier)", cost: gd.cost, enabled: reason == nil, reason: reason,
                                       highlighted: p.researching.contains(g)) { [weak self] in
                    guard let self = self else { return }
                    if let err = self.world.commandResearch(e.id, upgrade: g) { self.toast(err, warning: true) }
                    self.refreshHUD()
                })
            }
            if world.modeName(e) != nil {
                b.append(CommandButton(id: "mode", title: "Mode: \(world.modeName(e)!)", symbol: "dial.medium", hotkey: "m") { [weak self] in
                    self?.world.commandToggleMode([e.id]); self?.refreshHUD() })
            }
            if [.infantry, .heavy, .air, .hq].contains(d.kind) {
                b.append(CommandButton(id: "rally", title: "Rally", symbol: "flag.fill", hotkey: "r") { [weak self] in self?.mode = .rally })
            }
            return b
        }

        let units = ents.filter { $0.isUnit }
        let workers = units.filter { world.traits[$0.type].worker }
        if buildMenu && !workers.isEmpty {
            h.menuTitle = "Construct"
            for t in data.buildingIDs(p.faction) {
                let bd = data.buildings[t]
                let cost = world.buildingCost(me, t)
                let miss = p.missing(bd.requires, data)
                let reason = !miss.isEmpty ? "Requires " + miss.joined(separator: ", ") : (p.canAfford(cost) ? nil : "Not enough resources")
                b.append(CommandButton(id: "b\(t)", title: bd.name, symbol: "building:\(t)", cost: cost, enabled: reason == nil, reason: reason) { [weak self] in
                    guard let self = self else { return }
                    self.mode = .place(t)
                    // Start the ghost in front of the camera centre.
                    if let c = self.cameraWorldRect?() {
                        let cx = c.reduce(0) { $0 + $1.0 } / 4, cy = c.reduce(0) { $0 + $1.1 } / 4
                        self.moveGhost(worldX: cx, y: cy)
                    }
                })
            }
            b.append(CommandButton(id: "back", title: "Back", symbol: "chevron.left", hotkey: "\u{1b}") { [weak self] in self?.buildMenu = false })
            return b
        }
        guard !units.isEmpty else { return b }
        b.append(CommandButton(id: "amove", title: "Attack-Move", symbol: "scope", hotkey: "a") { [weak self] in self?.mode = .attackMove })
        b.append(CommandButton(id: "stop", title: "Stop", symbol: "stop.fill", hotkey: "s") { [weak self] in
            guard let self = self else { return }; self.world.commandStop(self.selection) })
        b.append(CommandButton(id: "hold", title: "Hold", symbol: "hand.raised.fill", hotkey: "h") { [weak self] in
            guard let self = self else { return }; self.world.commandHold(self.selection) })
        b.append(CommandButton(id: "patrol", title: "Patrol", symbol: "arrow.triangle.2.circlepath", hotkey: "p") { [weak self] in self?.mode = .patrol })
        if !workers.isEmpty {
            b.append(CommandButton(id: "build", title: "Build", symbol: "hammer.fill", hotkey: "b") { [weak self] in self?.buildMenu = true })
        }
        if units.contains(where: { world.traits[$0.type].modes > 0 }) {
            let names = Set(units.compactMap { world.modeName($0) })
            b.append(CommandButton(id: "mode", title: names.count == 1 ? names.first! : "Toggle Mode", symbol: "dial.medium", hotkey: "m") { [weak self] in
                guard let self = self else { return }; self.world.commandToggleMode(self.selection); self.refreshHUD() })
        }
        if units.contains(where: { world.traits[$0.type].emp }) {
            let ready = units.contains { world.traits[$0.type].emp && $0.abilityCooldown <= 0 }
            b.append(CommandButton(id: "emp", title: "EMP", symbol: "bolt.circle.fill", enabled: ready, reason: ready ? nil : "Recharging", hotkey: "e") { [weak self] in self?.mode = .emp })
        }
        if units.contains(where: { world.traits[$0.type].capacity > 0 && !$0.cargo.isEmpty }) {
            b.append(CommandButton(id: "unload", title: "Unload", symbol: "arrow.down.to.line", hotkey: "u") { [weak self] in self?.mode = .unload })
        }
        return b
    }

    // MARK: Minimap data

    func minimapDots() -> [(x: Double, y: Double, owner: Int, building: Bool)] {
        var out: [(Double, Double, Int, Bool)] = []
        for e in world.entities where e.alive && e.onMap && !e.isMine && e.kind != .resource {
            if e.owner != me && !isShown(e) { continue }
            out.append((e.x, e.y, e.owner, e.isBuilding))
        }
        return out.map { (x: $0.0, y: $0.1, owner: $0.2, building: $0.3) }
    }
}

extension World {
    func isEnemyPublic(_ a: Int, _ b: Int) -> Bool { a >= 0 && b >= 0 && a != b }
}
