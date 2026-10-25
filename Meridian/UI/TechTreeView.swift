import SwiftUI
import MeridianCore

/// The faction's tech: units and upgrades by tier, and a Buildings tab showing what each structure
/// costs, needs, trains and researches.
struct TechTreeView: View {
    @ObservedObject var controller: GameController
    @Environment(\.dismiss) var dismiss
    @State private var tab = 0

    var body: some View {
        let w = controller.world
        let p = w.players[controller.me]
        let data = w.data
        let accent = Theme.faction(p.faction)
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    Text("Units & Upgrades").tag(0)
                    Text("Buildings").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                .accessibilityIdentifier("techTabs")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if tab == 0 { unitsTab(w, p, data, accent) } else { buildingsTab(w, p, data, accent) }
                    }
                    .padding()
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("\(data.faction(p.faction).name) Tech")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem { Button("Close") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Units & upgrades

    @ViewBuilder
    func unitsTab(_ w: World, _ p: Player, _ data: GameData, _ accent: Color) -> some View {
        Text(data.faction(p.faction).description).font(.callout).foregroundColor(.secondary)
        ForEach(1...3, id: \.self) { tier in
            VStack(alignment: .leading, spacing: 8) {
                Text("TIER \(tier)").font(.system(size: 12, weight: .heavy)).tracking(3).foregroundColor(accent)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(data.unitIDs(p.faction).filter { unitTier(data.units[$0]) == tier }, id: \.self) { u in
                        let d = data.units[u]
                        let miss = p.missing(d.requires, data)
                        TechCard(title: d.name, subtitle: "\(d.role.capitalized) · trained at \(buildingName(d.producedAt, p.faction, data))",
                                 detail: "\(d.description)\nStrong: \(d.strongVs)\nWeak: \(d.weakVs)",
                                 cost: d.cost, status: miss.isEmpty ? "Available" : "Needs " + miss.joined(separator: ", "), ok: miss.isEmpty) {
                            TechIcon(image: IconCache.unit(u))
                        }
                    }
                    ForEach(data.upgradeIDs(p.faction).filter { data.upgrades[$0].tier == tier }, id: \.self) { g in
                        let d = data.upgrades[g]
                        let done = p.completedUpgrades.contains(g)
                        let st = done ? "Researched" : (p.researching.contains(g) ? "Researching…" : (w.upgradeAvailability(controller.me, g) ?? "Ready to research"))
                        TechCard(title: d.name, subtitle: "Upgrade · researched at \(buildingName(d.researchedAt, p.faction, data))",
                                 detail: d.description + (d.exclusiveWith.map { "\nExclusive with \(data.upgrades[data.upgradeIndex[$0]!].name)" } ?? ""),
                                 cost: d.cost, status: st, ok: done) {
                            UpgradeGlyph(tier: d.tier, size: 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: Buildings

    @ViewBuilder
    func buildingsTab(_ w: World, _ p: Player, _ data: GameData, _ accent: Color) -> some View {
        Text("Your structures: what each one costs, needs, and unlocks. Tap a worker's Build button to place one.")
            .font(.callout).foregroundColor(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(data.buildingIDs(p.faction), id: \.self) { b in
                BuildingCard(building: b, controller: controller, accent: accent)
            }
        }
    }

    func unitTier(_ u: UnitDef) -> Int {
        if u.requires.contains(where: { $0.hasSuffix("tier3") }) { return 3 }
        if u.requires.contains(where: { $0.hasSuffix("tier2") }) || [.heavy, .air].contains(u.producedAt) { return 2 }
        return 1
    }
}

/// The faction's building of a kind ("Drill Hall" rather than "infantry").
func buildingName(_ k: BuildingKind, _ f: Faction, _ data: GameData) -> String {
    data.buildingIDs(f).first { data.buildings[$0].kind == k }.map { data.buildings[$0].name } ?? k.rawValue.capitalized
}

struct BuildingCard: View {
    let building: Int
    @ObservedObject var controller: GameController
    let accent: Color

    var body: some View {
        let w = controller.world, p = w.players[controller.me], data = w.data
        let d = data.buildings[building]
        let owned = w.buildings(of: controller.me).filter { $0.type == building }
        let built = owned.filter { $0.complete }.count, building_ = owned.count - built
        let miss = p.missing(d.requires, data)
        let trains = data.unitIDs(p.faction).filter { data.units[$0].producedAt == d.kind }
        let researches = data.upgradeIDs(p.faction).filter { data.upgrades[$0].researchedAt == d.kind }
        let status = built > 0 ? "You have \(built)" + (building_ > 0 ? " (+\(building_) building)" : "")
            : (building_ > 0 ? "Under construction" : (miss.isEmpty ? "Ready to build" : "Needs " + miss.joined(separator: ", ")))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TechIcon(image: IconCache.building(building), size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.name).font(.system(size: 15, weight: .bold))
                    Text(kindTitle(d.kind)).font(.system(size: 10.5)).foregroundColor(.secondary)
                    CostLine(cost: w.buildingCost(controller.me, building))
                    HStack(spacing: 8) {
                        stat("heart.fill", "\(Int(d.hp))")
                        stat("shield.fill", fmt(d.armor))
                        stat("hourglass", "\(Int(d.buildTime))s")
                        if let wpn = d.weapon { stat("burst.fill", "\(fmt(wpn.damage))"); stat("scope", fmt(wpn.range)) }
                    }
                    Text(status).font(.system(size: 10.5, weight: .semibold)).foregroundColor(built > 0 ? .green : (miss.isEmpty ? accent : .orange))
                }
                Spacer(minLength: 0)
            }
            Text(d.description).font(.system(size: 11)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            if !trains.isEmpty {
                section("TRAINS")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6, alignment: .top)], alignment: .leading, spacing: 6) {
                        ForEach(trains, id: \.self) { u in
                            let ok = p.missing(data.units[u].requires, data).isEmpty
                            VStack(spacing: 2) {
                                TechIcon(image: IconCache.unit(u), size: 38)
                                Text(data.units[u].name).font(.system(size: 8.5, weight: .semibold)).lineLimit(1).frame(width: 58)
                            }
                            .opacity(ok ? 1 : 0.45)
                        }
                }
            }
            if !researches.isEmpty {
                section("RESEARCHES")
                FlowText(items: researches.map { g in
                    let done = p.completedUpgrades.contains(g)
                    return (data.upgrades[g].name + (done ? " ✓" : ""), done)
                }, accent: accent)
            }
        }
        .padding(10)
        .background(Chamfer(cut: 10).fill(LinearGradient(colors: [Color.white.opacity(built > 0 ? 0.10 : 0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
        .overlay(Chamfer(cut: 10).stroke(built > 0 ? accent.opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
    }

    func kindTitle(_ k: BuildingKind) -> String {
        switch k {
        case .hq: return "Headquarters · trains workers, takes deliveries"
        case .depot: return "Depot · resource drop-off point"
        case .infantry: return "Barracks · infantry"
        case .heavy: return "Factory · vehicles and heavy units"
        case .air: return "Airfield · aircraft"
        case .research: return "Research · upgrades and higher tiers"
        case .tower: return "Defence tower"
        case .forward: return "Forward post"
        }
    }

    func stat(_ s: String, _ v: String) -> some View {
        HStack(spacing: 2) { Image(systemName: s).font(.system(size: 8)); Text(v) }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.8))
    }

    func section(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).tracking(2).foregroundColor(accent.opacity(0.9))
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

/// Small wrapped chips.
struct FlowText: View {
    let items: [(String, Bool)]
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 4) {
                    UpgradeGlyph(tier: 1, size: 14)
                    Text(it.0).font(.system(size: 10, weight: .semibold)).foregroundColor(it.1 ? .green : .white.opacity(0.85))
                }
            }
        }
    }
}

/// A fixed-size icon tile, so cards never resize or blank while images load.
struct TechIcon: View {
    let image: CGImage?
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Chamfer(cut: size * 0.16).fill(Color.white.opacity(0.06))
            if let i = image { Image(decorative: i, scale: 2).resizable().interpolation(.high).scaledToFit().padding(size * 0.06) }
        }
        .frame(width: size, height: size)
    }
}

/// Upgrade emblem (shared by the tech tree and the command card).
struct UpgradeGlyph: View {
    let tier: Int
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Chamfer(cut: size * 0.18).fill(LinearGradient(colors: [Color.purple.opacity(0.5), Color.indigo.opacity(0.3)], startPoint: .top, endPoint: .bottom))
            Chamfer(cut: size * 0.18).stroke(Color.purple.opacity(0.9), lineWidth: 1)
            VStack(spacing: 0) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: size * 0.46))
                if size >= 24 { Text(String(repeating: "I", count: max(1, tier))).font(.system(size: size * 0.25, weight: .heavy)) }
            }.foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

