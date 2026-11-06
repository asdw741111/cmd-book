import Foundation

/// Pure, DOM-free ranking logic so Chinese-language discovery can be unit tested.
/// Lower rank = better match. Chinese keyword hits intentionally outrank plain
/// English name substring hits, so "数据恢复" brings photorec to the top.
///
/// All comparisons operate on precomputed lowercase UTF-8 bytes from
/// `SearchIndex`; no string is lowercased or allocated during a query.
enum Search {
    static func rank(_ entry: SearchEntry, needle: Data) -> Int? {
        if entry.name == needle { return 0 }
        if entry.keywords.contains(where: { $0 == needle }) { return 1 }
        if entry.zhTitle.range(of: needle) != nil
            || entry.zhCategory.range(of: needle) != nil { return 2 }
        if entry.keywords.contains(where: { $0.range(of: needle) != nil }) { return 3 }
        if entry.name.starts(with: needle) { return 4 }
        if entry.name.range(of: needle) != nil { return 5 }
        if entry.zhSummary.range(of: needle) != nil { return 6 }
        if entry.path.range(of: needle) != nil { return 7 }
        if entry.description.range(of: needle) != nil { return 8 }
        if entry.usage.range(of: needle) != nil { return 9 }
        return nil
    }

    /// Convenience for one-shot CLI searches; builds a throwaway index.
    static func sort(_ tools: [Tool], query: String) -> [Tool] {
        SearchIndex(tools: tools)
            .results(query: query, filter: .all, limit: Int.max)
            .matches
    }
}
