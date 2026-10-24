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
        var line: String {
            let d = GameData.shared
            return "\(d.faction(playerFaction).name) vs \(d.faction(aiFaction).name) · \(layout.title) · \(String(format: "%d:%02d", Int(gameTime) / 60, Int(gameTime) % 60))"
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
        guard let d = try? Data(contentsOf: infoURL) else { return nil }
        return try? JSONDecoder().decode(Info.self, from: d)
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
        do { return try JSONDecoder().decode(MatchSave.self, from: d) } catch { print("SAVE read failed: \(error)"); return nil }
    }

    static func delete() {
        queue.async {
            try? FileManager.default.removeItem(at: saveURL)
            try? FileManager.default.removeItem(at: infoURL)
        }
    }
}
