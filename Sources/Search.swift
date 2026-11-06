import Foundation

/// Pure, DOM-free search ranking so Chinese-language discovery can be unit tested.
/// Lower rank = better match. Chinese keyword hits intentionally outrank plain
/// English name substring hits, so "数据恢复" brings photorec to the top.
enum Search {
    static func rank(_ tool: Tool, query: String) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return 0 }

        let name = tool.name.lowercased()
        let keywords = tool.keywords.map { $0.lowercased() }
        let zhTitle = tool.titleZh.lowercased()
        let zhCategory = tool.categoryZh.lowercased()
        let zhSummary = tool.summaryZh.lowercased()
        let keywordsJoined = keywords.joined(separator: " ")

        if name == needle { return 0 }
        if keywords.contains(where: { $0 == needle }) { return 1 }
        if zhTitle.contains(needle) || zhCategory.contains(needle) { return 2 }
        if keywords.contains(where: { $0.contains(needle) }) { return 3 }
        if keywordsJoined.contains(needle) { return 4 }
        if name.hasPrefix(needle) { return 5 }
        if name.contains(needle) { return 6 }
        if zhSummary.contains(needle) { return 7 }
        if tool.path.lowercased().contains(needle) { return 8 }
        if tool.description.lowercased().contains(needle) { return 9 }
        if tool.usage.lowercased().contains(needle) { return 10 }
        return nil
    }

    static func sort(_ tools: [Tool], query: String) -> [Tool] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return tools }
        return tools
            .compactMap { tool -> (Tool, Int)? in
                guard let rank = rank(tool, query: needle) else { return nil }
                return (tool, rank)
            }
            .sorted { left, right in
                left.1 == right.1 ? left.0.name < right.0.name : left.1 < right.1
            }
            .map { $0.0 }
    }
}
