import Foundation
import SwiftUI
import MeridianCore

/// Boot Camp: an interactive first match against an opponent who never attacks. Each step says what to do,
/// points at it (a bouncing marker in the world and a glowing button in the HUD) and waits until it is done.
struct TutorialStep {
    var title: String
    var text: String
    /// Command-card button to glow (id without the "cmd_" prefix), worked out from the current state.
    var button: (GameController) -> String? = { _ in nil }
    /// Side-rail button to glow ("army", "idle").
    var rail: String? = nil
    /// World point for the marker.
    var target: (GameController) -> (Double, Double)? = { _ in nil }
    /// Information step: the player taps "Next".
    var info = false
    var enter: (GameController) -> Void = { _ in }
    var done: (GameController) -> Bool = { _ in false }
}

final class TutorialState {
    var step = 0
    var camStart: (Double, Double)? = nil
    var spawned: [Int] = []
    var outpost = -1
    var focusUnit = -1
    var finished = false
}

extension GameController {

    var tutorialStep: TutorialStep? {
        guard let t = tutorial, t.step < tutorialSteps.count else { return nil }
        return tutorialSteps[t.step]
    }

    /// Called from the HUD refresh: completes the current step when its goal is met.
    func tutorialTick() {
        guard let t = tutorial, let s = tutorialStep, !s.info else { return }
        if s.done(self) { advanceTutorial() }
        _ = t
    }

