import Foundation
import MeridianCore

/// One saved match on disk (the most recent unfinished game), plus a tiny summary for the title screen.
enum SaveStore {
    struct Info: Codable {
        var playerFaction: Faction
        var aiFaction: Faction
        var layout: MapLayout
        var difficulty: String
        var gameTime: Double
        var savedAt: Date
        /// Every commander and their teams (absent in saves from before team play).
        var factions: [Faction]? = nil
        var teams: [Int]? = nil
        var line: String {
            let d = GameData.shared
            let time = String(format: "%d:%02d", Int(gameTime) / 60, Int(gameTime) % 60)
            guard let fs = factions, let ts = teams, fs.count == ts.count, fs.count > 2 || ts.count == 2 && ts[0] == ts[1] else {
                return "\(d.faction(playerFaction).name) vs \(d.faction(aiFaction).name) · \(layout.title) · \(time)"
            }
            // "Concord + Brood vs Lattice + Lattice"
            let mine = fs.indices.filter { ts[$0] == ts[0] }.map { d.faction(fs[$0]).name }.joined(separator: " + ")
            let theirs = fs.indices.filter { ts[$0] != ts[0] }.map { d.faction(fs[$0]).name }.joined(separator: " + ")
            return "\(mine) vs \(theirs) · \(layout.title) · \(time)"
        }
    }

    private static let queue = DispatchQueue(label: "meridian.save", qos: .utility)
    private static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static var saveURL: URL { dir.appendingPathComponent("current.json") }
    private static var infoURL: URL { dir.appendingPathComponent("current-info.json") }

    static var info: Info? {
        guard let d = try? Data(contentsOf: infoURL), let i = try? JSONDecoder().decode(Info.self, from: d) else { return nil }
        // Saves from before team play rebuild a different map from their seed; don't offer them.
        return i.factions == nil ? nil : i
    }

    /// Encodes and writes off the main thread (the snapshot itself was taken on the main thread).
    static func write(_ save: MatchSave, info: Info) {
        queue.async {
            guard let d = try? JSONEncoder().encode(save), let i = try? JSONEncoder().encode(info) else { return }
            try? d.write(to: saveURL, options: .atomic)
            try? i.write(to: infoURL, options: .atomic)
        }
    }

    static func read() -> MatchSave? {
        queue.sync {}   // let any pending write finish first
        guard let d = try? Data(contentsOf: saveURL) else { return nil }
        do {
            let s = try JSONDecoder().decode(MatchSave.self, from: d)
            return s.version >= MatchSave.formatVersion ? s : nil
        } catch { print("SAVE read failed: \(error)"); return nil }
    }

    static func delete() {
        queue.async {
            try? FileManager.default.removeItem(at: saveURL)
            try? FileManager.default.removeItem(at: infoURL)
        }
    }
}
