import Foundation

enum Store {
    /// `.atomic` replaces the file via rename, which macOS can refuse when the
    /// existing file carries a `com.apple.provenance` attribute owned by a
    /// previous build of the app. Fall back to an in-place write in that case.
    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            try data.write(to: url)
        }
    }

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
            // An intentional change in probe policy legitimately changes usage
            // coverage; only same-policy regressions are refused.
            if existing.probePolicyVersion != snapshot.probePolicyVersion {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try write(data, to: url)
                return true
            }
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
        try write(data, to: url)
        return true
    }

    static func loadSaved(from url: URL = AppPaths.savedURL) -> SavedStore {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(SavedStore.self, from: data) else {
            return SavedStore()
        }
        return store
    }

    static func saveSaved(
        _ store: SavedStore, to url: URL = AppPaths.savedURL
    ) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(store), to: url)
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
        try write(encoder.encode(store), to: url)
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
        try write(encoder.encode(trimmed), to: url)
    }
}