    func advanceTutorial() {
        guard let t = tutorial else { return }
        t.step += 1
        SoundEngine.shared?.play(t.step >= tutorialSteps.count ? "victory" : "confirm", at: nil, minGap: 0)
        Haptics.tap()
        if t.step < tutorialSteps.count {
            let s = tutorialSteps[t.step]
            s.enter(self)
            // Bring what the step is about into view (a little later, once anything it spawned exists).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, let p = s.target(self) else { return }
                self.focusCamera?(p.0 + 1, p.1 - 1)
            }
        } else { t.finished = true }
        objectWillChange.send()
        refreshHUD()
    }

    // MARK: Helpers

    var hq: Entity? { world.buildings(of: me).first { world.bdef($0).kind == .hq } }
    var workerType: Int { data.unitIDs(world.players[me].faction).first { data.units[$0].role == "worker" }! }
    var barracksType: Int { data.buildingIDs(world.players[me].faction).first { data.buildings[$0].kind == .infantry }! }
    var soldierType: Int { data.unitIDs(world.players[me].faction).first { data.units[$0].role == "infantry" }! }
    var barracks: Entity? { world.buildings(of: me).first { $0.type == barracksType } }
    private var soldiers: [Entity] { world.units(of: me).filter { !world.traits[$0.type].worker && !$0.isMine } }

    private func spawnEnemies(_ type: String, count: Int, near p: (Double, Double)) -> [Int] {
        guard let u = data.unitIndex[type] else { return [] }
        return (0..<count).map { k in
            var (x, y) = (p.0 + Double(k % 2) * 1.2, p.1 + Double(k / 2) * 1.2)
            if world.nav.isBlocked(Int(x), Int(y)) { let o = world.nav.nearestOpen(Int(x), Int(y)); x = Double(o.0) + 0.5; y = Double(o.1) + 0.5 }
            let e = world.spawnUnit(u, owner: 1 - me, x: x, y: y)
            world.commandHold([e.id])
            return e.id
        }
    }

    /// A point some tiles from the HQ toward the map centre.
    private func ahead(_ d: Double) -> (Double, Double) {
        guard let h = hq else { return (Double(world.map.size) / 2, Double(world.map.size) / 2) }
        let m = Double(world.map.size) / 2
        let dx = m - h.x, dy = m - h.y, l = max(1, (dx * dx + dy * dy).squareRoot())
        return (h.x + dx / l * d, h.y + dy / l * d)
    }

    // MARK: Steps

    var tutorialSteps: [TutorialStep] {
        let wName = data.units[workerType].name, bName = data.buildings[barracksType].name, sName = data.units[soldierType].name
        return [
            TutorialStep(title: "Welcome, Commander", text: "This is your \(data.buildings[hq?.type ?? 0].name), the heart of your base. In a few minutes you'll learn everything you need to win a battle.",
                         target: { $0.hq.map { ($0.x, $0.y) } }, info: true),
            TutorialStep(title: "Look around", text: "Drag one finger across the screen to move the camera. Pinch with two fingers to zoom.",
                         enter: { c in c.tutorial?.camStart = c.cameraState.map { s in (s().0, s().1) } },
                         done: { c in
                             guard let s = c.cameraState?() else { return false }
                             guard let a = c.tutorial?.camStart else { c.tutorial?.camStart = (s.0, s.1); return false }
                             return dist2(a.0, a.1, s.0, s.1) > 9
                         }),
            TutorialStep(title: "Select a worker", text: "Tap the \(wName) under the arrow. (Workers have a yellow hard hat.)",
                         target: { c in c.world.entity(c.tutorial?.focusUnit ?? -1).map { ($0.x, $0.y) } },
                         enter: { c in
                             // One worker stands still so it's easy to tap.
                             guard let h = c.hq, let w = c.world.units(of: c.me).filter({ c.world.traits[$0.type].worker })
                                 .min(by: { dist2($0.x, $0.y, h.x, h.y) < dist2($1.x, $1.y, h.x, h.y) }) else { return }
                             c.world.commandStop([w.id])
                             c.tutorial?.focusUnit = w.id
                         },
                         done: { c in c.selectedEntities.contains { $0.isUnit && c.world.traits[$0.type].worker } }),
            TutorialStep(title: "Gather wood", text: "With your \(wName) selected, tap a tree. Workers gather resources and carry them back to your base.",
                         target: { c in
                             guard let h = c.hq else { return nil }
                             return c.world.entities.filter { $0.alive && $0.isResource && $0.type == ResourceKind.wood.rawValue }
                                 .min { dist2($0.x, $0.y, h.x, h.y) < dist2($1.x, $1.y, h.x, h.y) }.map { ($0.x, $0.y) }
                         },
                         done: { c in c.world.units(of: c.me).contains { c.world.traits[$0.type].worker && ($0.order == .gather || $0.order == .returnCargo) && c.world.entity($0.gatherNode)?.type == ResourceKind.wood.rawValue } }),
            TutorialStep(title: "Select a group", text: "Put two fingers on the screen and drag them together to draw a box around several workers. (Double-tapping a unit selects every unit of that type.)",
                         done: { c in c.selectedEntities.filter { $0.isUnit }.count >= 2 }),
            TutorialStep(title: "Train a worker", text: "More workers means more resources. Tap your HQ, then tap the \(wName) button.",
                         button: { c in "u\(c.workerType)" },
                         target: { $0.hq.map { ($0.x, $0.y) } },
                         done: { c in (c.hq?.queue.contains { !$0.isUpgrade && $0.index == c.workerType } ?? false) || c.world.players[c.me].stats.unitsProduced > 0 }),
            TutorialStep(title: "Build a \(bName)", text: "Select a \(wName), tap Build, choose the \(bName), drag it to an open spot and tap Confirm.",
                         button: { c in
                             if case .place = c.mode { return "confirm" }
                             if c.buildMenu { return "b\(c.barracksType)" }
                             return c.selectedEntities.contains { $0.isUnit && c.world.traits[$0.type].worker } ? "build" : nil
                         },
                         done: { c in c.barracks != nil }),
            TutorialStep(title: "Construction", text: "Your \(wName) is building it — the bar shows progress. Tip: select more \(wName)s and tap the building site to help; more builders finish it faster.",
                         target: { c in c.barracks.map { ($0.x, $0.y) } },
                         enter: { c in c.speed = 2 },
                         done: { c in c.barracks?.complete == true }),
            TutorialStep(title: "Train soldiers", text: "Select your \(bName) and train 3 \(sName)s.",
                         button: { c in "u\(c.soldierType)" },
                         target: { c in c.barracks.map { ($0.x, $0.y) } },
                         enter: { c in c.speed = 1.5 },
                         done: { c in c.soldiers.count >= 3 }),
            TutorialStep(title: "Select your army", text: "Tap Army on the left. It selects every soldier you have.",
                         rail: "army",
                         enter: { c in c.speed = 1 },
                         done: { c in c.selectedEntities.filter { $0.isUnit && !c.world.traits[$0.type].worker }.count >= 3 }),
            TutorialStep(title: "Attack!", text: "Enemy scouts spotted! With your army selected, tap one of the red units to attack.",
                         target: { c in c.tutorial?.spawned.compactMap { c.world.entity($0) }.first.map { ($0.x, $0.y) } },
                         enter: { c in
                             // Practice targets: they fire back but do no damage, so a first fight is never lost.
                             if let u = c.data.unitIndex["m_runner"] { c.world.players[1 - c.me].mods.unit[u].damage = 0 }
                             c.tutorial?.spawned = c.spawnEnemies("m_runner", count: 2, near: c.ahead(11))
                         },
                         done: { c in (c.tutorial?.spawned ?? []).allSatisfy { c.world.entity($0) == nil } }),
            TutorialStep(title: "Capture a site", text: "Glowing platforms are strategic sites: they give resources and win the game if you hold enough. Select your army and tap the platform to capture it.",
                         target: { c in c.tutorialSite.map { (c.world.sites[$0].x, c.world.sites[$0].y) } },
                         done: { c in c.world.sites.contains { $0.owner == c.me && $0.control >= 1 } }),
            TutorialStep(title: "Destroy the outpost", text: "One last target: destroy the enemy relay. Tip: tap Attack-Move, then the target, and your army fights everything on the way.",
                         button: { c in c.selectedEntities.contains { $0.isUnit && !c.world.traits[$0.type].worker } ? "amove" : nil },
                         target: { c in c.world.entity(c.tutorial?.outpost ?? -1).map { ($0.x, $0.y) } },
                         enter: { c in
                             // Just past the site the army has captured, inside its sight.
                             var p = c.ahead(17)
                             if let site = c.world.sites.filter({ $0.owner == c.me }).first, let h = c.hq {
                                 let dx = site.x - h.x, dy = site.y - h.y, l = max(1, (dx * dx + dy * dy).squareRoot())
                                 p = (site.x + dx / l * 5, site.y + dy / l * 5)
                             }
                             let f = c.world.players[1 - c.me].faction
                             if let t = c.data.buildingIDs(f).first(where: { c.data.buildings[$0].kind == .forward }) {
                                 var tx = Int(p.0), ty = Int(p.1)
                                 if c.world.nav.isBlocked(tx, ty) { let o = c.world.nav.nearestOpen(tx, ty); tx = o.0; ty = o.1 }
                                 c.tutorial?.outpost = c.world.spawnBuilding(t, owner: 1 - c.me, tileX: tx, tileY: ty, complete: true).id
                             }
                         },
                         done: { c in c.world.entity(c.tutorial?.outpost ?? -1) == nil }),
            TutorialStep(title: "Training complete!", text: "Great work, Commander. You're ready for a real battle — start on Easy, and use the Commander's guide if you need a hint. Good luck!",
                         info: true),
        ]
    }

    /// The neutral site nearest the player's base.
    var tutorialSite: Int? {
        guard let h = hq else { return nil }
        return world.sites.indices.filter { world.sites[$0].owner != me }
            .min { dist2(world.sites[$0].x, world.sites[$0].y, h.x, h.y) < dist2(world.sites[$1].x, world.sites[$1].y, h.x, h.y) }
    }

    /// Where the bouncing marker should point (world coordinates), if anywhere.
    var tutorialMarker: (Double, Double)? { tutorialStep?.target(self) }
}

