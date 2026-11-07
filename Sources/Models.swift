import Foundation

enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case user
    case system
    case runtime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .user: return "用户安装"
        case .system: return "系统自带"
        case .runtime: return "运行时附带"
        }
    }
}

struct Tool: Codable, Identifiable, Hashable {
    var name: String
    var path: String
    var allPaths: [String]
    var category: ToolCategory
    var description: String
    var usage: String
    var usageSource: String
    var manExamples: String
    var interactive: Bool
    var titleZh: String = ""
    var summaryZh: String = ""
    var categoryZh: String = ""
    var keywords: [String] = []

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path, allPaths, category, description, usage, usageSource
        case manExamples, interactive, titleZh, summaryZh, categoryZh, keywords
    }
}

/// Tolerates snapshots written before the Chinese fields existed.
extension Tool {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        allPaths = try container.decode([String].self, forKey: .allPaths)
        category = try container.decode(ToolCategory.self, forKey: .category)
        description = try container.decode(String.self, forKey: .description)
        usage = try container.decode(String.self, forKey: .usage)
        usageSource = try container.decode(String.self, forKey: .usageSource)
        manExamples = try container.decode(String.self, forKey: .manExamples)
        interactive = try container.decode(Bool.self, forKey: .interactive)
        titleZh = try container.decodeIfPresent(String.self, forKey: .titleZh) ?? ""
        summaryZh = try container.decodeIfPresent(String.self, forKey: .summaryZh) ?? ""
        categoryZh = try container.decodeIfPresent(String.self, forKey: .categoryZh) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    }
}

struct ScanSummary: Codable {
    var discovered: Int = 0
    var scanned: Int = 0
    var withUsage: Int = 0
    var byCategory: [String: Int] = [:]
    var bySource: [String: Int] = [:]
}

struct Snapshot: Codable {
    var version: Int = 1
    var scannedAt: String = ""
    var loginPath: String = ""
    var summary: ScanSummary = ScanSummary()
    var tools: [Tool] = []
}

struct ExampleField: Codable, Identifiable, Hashable {
    var key: String
    var label: String
    var value: String
    var hint: String?

    var id: String { key }
}

struct Example: Codable, Identifiable, Hashable {
    var id: String
    var tool: String
    var title: String
    var summary: String?
    var argv: [String]
    var fields: [ExampleField]
    var risk: String
    var interactive: Bool?

    var isInteractive: Bool { interactive ?? false }

    var riskLabel: String {
        switch risk {
        case "danger": return "高风险"
        case "write": return "会写入文件"
        default: return "只读"
        }
    }
}

struct ExampleLibrary: Codable {
    var version: Int
    var examples: [Example]
}

/// Optional user overlay for the bundled example library. Lives at
/// ~/Library/Application Support/CmdBook/examples.json; every field can be
/// omitted, so a user file only has to describe the delta.
struct UserExamplePatch: Codable {
    var examples: [Example]?
    var remove: [String]?
}

/// Optional user overlay for the Chinese dictionary.
struct UserChinesePatch: Codable {
    var tools: [String: ChineseEntry]?
    var rules: [ChineseRule]?
    var fallback: [String: ChineseEntry]?
}

struct SavedExample: Codable, Identifiable {
    var id: String
    var exampleID: String
    var values: [String: String]
}

struct SavedStore: Codable {
    var version: Int = 1
    var items: [SavedExample] = []
}

struct SavedItem: Identifiable {
    var id: String { saved.id }
    let saved: SavedExample
    let example: Example
}

struct DiscoveredTool {
    var name: String
    var path: String
    var allPaths: [String]
}
