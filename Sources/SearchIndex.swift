import Foundation

/// Precomputed, lowercased UTF-8 bytes for one tool.
///
/// `String.contains` on the ~3.35 MB of captured --help text costs ~135 ms per
/// full pass. Foundation's `Data.range(of:)` does byte-level searching and is
/// roughly 100x faster, so all searchable fields are converted once at load time
/// and every keystroke only performs cheap byte comparisons.
struct SearchEntry {
    let tool: Tool
    let name: Data
    let keywords: [Data]
    let zhTitle: Data
    let zhCategory: Data
    let zhSummary: Data
    let path: Data
    let description: Data
    let usage: Data

    init(_ tool: Tool) {
        self.tool = tool
        name = Data(tool.name.lowercased().utf8)
        keywords = tool.keywords.map { Data($0.lowercased().utf8) }
        zhTitle = Data(tool.titleZh.lowercased().utf8)
        zhCategory = Data(tool.categoryZh.lowercased().utf8)
        zhSummary = Data(tool.summaryZh.lowercased().utf8)
        path = Data(tool.path.lowercased().utf8)
        description = Data(tool.description.lowercased().utf8)
        usage = Data(tool.usage.lowercased().utf8)
    }
}

struct SearchOutcome {
    var matches: [Tool]
    var visible: [Tool]
    var scopeExpanded: Bool
}

/// Immutable, reusable search index. Built once when a snapshot loads or a
/// rescan completes; queried for every keystroke without re-lowercasing any text.
final class SearchIndex {
    private let allEntries: [SearchEntry]
    private let userEntries: [SearchEntry]
    private let systemEntries: [SearchEntry]

    init(tools: [Tool]) {
        let entries = tools.map(SearchEntry.init)
        allEntries = entries
        userEntries = entries.filter { $0.tool.category == .user }
        systemEntries = entries.filter { $0.tool.category != .user }
    }

    /// - Parameter favorites: when non-nil, restrict results to these tool
    ///   names and disable scope widening (staying inside the favourites set).
    func results(
        query: String, filter: ToolFilter, limit: Int,
        favorites: Set<String>? = nil
    ) -> SearchOutcome {
        let base: [SearchEntry]
        switch filter {
        case .user: base = userEntries
        case .system: base = systemEntries
        case .all, .favorites: base = allEntries
        }
        let scoped: [SearchEntry]
        if let favorites = favorites {
            scoped = base.filter { favorites.contains($0.tool.name) }
        } else {
            scoped = base
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            let matches = scoped.map { $0.tool }
            return SearchOutcome(
                matches: matches,
                visible: Array(matches.prefix(limit)),
                scopeExpanded: false
            )
        }

        let needle = Data(normalized.utf8)
        var ranked = rankAll(scoped, needle: needle)
        if ranked.isEmpty && favorites == nil {
            let widened = rankAll(allEntries, needle: needle)
            if !widened.isEmpty {
                ranked = widened
                let matches = ranked.map { $0.0.tool }
                return SearchOutcome(
                    matches: matches,
                    visible: Array(matches.prefix(limit)),
                    scopeExpanded: true
                )
            }
        }
        let matches = ranked.map { $0.0.tool }
        return SearchOutcome(
            matches: matches,
            visible: Array(matches.prefix(limit)),
            scopeExpanded: false
        )
    }

    private func rankAll(
        _ entries: [SearchEntry], needle: Data
    ) -> [(SearchEntry, Int)] {
        entries
            .compactMap { entry -> (SearchEntry, Int)? in
                guard let rank = Search.rank(entry, needle: needle) else { return nil }
                return (entry, rank)
            }
            .sorted { left, right in
                left.1 == right.1
                    ? left.0.tool.name < right.0.tool.name
                    : left.1 < right.1
            }
    }
}