extension GameController {
    /// Development autopilot (`-tutorialauto`): plays each step the way a player would, logging progress.
    func tutorialAutopilot() {
        guard let t = tutorial, t.step < tutorialSteps.count else { return }
        let s = tutorialSteps[t.step]
        print("TUT step \(t.step + 1) \(s.title) at \(Int(world.time))s")
        let workers = world.units(of: me).filter { world.traits[$0.type].worker }
        switch t.step {
        case 0, tutorialSteps.count - 1: advanceTutorial()
        case 1:
            if let h = hq { focusCamera?(h.x + 8, h.y + 8) }
        case 2: if let w = world.entity(t.focusUnit) { select([w.id]) }
        case 3:
            if let w = selectedEntities.first, let n = s.target(self).flatMap({ p in world.entities.first { $0.isResource && $0.alive && abs($0.x - p.0) < 0.01 && abs($0.y - p.1) < 0.01 } }) {
                command(at: n.x, y: n.y, target: n); _ = w
            }
        case 4: select(workers.map { $0.id })
        case 5: if let h = hq { select([h.id]); _ = world.commandTrain(h.id, unitType: workerType) }
        case 6:
            guard let h = hq, let w = workers.first else { return }
            search: for r in 4...12 { for dy in -r...r { for dx in -r...r where abs(dx) == r || abs(dy) == r {
                let tx = h.tileX + dx, ty = h.tileY + dy
                if world.placementError(me, barracksType, tileX: tx, tileY: ty) == nil { _ = world.commandBuild([w.id], type: barracksType, tileX: tx, tileY: ty); break search }
            } } }
        case 8: if let b = barracks, b.queue.count < 3 { select([b.id]); _ = world.commandTrain(b.id, unitType: soldierType) }
        case 9: selectArmy()
        case 10: if let e = t.spawned.compactMap({ world.entity($0) }).first { command(at: e.x, y: e.y, target: e) }
        case 11: if let i = tutorialSite { selectArmy(); command(at: world.sites[i].x, y: world.sites[i].y, target: nil) }
        case 12: if let o = world.entity(t.outpost) { selectArmy(); command(at: o.x, y: o.y, target: o) }
        default: break
        }
    }
}

