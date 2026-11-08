import Foundation

/// Portable bundle of all user-authored data. Built-in resources and the scan
/// snapshot are intentionally excluded: they are reproducible on any machine.
struct CmdBookBackup: Codable {
    var version: Int = 1
    var exportedAt: String = ""
    var examples: UserExamplePatch?
    var dictionary: UserChinesePatch?
    var saved: SavedStore?
    var favorites: FavoriteStore?
    var history: RunHistory?
}

struct ImportReport {
    var examples = 0
    var dictionaryEntries = 0
    var saved = 0
    var favorites = 0
    var history = 0
}

enum BackupError: Error, LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "不支持的备份版本：\(version)"
        }
    }
}

enum Backup {
    static func makeBackup() -> CmdBookBackup {
        var backup = CmdBookBackup()
        backup.exportedAt = ISO8601DateFormatter().string(from: Date())
        backup.examples = ExampleRepo.userPatch()
        backup.dictionary = ChineseNotes.userPatch()
        backup.saved = Store.loadSaved()
        backup.favorites = Store.loadFavorites()
        backup.history = Store.loadHistory()
        return backup
    }

    static func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(makeBackup()).write(to: url, options: [.atomic])
    }

    static func load(from url: URL) throws -> CmdBookBackup {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(CmdBookBackup.self, from: data)
        guard backup.version == 1 else {
            throw BackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    /// Merges a backup into the current user data. Nothing is ever replaced
    /// wholesale: examples/saved/history merge by id, favourites union by name,
    /// dictionary entries override by key and new rules are appended.
    static func restore(
        from url: URL,
        into directory: URL = AppPaths.supportDirectory
    ) throws -> ImportReport {
        let backup = try load(from: url)
        var report = ImportReport()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let examplesURL = directory.appendingPathComponent("examples.json")
        let dictionaryURL = directory.appendingPathComponent("tool-zh.json")
        let savedURL = directory.appendingPathComponent("saved.json")
        let favoritesURL = directory.appendingPathComponent("favorites.json")
        let historyURL = directory.appendingPathComponent("history.json")

        if let incoming = backup.examples {
            var current = ExampleRepo.userPatch(from: examplesURL)
                ?? UserExamplePatch(examples: nil, remove: nil)
            var byID: [String: Example] = [:]
            for example in current.examples ?? [] { byID[example.id] = example }
            for example in incoming.examples ?? [] { byID[example.id] = example }
            current.examples = byID.values.sorted { $0.id < $1.id }
            var removed = Set(current.remove ?? [])
            for id in incoming.remove ?? [] { removed.insert(id) }
            current.remove = removed.sorted()
            try ExampleRepo.saveUserPatch(current, to: examplesURL)
            report.examples = (incoming.examples?.count ?? 0) + (incoming.remove?.count ?? 0)
        }

        if let incoming = backup.dictionary {
            var current = ChineseNotes.userPatch(from: dictionaryURL)
                ?? UserChinesePatch(tools: nil, rules: nil, fallback: nil)
            var tools = current.tools ?? [:]
            for (name, entry) in incoming.tools ?? [:] { tools[name] = entry }
            current.tools = tools
            var fallback = current.fallback ?? [:]
            for (category, entry) in incoming.fallback ?? [:] { fallback[category] = entry }
            current.fallback = fallback
            var rules = current.rules ?? []
            var seen = Set(rules.map { $0.prefix })
            for rule in incoming.rules ?? [] where !seen.contains(rule.prefix) {
                rules.append(rule)
                seen.insert(rule.prefix)
            }
            current.rules = rules
            try ChineseNotes.saveUserPatch(current, to: dictionaryURL)
            report.dictionaryEntries = (incoming.tools?.count ?? 0)
                + (incoming.rules?.count ?? 0)
        }

        if let incoming = backup.saved {
            var current = Store.loadSaved(from: savedURL)
            var byID: [String: SavedExample] = [:]
            for item in current.items { byID[item.id] = item }
            for item in incoming.items { byID[item.id] = item }
            current.items = byID.values.sorted { $0.id < $1.id }
            try Store.saveSaved(current, to: savedURL)
            report.saved = incoming.items.count
        }

        if let incoming = backup.favorites {
            var current = Store.loadFavorites(from: favoritesURL)
            var known = Set(current.tools)
            for name in incoming.tools where !known.contains(name) {
                current.tools.append(name)
                known.insert(name)
            }
            try Store.saveFavorites(current, to: favoritesURL)
            report.favorites = incoming.tools.count
        }

        if let incoming = backup.history {
            var current = Store.loadHistory(from: historyURL)
            var byID: [String: RunRecord] = [:]
            for record in current.items { byID[record.id] = record }
            for record in incoming.items { byID[record.id] = record }
            current.items = Array(
                byID.values.sorted { $0.startedAt > $1.startedAt }
                    .prefix(Store.historyLimit)
            )
            try Store.saveHistory(current, to: historyURL)
            report.history = incoming.items.count
        }

        return report
    }
}
