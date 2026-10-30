import SwiftUI
import MeridianCore

/// Touch-first heads-up display layered over the SpriteKit view. Adapts between the Duo's cover screen
/// (narrow portrait), the unfolded inner screen, and landscape/desktop windows.
struct HUDView: View {
    @ObservedObject var controller: GameController
    let scene: GameScene
    @Binding var showPause: Bool

    var showCard: Bool { !controller.hud.buttons.isEmpty || controller.hud.menuTitle != nil }
    var accent: Color { Accent.of(controller.hud.faction) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let landscape = w > h * 1.15
            let compact = w < 520
            let mini = min(landscape ? h * 0.30 : w * (compact ? 0.30 : 0.26), 210)
            VStack(spacing: 6) {
                TopBar(controller: controller, compact: compact, showPause: $showPause, accent: accent)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { scene.hudTopY = $0 }
                ToastStack(controller: controller)
                if controller.tutorial != nil { TutorialCard(controller: controller, onExit: { controller.exitTutorial?() }) }
                if let g = controller.hud.guide { GuideCard(text: g, accent: accent) { controller.guideDismissed = true; controller.refreshHUD() } }
                HStack(alignment: .top) {
                    SideRail(controller: controller, accent: accent)
                    Spacer()
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                if let placing = controller.hud.placing {
                    PlacementBar(controller: controller, title: placing, accent: accent)
                }
                if landscape {
                    HStack(alignment: .bottom, spacing: 8) {
                        MinimapFrame(controller: controller, scene: scene, accent: accent).frame(width: mini * 1.35, height: mini * 0.72)
                        SelectionPanel(controller: controller, accent: accent).frame(maxWidth: .infinity)
                        if showCard { CommandCard(controller: controller, columns: 5, accent: accent).frame(width: min(340, w * 0.36)) }
                    }
                } else {
                    VStack(spacing: 6) {
                        SelectionPanel(controller: controller, compact: compact, accent: accent)
                        HStack(alignment: .bottom, spacing: 6) {
                            MinimapFrame(controller: controller, scene: scene, accent: accent).frame(width: mini * 1.35, height: mini * 0.72)
                            if showCard { CommandCard(controller: controller, columns: compact ? 4 : 5, accent: accent) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                }
                // The scene edge-scrolls from where the HUD ends, not from the screen edge.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { scene.hudBottomY = $0 }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }
}

struct ResourceIcon: View {
    let kind: Int
    var body: some View { ResourceGlyph(kind: kind) }
}

struct ResourceLabel: View {
    let kind: Int
    let value: Int
    let income: Double
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            ResourceGlyph(kind: kind).frame(width: 15, height: 15)
            VStack(alignment: .leading, spacing: -2) {
                Text("\(value)").font(.system(size: compact ? 12.5 : 14, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                if !compact { Text("+\(Int(income))/m").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.5)) }
            }
        }
    }
}

struct TopBar: View {
    @ObservedObject var controller: GameController
    let compact: Bool
    @Binding var showPause: Bool
    let accent: Color
    var body: some View {
        let h = controller.hud
        GlassPanel(accent: accent, padding: 7, cut: 9) {
            HStack(spacing: compact ? 9 : 14) {
                ForEach([0, 2, 1], id: \.self) { k in ResourceLabel(kind: k, value: h.res[k], income: h.income[k], compact: compact) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "person.3.fill").font(.system(size: 9))
                        Text("\(h.units)").font(.system(size: compact ? 11.5 : 13, weight: .semibold, design: .monospaced))
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(h.units >= h.cap ? Color.red : accent).frame(width: g.size.width * CGFloat(h.units) / CGFloat(max(1, h.cap)))
                        }
                    }.frame(width: 34, height: 2.5)
                }
                .foregroundColor(h.units >= h.cap ? .red : .white)
                Spacer(minLength: 0)
                SiteStrip(h: h, compact: compact)
                if !compact {
                    Text(String(format: "%d:%02d", Int(h.time) / 60, Int(h.time) % 60)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                }
                Button { controller.showTech = true } label: { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(.plain).accessibilityLabel("Tech tree")
                Button { showPause = true; controller.paused = true; SoundEngine.shared?.play("click", at: nil) } label: { Image(systemName: "pause.circle.fill").font(.system(size: 21)) }
                    .buttonStyle(.plain).accessibilityLabel("Pause")
            }
            .foregroundColor(.white)
        }
    }
}

/// Seven diamond pips coloured by site owner, with the dominance countdown when active.
struct SiteStrip: View {
    let h: HUDState
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2.5) {
                ForEach(Array(h.siteOwners.enumerated()), id: \.offset) { i, o in
                    let pr = i < h.siteProgress.count ? h.siteProgress[i] : 0
                    Rectangle()
                        .fill(o >= 0 ? Theme.team(o) : Color.white.opacity(0.15))
                        .overlay(Rectangle().stroke(Color.white.opacity(o >= 0 ? 0.5 : 0.25), lineWidth: 0.6))
                        .overlay(alignment: .bottom) {
                            if o < 0 && abs(pr) > 0.02 { Rectangle().fill(Color.white.opacity(0.6)).frame(height: 7 * CGFloat(abs(pr))) }
                        }
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(45))
                        .frame(width: compact ? 8 : 10, height: 10)
                }
            }
            if h.myDominance > 0 || h.enemyDominance > 0 {
                let mine = h.myDominance >= h.enemyDominance
                let left = Int(h.dominanceSeconds - max(h.myDominance, h.enemyDominance))
                Text("\(mine ? "WIN" : "LOSE") \(left / 60):\(String(format: "%02d", left % 60))")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(mine ? Theme.team(0) : Theme.team(1)))
                    .foregroundColor(.black)
            }
        }
        .accessibilityLabel("Sites: \(h.sitesOwned) yours, \(h.sitesEnemy) enemy")
    }
}

