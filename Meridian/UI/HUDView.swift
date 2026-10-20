import SwiftUI
import MeridianCore

/// Touch-first heads-up display layered over the SpriteKit view. Adapts between the Duo's cover screen
/// (narrow portrait), the unfolded inner screen, and landscape/desktop windows.
struct HUDView: View {
    @ObservedObject var controller: GameController
    let scene: GameScene
    @Binding var showPause: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let landscape = w > h * 1.15
            let compact = w < 520
            let mini = min(landscape ? h * 0.32 : w * (compact ? 0.30 : 0.27), 220)
            VStack(spacing: 6) {
                TopBar(controller: controller, compact: compact, showPause: $showPause)
                ToastStack(controller: controller)
                HStack(alignment: .top) {
                    SideButtons(controller: controller)
                    Spacer()
                }
                Spacer(minLength: 0)
                if let placing = controller.hud.placing {
                    PlacementBar(controller: controller, title: placing)
                }
                if landscape {
                    HStack(alignment: .bottom, spacing: 8) {
                        MinimapView(controller: controller, scene: scene).frame(width: mini * 1.3, height: mini * 0.68)
                        SelectionPanel(controller: controller).frame(maxWidth: .infinity)
                        CommandCard(controller: controller, columns: 5).frame(width: min(330, w * 0.36))
                    }
                } else {
                    VStack(spacing: 6) {
                        SelectionPanel(controller: controller, compact: compact)
                        HStack(alignment: .bottom, spacing: 6) {
                            MinimapView(controller: controller, scene: scene).frame(width: mini * 1.3, height: mini * 0.68)
                            CommandCard(controller: controller, columns: compact ? 4 : 5)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }
}

struct ResourceLabel: View {
    let kind: Int
    let value: Int
    let income: Double
    let compact: Bool
    var body: some View {
        HStack(spacing: 3) {
            ResourceIcon(kind: kind).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: -2) {
                Text("\(value)").font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                if !compact { Text("+\(Int(income))/m").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.55)) }
            }
        }
    }
}

struct ResourceIcon: View {
    let kind: Int
    var body: some View {
        switch kind {
        case 0: RoundedRectangle(cornerRadius: 2).fill(Theme.iron).rotationEffect(.degrees(45)).scaleEffect(0.75)
        case 1: Circle().fill(Theme.gold).overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        default: Capsule().fill(Theme.wood).frame(height: 7).rotationEffect(.degrees(-30))
        }
    }
}

struct TopBar: View {
    @ObservedObject var controller: GameController
    let compact: Bool
    @Binding var showPause: Bool
    var body: some View {
        let h = controller.hud
        Panel(padding: 6) {
            HStack(spacing: compact ? 8 : 14) {
                ForEach(0..<3, id: \.self) { k in ResourceLabel(kind: [0, 2, 1][k], value: h.res[[0, 2, 1][k]], income: h.income[[0, 2, 1][k]], compact: compact) }
                HStack(spacing: 3) {
                    Image(systemName: "person.3.fill").font(.system(size: 10))
                    Text("\(h.units)/\(h.cap)").font(.system(size: compact ? 11 : 13, weight: .semibold, design: .monospaced))
                }.foregroundColor(h.units >= h.cap ? .red : .white)
                Spacer(minLength: 0)
                SitesIndicator(h: h, compact: compact)
                if !compact {
                    Text(String(format: "%d:%02d", Int(h.time) / 60, Int(h.time) % 60)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                }
                Button { controller.showTech = true } label: { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 15, weight: .semibold)) }
                    .buttonStyle(.plain).accessibilityLabel("Tech tree")
                Button { showPause = true; controller.paused = true } label: { Image(systemName: "pause.circle.fill").font(.system(size: 20)) }
                    .buttonStyle(.plain).accessibilityLabel("Pause")
            }
            .foregroundColor(.white)
        }
    }
}

