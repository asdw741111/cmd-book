import Foundation

enum Store {
    /// Debug scans (`--scan --limit N`) write here so they can never damage the
    /// production index used by the app.
    static var debugSnapshotURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("tools-debug.json")
    }

    static func loadSnapshot(from url: URL = AppPaths.snapshotURL) -> Snapshot? {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Writes atomically. When `protectExisting` is true, a snapshot that is
    /// clearly worse than the last good one is rejected without writing.
    ///
    /// This guards two real failure modes: a `--scan --limit` debug run, and a
    /// scan that hits the 180 s global deadline and fills the tail with empty
    /// usage text. Without the gate either one silently destroys the only good
    /// `tools.json`.
    /// - Returns: `false` when the write was refused by the quality gate.
    @discardableResult
    static func saveSnapshot(
        _ snapshot: Snapshot,
        to url: URL = AppPaths.snapshotURL,
        protectExisting: Bool = true
    ) throws -> Bool {
        AppPaths.prepare()
        if protectExisting, let existing = loadSnapshot(from: url) {
            let oldTools = existing.tools.count
            let oldUsage = existing.summary.withUsage
            let newTools = snapshot.tools.count
            let newUsage = snapshot.summary.withUsage
            let threshold = 0.9
            if newTools < Int(Double(oldTools) * threshold)
                || newUsage < Int(Double(oldUsage) * threshold) {
                return false
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
        return true
    }

    static func loadSaved() -> SavedStore {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: AppPaths.savedURL),
              let store = try? JSONDecoder().decode(SavedStore.self, from: data) else {
            return SavedStore()
        }
        return store
    }

    static func saveSaved(_ store: SavedStore) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: AppPaths.savedURL, options: [.atomic])
    }

    static var favoritesURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("favorites.json")
    }

    static var historyURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("history.json")
    }

    /// Most recent first; older entries beyond the cap are dropped.
    static let historyLimit = 200

    static func loadFavorites(from url: URL = Self.favoritesURL) -> FavoriteStore {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(FavoriteStore.self, from: data) else {
            return FavoriteStore()
        }
        return store
    }

    static func saveFavorites(
        _ store: FavoriteStore, to url: URL = Self.favoritesURL
    ) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: url, options: [.atomic])
    }

    static func loadHistory(from url: URL = Self.historyURL) -> RunHistory {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(RunHistory.self, from: data) else {
            return RunHistory()
        }
        var trimmed = history
        if trimmed.items.count > historyLimit {
            trimmed.items = Array(trimmed.items.prefix(historyLimit))
        }
        return trimmed
    }

    static func saveHistory(
        _ history: RunHistory, to url: URL = Self.historyURL
    ) throws {
        AppPaths.prepare()
        var trimmed = history
        if trimmed.items.count > historyLimit {
            trimmed.items = Array(trimmed.items.prefix(historyLimit))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(trimmed).write(to: url, options: [.atomic])
    }
}