/// Pulsing gold frame marking the control the tutorial wants pressed.
struct GlowFrame: View {
    var cut: CGFloat
    @State private var on = false
    var body: some View {
        Chamfer(cut: cut).stroke(Theme.gold, lineWidth: on ? 3 : 1.5)
            .shadow(color: Theme.gold.opacity(on ? 0.9 : 0.3), radius: on ? 8 : 3)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { on = true } }
    }
}

/// Commander's guide card: one suggested next step, dismissible.
struct GuideCard: View {
    let text: String
    let accent: Color
    var onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundColor(Theme.gold).font(.system(size: 13))
            Text(text).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).padding(4) }
                .buttonStyle(.plain).accessibilityLabel("Hide guide")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Chamfer(cut: 7).fill(Color.black.opacity(0.72)))
        .overlay(Chamfer(cut: 7).stroke(Theme.gold.opacity(0.55), lineWidth: 1))
        .foregroundColor(.white)
        .frame(maxWidth: 420)
        .padding(.horizontal, 60)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: text)
    }
}

struct ToastStack: View {
    @ObservedObject var controller: GameController
    var body: some View {
        VStack(spacing: 4) {
            ForEach(controller.toasts) { t in
                Button {
                    if let at = t.at { controller.focusCamera?(at.0, at.1); Haptics.tap() }
                } label: { toastRow(t) }
                .buttonStyle(.plain)
                .allowsHitTesting(t.at != nil)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.toasts.map { $0.id })
    }

    func toastRow(_ t: Toast) -> some View {
                HStack(spacing: 6) {
                    Image(systemName: t.warning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundColor(t.warning ? Color(red: 1, green: 0.45, blue: 0.35) : Theme.accent)
                    Text(t.text).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Chamfer(cut: 6).fill(Color.black.opacity(0.72)))
                .overlay(Chamfer(cut: 6).stroke((t.warning ? Color.red : Theme.accent).opacity(0.5), lineWidth: 1))
                .foregroundColor(.white)
                .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SideRail: View {
    @ObservedObject var controller: GameController
    let accent: Color
    var body: some View {
        VStack(spacing: 6) {
            railButton("figure.walk.motion", "Army", badge: controller.hud.armyCount) { controller.selectArmy() }
                .overlay { if controller.hud.tutorialRail == "army" { GlowFrame(cut: 6) } }
            if ProcessInfo.processInfo.arguments.contains("-uitest") {
                // UI tests cannot perform hold-and-drag box selection; this stands in for a box select of the workers.
                railButton("person.3", "Workers", badge: 0) { controller.selectWorkers() }.accessibilityIdentifier("test_select_workers")
            }
            railButton("hammer.circle", "Idle", badge: controller.hud.idleWorkers, alert: controller.hud.idleWorkers > 0) { controller.selectIdleWorker() }
            ForEach(1...4, id: \.self) { n in
                let g = controller.controlGroups[n]?.compactMap { controller.world.entity($0) } ?? []
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        if let f = g.first, f.isUnit, let img = IconCache.unit(f.type) {
                            Image(decorative: img, scale: 2).resizable().scaledToFit().frame(width: 22, height: 18)
                        }
                        Text("\(n)").font(.system(size: g.isEmpty ? 14 : 10, weight: .heavy, design: .rounded))
                    }
                    if !g.isEmpty { Text("\(g.count)").font(.system(size: 8, weight: .bold)).padding(2).background(Capsule().fill(accent)).foregroundColor(.black).offset(x: 4, y: -4) }
                }
                .frame(width: 40, height: 34)
                .background(Chamfer(cut: 6).fill(g.isEmpty ? Color.black.opacity(0.55) : accent.opacity(0.22)))
                .overlay(Chamfer(cut: 6).stroke(Color.white.opacity(0.14)))
                .foregroundColor(.white)
                .onTapGesture { controller.groupRecall(n); SoundEngine.shared?.play("click", at: nil) }
                .onLongPressGesture(minimumDuration: 0.4) { controller.groupAssign(n); SoundEngine.shared?.play("confirm", at: nil) }
                .accessibilityLabel("Control group \(n). Long press to assign.")
            }
        }
    }

    func railButton(_ sym: String, _ label: String, badge: Int, alert: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { action(); SoundEngine.shared?.play("click", at: nil) } label: {
            VStack(spacing: 1) {
                Image(systemName: sym).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 8, weight: .bold))
            }
            .frame(width: 40, height: 40)
            .background(Chamfer(cut: 6).fill(Color.black.opacity(0.6)))
            .overlay(Chamfer(cut: 6).stroke(alert ? Color.orange.opacity(0.8) : Color.white.opacity(0.14)))
            .overlay(alignment: .topTrailing) {
                if badge > 0 { Text("\(badge)").font(.system(size: 8, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1).background(Capsule().fill(alert ? Color.orange : accent)).foregroundColor(.black).offset(x: 5, y: -5) }
            }
        }
        .buttonStyle(.plain).foregroundColor(.white)
        .accessibilityLabel(label)
    }
}

struct PlacementBar: View {
    @ObservedObject var controller: GameController
    let title: String
    let accent: Color
    var body: some View {
        let h = controller.hud
        GlassPanel(accent: h.placementValid ? .green : .orange, padding: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill").foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Placing \(title)").font(.system(size: 13, weight: .bold))
                    Text(h.placementReason ?? "Drag to adjust, then confirm").font(.system(size: 11)).accessibilityIdentifier("placementReason")
                        .foregroundColor(h.placementValid ? Color.green : Color.orange)
                }
                Spacer()
                Button { controller.cancelMode() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 36) }
                    .buttonStyle(.bordered)
                Button { controller.confirmPlacement() } label: { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).frame(width: 52, height: 36) }
                    .buttonStyle(.borderedProminent).tint(.green).disabled(!h.placementValid)
                    .accessibilityLabel("Confirm placement").accessibilityIdentifier("confirmPlacement")
            }
            .foregroundColor(.white)
        }
    }
}