struct SitesIndicator: View {
    let h: HUDState
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.2.crossed.fill").font(.system(size: 11))
            Text("\(h.sitesOwned)").foregroundColor(Theme.team(0)).bold()
            Text("/").foregroundColor(.white.opacity(0.4))
            Text("\(h.sitesEnemy)").foregroundColor(Theme.team(1)).bold()
            if h.myDominance > 0 || h.enemyDominance > 0 {
                let mine = h.myDominance >= h.enemyDominance
                let left = Int(h.dominanceSeconds - max(h.myDominance, h.enemyDominance))
                Text("\(mine ? "WIN" : "LOSS") in \(left / 60):\(String(format: "%02d", left % 60))")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(mine ? Theme.team(0) : Theme.team(1)))
                    .foregroundColor(.black)
            } else if !compact && !h.dominanceActive {
                Text("need \(h.dominanceNeed)").font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
            }
        }
        .font(.system(size: 13, design: .monospaced))
    }
}

struct ToastStack: View {
    @ObservedObject var controller: GameController
    var body: some View {
        VStack(spacing: 3) {
            ForEach(controller.toasts) { t in
                Text(t.text).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(t.warning ? Color(red: 0.55, green: 0.12, blue: 0.1).opacity(0.9) : Color.black.opacity(0.7)))
                    .foregroundColor(.white)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: controller.toasts.map { $0.id })
    }
}

struct SideButtons: View {
    @ObservedObject var controller: GameController
    var body: some View {
        VStack(spacing: 6) {
            side("figure.walk.motion", "Army") { controller.selectArmy() }
            side("hammer.circle", "Idle") { controller.selectIdleWorker() }
            ForEach(1...4, id: \.self) { n in
                Text("\(n)").font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(width: 38, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(controller.controlGroups[n]?.isEmpty == false ? Theme.accent.opacity(0.35) : Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.panelStroke))
                    .onTapGesture { controller.groupRecall(n) }
                    .onLongPressGesture(minimumDuration: 0.4) { controller.groupAssign(n) }
                    .accessibilityLabel("Control group \(n). Long press to assign.")
            }
        }
    }

    func side(_ sym: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: sym).font(.system(size: 15))
                Text(label).font(.system(size: 8, weight: .semibold))
            }
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.panelStroke))
        }
        .buttonStyle(.plain).foregroundColor(.white)
    }
}

struct PlacementBar: View {
    @ObservedObject var controller: GameController
    let title: String
    var body: some View {
        let h = controller.hud
        Panel(padding: 8) {
            HStack(spacing: 10) {
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
        }
    }
}

struct SelectionPanel: View {
    @ObservedObject var controller: GameController
    var compact = false
    var body: some View {
        let h = controller.hud
        Panel(padding: 8) {
            if h.selectionTitle.isEmpty {
                HStack {
                    Text(controller.mode == .normal ? "Tap a unit or building. Hold and drag to box-select." : (h.menuTitle ?? ""))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(h.selectionTitle).font(.system(size: 15, weight: .bold)).accessibilityIdentifier("selectionTitle")
                        Text(h.selectionSubtitle).font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    if let hp = h.selectionHP {
                        HStack(spacing: 6) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.12))
                                    Capsule().fill(hp.0 / hp.1 > 0.5 ? Color.green : (hp.0 / hp.1 > 0.25 ? Color.yellow : Color.red))
                                        .frame(width: g.size.width * CGFloat(max(0, min(1, hp.0 / max(1, hp.1)))))
                                }
                            }.frame(height: 6)
                            Text("\(Int(hp.0))/\(Int(hp.1))").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                        }
                    }
                    if !h.queue.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(h.queue) { q in
                                    VStack(spacing: 1) {
                                        Text(q.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                                        ProgressView(value: q.progress).tint(q.isUpgrade ? .purple : Theme.accent).frame(width: 60)
                                    }
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                                    .onTapGesture { if let b = controller.selection.first { controller.world.commandCancel(b, index: q.id); controller.refreshHUD() } }
                                    .accessibilityElement(children: .combine).accessibilityIdentifier("queue_\(q.id)")
                                }
                            }
                        }
                    }
                    if !h.selectionDetail.isEmpty {
                        Text(h.selectionDetail).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.75))
                            .lineLimit(compact ? 3 : 5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .foregroundColor(.white)
    }
}

