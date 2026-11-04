import Foundation
import MeridianCore

/// Recorded matches on disk (the most recent few), newest first, plus a summary line for the list.
enum ReplayStore {
    struct Info: Codable, Identifiable {
        var id: String          // file name
        var line: String
        var recordedAt: Date
        var won: Bool?
        var faction: Faction
    }

    static let keep = 12
    private static let queue = DispatchQueue(label: "meridian.replays", qos: .utility)
    private static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Replays", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Writes a finished recording and trims the folder to the newest `keep`.
    static func add(_ r: Replay) {
        queue.async {
            let name = ISO8601DateFormatter().string(from: r.recordedAt).replacingOccurrences(of: ":", with: "-") + ".json"
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for old in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(keep) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    static func list() -> [Info] {
        queue.sync {}
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let data = GameData.shared
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.compactMap { url in
            guard let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(Replay.self, from: d), r.version == Replay.formatVersion else { return nil }
            let won = r.winner.map { $0 >= 0 && r.teams[$0] == r.teams[r.human] }
            return Info(id: url.lastPathComponent, line: r.summary(data), recordedAt: r.recordedAt, won: won, faction: r.factions[r.human])
        }
    }

    static func read(_ id: String) -> Replay? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(id)) else { return nil }
        return try? JSONDecoder().decode(Replay.self, from: d)
    }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(id)) }
}