/// Tutorial instruction card.
struct TutorialCard: View {
    @ObservedObject var controller: GameController
    var onExit: () -> Void
    var body: some View {
        if let t = controller.tutorial {
            let n = controller.tutorialSteps.count
            let done = t.step >= n
            let s = done ? nil : controller.tutorialSteps[t.step]
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(done ? "BOOT CAMP" : "BOOT CAMP · STEP \(t.step + 1) OF \(n)").font(.system(size: 9, weight: .heavy)).tracking(2).foregroundColor(Theme.gold)
                    Spacer()
                    Button(done ? "Finish" : "Skip") { onExit() }.font(.system(size: 11, weight: .bold)).buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                }
                if let s = s {
                    Text(s.title).font(.system(size: 16, weight: .heavy))
                    Text(s.text).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    if s.info {
                        Button { if t.step == n - 1 { onExit() } else { controller.advanceTutorial() } } label: {
                            Text(t.step == n - 1 ? "BACK TO MENU" : "NEXT").font(.system(size: 13, weight: .black)).tracking(3)
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(Chamfer(cut: 6).fill(Theme.gold)).foregroundColor(.black)
                        }.buttonStyle(.plain).accessibilityLabel("Tutorial next")
                    }
                }
            }
            .padding(12)
            .background(Chamfer(cut: 10).fill(Color.black.opacity(0.8)))
            .overlay(Chamfer(cut: 10).stroke(Theme.gold.opacity(0.7), lineWidth: 1.5))
            .foregroundColor(.white)
            .frame(maxWidth: 440)
            .padding(.horizontal, 54)
            .animation(.easeInOut(duration: 0.25), value: t.step)
        }
    }
}