struct CommandCard: View {
    @ObservedObject var controller: GameController
    var columns: Int
    @State private var info: CommandButton.ID? = nil

    var body: some View {
        let h = controller.hud
        Panel(padding: 6) {
            VStack(alignment: .leading, spacing: 4) {
                if let t = h.menuTitle { Text(t).font(.system(size: 10, weight: .bold)).tracking(1).foregroundColor(.white.opacity(0.6)) }
                if let id = info, let b = h.buttons.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.title).font(.system(size: 11, weight: .bold))
                        if let c = b.cost { CostLine(cost: c) }
                        if let r = b.reason { Text(r).font(.system(size: 9.5)).foregroundColor(.orange) }
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 4), count: columns), spacing: 4) {
                        ForEach(h.buttons) { b in
                            CommandButtonView(button: b, controller: controller)
                                .onLongPressGesture(minimumDuration: 0.35) { info = b.id }
                                .simultaneousGesture(TapGesture().onEnded { info = b.id; if b.enabled { b.action() } })
                        }
                    }
                }
                .frame(height: CGFloat(min(3, max(1, (h.buttons.count + columns - 1) / columns))) * 54)
            }
        }
        .frame(width: CGFloat(columns) * 58 + 12)
        .opacity(h.buttons.isEmpty && h.menuTitle == nil ? 0 : 1)
        .foregroundColor(.white)
    }
}

struct CostLine: View {
    let cost: Cost
    var body: some View {
        HStack(spacing: 5) {
            if cost.iron > 0 { HStack(spacing: 1) { ResourceIcon(kind: 0).frame(width: 8, height: 8); Text("\(cost.iron)") } }
            if cost.wood > 0 { HStack(spacing: 1) { ResourceIcon(kind: 2).frame(width: 8, height: 8); Text("\(cost.wood)") } }
            if cost.gold > 0 { HStack(spacing: 1) { ResourceIcon(kind: 1).frame(width: 8, height: 8); Text("\(cost.gold)") } }
        }.font(.system(size: 9, weight: .semibold, design: .monospaced))
    }
}

struct CommandButtonView: View {
    let button: CommandButton
    let controller: GameController
    var body: some View {
        VStack(spacing: 1) {
            icon.frame(width: 30, height: 26)
            Text(button.title).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: 54, height: 50)
        .background(RoundedRectangle(cornerRadius: 8).fill(button.highlighted ? Color.purple.opacity(0.35) : Color.white.opacity(button.enabled ? 0.09 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(button.enabled ? Color.white.opacity(0.25) : Color.white.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            if let b = button.badge { Text(b).font(.system(size: 8, weight: .bold)).padding(2).background(Capsule().fill(Theme.accent)).foregroundColor(.black) }
        }
        .overlay(alignment: .bottomLeading) {
            if let k = button.hotkey, k.isLetter {
                Text(String(k).uppercased()).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.4)).padding(3)
            }
        }
        .opacity(button.enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button.title)
        .accessibilityIdentifier("cmd_" + button.id)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder var icon: some View {
        let s = button.symbol
        if s.hasPrefix("unit:"), let i = Int(s.dropFirst(5)), let img = TextureBank.cache.values.first?.unitIcons[i] {
            Image(decorative: img, scale: 2).resizable().scaledToFit()
        } else if s.hasPrefix("building:"), let i = Int(s.dropFirst(9)), let img = TextureBank.cache.values.first?.buildingIcons[i] {
            Image(decorative: img, scale: 2).resizable().scaledToFit()
        } else if s.hasPrefix("upgrade:") {
            let tier = Int(s.dropFirst(8)) ?? 1
            ZStack {
                RoundedRectangle(cornerRadius: 4).stroke(Color.purple.opacity(0.9), lineWidth: 1.5)
                Text(String(repeating: "▲", count: max(1, tier))).font(.system(size: 8)).foregroundColor(.purple)
            }.frame(width: 24, height: 22)
        } else {
            Image(systemName: s).font(.system(size: 18, weight: .semibold))
        }
    }
}