struct SelectionPanel: View {
    @ObservedObject var controller: GameController
    var compact = false
    let accent: Color
    @State private var expanded = false

    var body: some View {
        let h = controller.hud
        GlassPanel(accent: accent, padding: 8) {
            if h.selectionTitle.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").foregroundColor(accent.opacity(0.8))
                    Text(controller.mode == .normal ? "Drag to move · Hold, then drag to select" : (h.menuTitle ?? ""))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if let pt = h.portrait {
                        if pt.unit { UnitPortraitView(unitID: controller.data.units[pt.type].id, unitType: pt.type, owner: pt.owner, size: compact ? 66 : 78, radio: controller.radio) }
                        else { Portrait(type: pt.type, building: pt.building, owner: pt.owner, size: compact ? 48 : 56) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(h.selectionTitle).font(.system(size: 15, weight: .bold)).accessibilityIdentifier("selectionTitle")
                            Text(h.selectionSubtitle).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        if let hp = h.selectionHP {
                            HStack(spacing: 6) {
                                HealthBar(frac: hp.0 / max(1, hp.1))
                                Text("\(Int(hp.0))/\(Int(hp.1))").font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.65))
                            }
                        }
                        if !h.stats.isEmpty || !h.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(h.stats.enumerated()), id: \.offset) { _, s in StatChip(symbol: s.symbol, value: s.value) }
                                ForEach(h.tags, id: \.self) { Chip(text: $0, color: accent) }
                            }
                        }
                        if !h.selectionIcons.isEmpty { tiles(h) }
                        if !h.queue.isEmpty { queue(h) }
                        if !h.selectionDetail.isEmpty && h.selectionIcons.isEmpty {
                            Text(h.selectionDetail).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.72))
                                .lineLimit(expanded ? 8 : (compact ? 2 : 3)).fixedSize(horizontal: false, vertical: true)
                                .onTapGesture { expanded.toggle() }
                        }
                    }
                }
            }
        }
        .foregroundColor(.white)
        .overlay(alignment: .topLeading) {
            RadioSubtitle(radio: controller.radio, accent: accent).offset(x: 4, y: -30)
                .animation(.easeOut(duration: 0.2), value: controller.radio.line?.id)
        }
    }

    func tiles(_ h: HUDState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(h.selectionIcons.prefix(12), id: \.type) { t in
                    VStack(spacing: 1) {
                        ZStack(alignment: .bottomTrailing) {
                            Portrait(type: t.type, building: false, owner: controller.me, size: 34)
                            Text("\(t.count)").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 3).background(Capsule().fill(Color.black.opacity(0.75)))
                        }
                        HealthBar(frac: h.tileHP[t.type] ?? 1, height: 3).frame(width: 30)
                    }
                    .onTapGesture {
                        // Narrow the selection to this type.
                        controller.select(controller.selection.filter { controller.world.entity($0)?.type == t.type && controller.world.entity($0)?.isUnit == true })
                        SoundEngine.shared?.play("click", at: nil)
                    }
                }
            }
        }
    }

    func queue(_ h: HUDState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(h.queue) { q in
                    HStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
                            Circle().trim(from: 0, to: CGFloat(q.progress)).stroke(q.isUpgrade ? Color.purple : accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        }.frame(width: 16, height: 16)
                        Text(q.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Chamfer(cut: 5).fill(Color.white.opacity(0.07)))
                    .onTapGesture { if let b = controller.selection.first { controller.world.commandCancel(b, index: q.id); controller.refreshHUD(); SoundEngine.shared?.play("cancel", at: nil) } }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("queue_\(q.id)")
                }
            }
        }
    }
}