struct TechCard<Icon: View>: View {
    let title: String, subtitle: String, detail: String
    let cost: Cost
    let status: String
    let ok: Bool
    @ViewBuilder var icon: () -> Icon
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
                CostLine(cost: cost)
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(status).font(.system(size: 10, weight: .semibold)).foregroundColor(ok ? .green : .orange)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Chamfer(cut: 9).fill(LinearGradient(colors: [Color.white.opacity(ok ? 0.09 : 0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
        .overlay(Chamfer(cut: 9).stroke(ok ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
    }
}

#if os(macOS)
/// Development: renders the tech screens offscreen for review (`--render-tech <dir> [faction]`).
@MainActor
enum TechSheet {
    static func write(to dir: URL, faction: Faction) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var st = GameSettings(); st.playerFaction = faction; st.aiFaction = faction == .machines ? .aliens : .machines; st.seed = 42
        let c = GameController(settings: st, aiPlayers: false)
        let data = c.world.data, p = c.world.players[c.me], accent = Theme.faction(faction)
        let tree = TechTreeView(controller: c)
        func save<V: View>(_ v: V, _ name: String, width: CGFloat) {
            let r = ImageRenderer(content: v.frame(width: width).padding(16).background(Color(red: 0.04, green: 0.05, blue: 0.08)).environment(\.colorScheme, .dark))
            r.scale = 2
            guard let img = r.cgImage else { print("render failed: \(name)"); return }
            PortraitPipeline.writePNG(img, dir.appendingPathComponent(name))
            print("wrote \(dir.appendingPathComponent(name).path)")
        }
        save(VStack(alignment: .leading, spacing: 16) { tree.unitsTab(c.world, p, data, accent) }.foregroundColor(.white), "tech_\(faction.rawValue)_units.png", width: 700)
        save(VStack(alignment: .leading, spacing: 16) { tree.buildingsTab(c.world, p, data, accent) }.foregroundColor(.white), "tech_\(faction.rawValue)_buildings.png", width: 700)
        save(VStack(alignment: .leading, spacing: 16) { tree.buildingsTab(c.world, p, data, accent) }.foregroundColor(.white), "tech_\(faction.rawValue)_buildings_phone.png", width: 360)
    }
}
#endif
