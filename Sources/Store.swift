import Foundation

enum Store {
    /// `.atomic` replaces the file via rename, which macOS can refuse when the
    /// existing file carries a `com.apple.provenance` attribute owned by a
    /// previous build of the app. Fall back to an in-place write in that case.
    private static func decode<T: Decodable>(
        _ type: T.Type, from url: URL, label: String, fallback: T
    ) -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLog.store.error(
                "\(label, privacy: .public) 解码失败: \(error.localizedDescription, privacy: .public)"
            )
            return fallback
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLog.store.warning(
                "原子写被拒绝，回退原位写入 \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
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
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            AppLog.store.error(
                "快照 \(url.lastPathComponent, privacy: .public) 解码失败: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
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
        return decode(
            SavedStore.self, from: url, label: "保存的参数组合", fallback: SavedStore()
        )
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
        return decode(
            FavoriteStore.self, from: url, label: "收藏", fallback: FavoriteStore()
        )
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
        var trimmed = decode(
            RunHistory.self, from: url, label: "运行历史", fallback: RunHistory()
        )
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