struct CommandCard: View {
    @ObservedObject var controller: GameController
    var columns: Int
    let accent: Color
    @State private var info: CommandButton.ID? = nil

    var body: some View {
        let h = controller.hud
        GlassPanel(accent: accent, padding: 6) {
            VStack(alignment: .leading, spacing: 4) {
                if let t = h.menuTitle { Text(t.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(accent.opacity(0.9)) }
                if let id = info, let b = h.buttons.first(where: { $0.id == id }) {
                    HStack(spacing: 6) {
                        Text(b.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                        if let c = b.cost { CostLine(cost: c) }
                    }
                    if let r = b.reason { Text(r).font(.system(size: 9.5)).foregroundColor(.orange).lineLimit(2) }
                    else if let d = b.detail { Text(d).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.7)).lineLimit(2) }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: columns), spacing: 4) {
                        ForEach(h.buttons) { b in
                            CommandButtonView(button: b, accent: accent)
                                .onLongPressGesture(minimumDuration: 0.35) { info = b.id }
                                .simultaneousGesture(TapGesture().onEnded {
                                    info = b.id
                                    if b.enabled { b.action(); SoundEngine.shared?.play("confirm", at: nil) } else { SoundEngine.shared?.play("denied", at: nil) }
                                })
                        }
                    }
                }
                .frame(height: CGFloat(min(3, max(1, (h.buttons.count + columns - 1) / columns))) * 64)
            }
        }
        .frame(width: CGFloat(columns) * 60 + 12)
        .foregroundColor(.white)
    }
}

