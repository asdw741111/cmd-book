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
    static func load() -> ChineseDictionary {
        guard let url = AppPaths.resourceURL(name: "tool-zh", extension: "json"),
              let data = try? Data(contentsOf: url),
              var dictionary = try? JSONDecoder().decode(ChineseDictionary.self, from: data) else {
            return .empty
        }
        // `notes(for:)` returns on the first matching prefix. Sort longest-first
        // so a specific rule (`gif2webp`) is not shadowed by a generic one (`gif`).
        dictionary.rules.sort { $0.prefix.count > $1.prefix.count }
        return dictionary
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
