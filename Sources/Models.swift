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
    /// mtime of the executable when its help text was captured. Missing on
    /// snapshots written before incremental scanning existed, or when the
    /// probe did not complete; such entries are always re-probed.
    var probeMtime: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path, allPaths, category, description, usage, usageSource
        case manExamples, interactive, titleZh, summaryZh, categoryZh, keywords
        case probeMtime
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
        probeMtime = try container.decodeIfPresent(Double.self, forKey: .probeMtime)
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
    /// Number of tools whose probe result was reused from the previous scan.
    /// Optional so snapshots written before incremental scanning still decode.
    var reuseCount: Int?
    /// Tools whose binary was deliberately not executed (system shims, GUI /
    /// keychain prompts, app-bundled helpers). Optional for the same reason.
    var skippedBinaryProbes: Int?
    /// Probe policy generation. Bumped when the rules for executing binaries
    /// change, so the quality gate can tell an intentional coverage change
    /// from an accidental degraded scan. Optional for old snapshots.
    var probePolicyVersion: Int?
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

struct FavoriteStore: Codable {
    var version: Int = 1
    var tools: [String] = []
    var examples: [String] = []
}

struct RunRecord: Codable, Identifiable, Hashable {
    var id: String
    var tool: String
    var title: String
    var command: String
    var workingDirectory: String
    var startedAt: String
    var durationMs: Int
    var exitCode: Int32?
    var viaTerminal: Bool
    var outputBytes: Int
}

struct RunHistory: Codable {
    var version: Int = 1
    var items: [RunRecord] = []
}

extension FavoriteStore {
    func contains(tool name: String) -> Bool { tools.contains(name) }

    mutating func toggle(tool name: String) {
        if let index = tools.firstIndex(of: name) {
            tools.remove(at: index)
        } else {
            tools.append(name)
        }
    }
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
