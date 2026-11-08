import Foundation

struct ChineseEntry: Codable {
    var title: String
    var summary: String
    var category: String
    var keywords: [String]
}

struct ChineseRule: Codable {
    var prefix: String
    var category: String
    var keywords: [String]
    var summary: String
}

struct ChineseDictionary: Codable {
    var version: Int = 1
    var tools: [String: ChineseEntry] = [:]
    var rules: [ChineseRule] = []
    var fallback: [String: ChineseEntry] = [:]

    static let empty = ChineseDictionary()
}

struct ToolNotes {
    var title: String
    var summary: String
    var category: String
    var keywords: [String]
    var isExact: Bool
}

/// Chinese metadata for every discovered tool. Exact entries come from
/// Resources/tool-zh.json; name-prefix rules and per-category fallbacks make
/// sure even obscure system binaries have readable Chinese text and searchable
/// Chinese keywords.
enum ChineseNotes {
    static func userPatch(
        from url: URL = AppPaths.userResourceURL(name: "tool-zh", extension: "json")
    ) -> UserChinesePatch? {
        guard let data = try? Data(contentsOf: url),
              let patch = try? JSONDecoder().decode(UserChinesePatch.self, from: data) else {
            return nil
        }
        return patch
    }

    /// Stable longest-prefix-first ordering. Keeping the original index as the
    /// tie-breaker also guarantees user rules (prepended below) win over bundled
    /// rules of the same length.
    static func ordering(_ dictionary: ChineseDictionary) -> ChineseDictionary {
        var result = dictionary
        result.rules = result.rules.enumerated().sorted { left, right in
            if left.element.prefix.count != right.element.prefix.count {
                return left.element.prefix.count > right.element.prefix.count
            }
            return left.offset < right.offset
        }.map { $0.element }
        return result
    }

    /// Pure merge: user exact entries override by name, user rules are tried
    /// before bundled rules, user fallbacks override by category.
    static func merging(
        base: ChineseDictionary, patch: UserChinesePatch?
    ) -> ChineseDictionary {
        guard let patch = patch else { return ordering(base) }
        var merged = base
        for (name, entry) in patch.tools ?? [:] { merged.tools[name] = entry }
        for (category, entry) in patch.fallback ?? [:] { merged.fallback[category] = entry }
        if let rules = patch.rules, !rules.isEmpty {
            merged.rules = rules + base.rules
        }
        return ordering(merged)
    }

    static func saveUserPatch(
        _ patch: UserChinesePatch,
        to url: URL = AppPaths.userResourceURL(name: "tool-zh", extension: "json")
    ) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(patch).write(to: url, options: [.atomic])
    }

    static func load() -> ChineseDictionary {
        let base: ChineseDictionary
        if let url = AppPaths.resourceURL(name: "tool-zh", extension: "json"),
           let data = try? Data(contentsOf: url),
           let dictionary = try? JSONDecoder().decode(ChineseDictionary.self, from: data) {
            base = dictionary
        } else {
            base = .empty
        }
        return merging(base: base, patch: userPatch())
    }

    static func notes(for tool: Tool, dictionary: ChineseDictionary) -> ToolNotes {
        if let exact = dictionary.tools[tool.name] {
            return ToolNotes(
                title: exact.title, summary: exact.summary,
                category: exact.category, keywords: exact.keywords, isExact: true
            )
        }

        for rule in dictionary.rules where tool.name.hasPrefix(rule.prefix) {
            return ToolNotes(
                title: tool.name, summary: rule.summary,
                category: rule.category, keywords: rule.keywords, isExact: false
            )
        }

        let fallback = dictionary.fallback[tool.category.rawValue]
            ?? ChineseEntry(
                title: "", summary: "命令行工具。",
                category: "其他工具", keywords: ["命令行工具"]
            )
        var summary = fallback.summary
        if !tool.description.isEmpty {
            summary += " 英文说明：" + tool.description
        }
        if summary.count > 240 { summary = String(summary.prefix(239)) + "…" }
        return ToolNotes(
            title: tool.name, summary: summary,
            category: fallback.category, keywords: fallback.keywords, isExact: false
        )
    }

    static func apply(_ tool: inout Tool, dictionary: ChineseDictionary) {
        let notes = notes(for: tool, dictionary: dictionary)
        tool.titleZh = notes.title
        tool.summaryZh = notes.summary
        tool.categoryZh = notes.category
        tool.keywords = notes.keywords
    }

    static func exactCount(in dictionary: ChineseDictionary) -> Int {
        dictionary.tools.count
    }
}