struct CostLine: View {
    let cost: Cost
    var body: some View {
        HStack(spacing: 5) {
            if cost.iron > 0 { HStack(spacing: 1) { ResourceGlyph(kind: 0).frame(width: 9, height: 9); Text("\(cost.iron)") } }
            if cost.wood > 0 { HStack(spacing: 1) { ResourceGlyph(kind: 2).frame(width: 9, height: 9); Text("\(cost.wood)") } }
            if cost.gold > 0 { HStack(spacing: 1) { ResourceGlyph(kind: 1).frame(width: 9, height: 9); Text("\(cost.gold)") } }
        }.font(.system(size: 9, weight: .semibold, design: .monospaced))
    }
}

struct CommandButtonView: View {
    let button: CommandButton
    let accent: Color
    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                icon.frame(width: 34, height: 30)
                if let p = button.progress {
                    Circle().trim(from: 0, to: CGFloat(p)).stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 38, height: 38)
                }
            }
            Text(button.title).font(.system(size: 7.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            if let c = button.cost, !c.isZero {
                // Costs you can't cover yet show in red.
                let short = button.reason?.hasPrefix("Need ") == true ? button.reason! : ""
                HStack(spacing: 2) {
                    if c.iron > 0 { Text("\(c.iron)").foregroundColor(short.contains("iron") ? .red : Theme.iron) }
                    if c.wood > 0 { Text("\(c.wood)").foregroundColor(short.contains("wood") ? .red : Theme.wood) }
                    if c.gold > 0 { Text("\(c.gold)").foregroundColor(short.contains("gold") ? .red : Theme.gold) }
                }.font(.system(size: 7, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: 56, height: 62)
        .background(Chamfer(cut: 7).fill(LinearGradient(colors: button.highlighted ? [Color.purple.opacity(0.45), Color.purple.opacity(0.15)]
                                                         : [Color.white.opacity(button.enabled ? 0.13 : 0.04), Color.white.opacity(button.enabled ? 0.04 : 0.02)], startPoint: .top, endPoint: .bottom)))
        .overlay(Chamfer(cut: 7).stroke(button.enabled ? accent.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1))
        .overlay { if button.glow { GlowFrame(cut: 7) } }
        .overlay(alignment: .topTrailing) {
            if button.queued > 0 {
                Text("\(button.queued)").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 4).padding(.vertical, 1).background(Capsule().fill(accent)).foregroundColor(.black).padding(2)
            } else if let b = button.badge {
                Text(b).font(.system(size: 8, weight: .bold)).padding(2).background(Capsule().fill(accent)).foregroundColor(.black).padding(2)
            }
        }
        .overlay(alignment: .topLeading) {
            if !button.enabled && button.reason?.hasPrefix("Requires") == true {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundColor(.white.opacity(0.5)).padding(4)
            } else if Self.showHotkeys, let k = button.hotkey, k.isLetter {
                Text(String(k).uppercased()).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.35)).padding(4)
            }
        }
        .opacity(button.enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button.title)
        .accessibilityIdentifier("cmd_" + button.id)
        .accessibilityAddTraits(.isButton)
    }

    /// Keyboard letters only matter with a hardware keyboard (Mac); on a touch screen they're clutter.
    #if os(iOS)
    static let showHotkeys = ProcessInfo.processInfo.isiOSAppOnMac
    #else
    static let showHotkeys = true
    #endif

    @ViewBuilder var icon: some View {
        let s = button.symbol
        if s.hasPrefix("unit:"), let i = Int(s.dropFirst(5)), let img = IconCache.unit(i) {
            Image(decorative: img, scale: 2).resizable().scaledToFit()
        } else if s.hasPrefix("building:"), let i = Int(s.dropFirst(9)), let img = IconCache.building(i) {
            Image(decorative: img, scale: 2).resizable().scaledToFit()
        } else if s.hasPrefix("upgrade:") {
            UpgradeGlyph(tier: Int(s.dropFirst(8)) ?? 1, size: 28)
        } else {
            Image(systemName: s).font(.system(size: 19, weight: .semibold)).foregroundColor(accent)
        }
    }
}

/// Minimap inside a framed glass bezel.
struct MinimapFrame: View {
    @ObservedObject var controller: GameController
    let scene: GameScene
    let accent: Color
    var body: some View {
        MinimapView(controller: controller, scene: scene)
            .padding(3)
            .background(Chamfer(cut: 9).fill(Color.black.opacity(0.8)))
            .overlay(Chamfer(cut: 9).stroke(accent.opacity(0.55), lineWidth: 1.2))
    }
}
