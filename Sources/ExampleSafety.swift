import Foundation

struct RiskFinding {
    let level: String
    let message: String
}

/// Static risk analysis for an example's argv template.
///
/// User-authored examples changed the trust model: the bundled examples are
/// curated, but the in-app editor lets a user write arbitrary argv and declare
/// any `risk` level. Deriving the level from the arguments closes that gap —
/// a "safe" label can never downgrade a detected capability.
enum ExampleSafety {
    private static let codeTools: Set<String> = [
        "python", "python3", "ruby", "perl", "php", "lua", "node", "deno", "bun",
        "swift", "osascript", "js", "qjs", "r", "R", "rubyw"
    ]
    private static let execFlags: Set<String> = [
        "-c", "-e", "--eval", "-E", "/c", "-command", "--command", "-ex"
    ]
    private static let shellTools: Set<String> = [
        "sh", "bash", "zsh", "fish", "env", "eval", "xargs", "osascript", "sudo"
    ]
    private static let outputFlags: Set<String> = [
        "-o", "--output", "-O", ">", ">>", "--in-place", "-delete"
    ]

    static func findings(tool: String, argv: [String]) -> [RiskFinding] {
        let name = (tool as NSString).lastPathComponent.lowercased()
        let lowered = argv.map { $0.lowercased() }
        var result: [RiskFinding] = []

        if shellTools.contains(name) {
            return [RiskFinding(level: "danger", message: "\(tool) 可执行任意命令")]
        }
        if codeTools.contains(name) && lowered.contains(where: { execFlags.contains($0) }) {
            result.append(RiskFinding(
                level: "danger", message: "\(tool) 带 -c/-e 等标志可运行任意代码"
            ))
        }
        if name == "find" && lowered.contains(where: {
            ["-exec", "-execdir", "-ok", "-delete"].contains($0)
        }) {
            result.append(RiskFinding(
                level: "danger", message: "find 的 -exec/-delete 可执行命令或删除文件"
            ))
        }
        if result.isEmpty {
            if ["cp", "mv", "tee", "install", "touch", "mkdir", "rmdir",
                "dd", "truncate", "zip", "unzip", "gzip", "gunzip"].contains(name) {
                result.append(RiskFinding(level: "write", message: "\(tool) 会写入或修改文件"))
            }
            if name == "git", let subcommand = lowered.first,
               ["commit", "push", "reset", "checkout", "merge", "rebase",
                "clean", "rm", "apply", "stash"].contains(subcommand) {
                result.append(RiskFinding(level: "write", message: "git \(subcommand) 会改动仓库"))
            }
            if ["curl", "wget"].contains(name) && lowered.contains(where: {
                ["-o", "-O", "--output", "-d", "--data", "-t", "--upload-file"].contains($0)
            }) {
                result.append(RiskFinding(level: "write", message: "\(tool) 会下载或上传文件"))
            }
            if lowered.contains(where: { outputFlags.contains($0) }) {
                result.append(RiskFinding(level: "write", message: "参数含输出 / 就地修改标志"))
            }
        }
        return result
    }

    /// Never lower the declared level; only raise it when argv says otherwise.
    static func effectiveRisk(
        tool: String, argv: [String], declared: String
    ) -> String {
        let rank = ["safe": 0, "write": 1, "danger": 2]
        var level = declared
        for finding in findings(tool: tool, argv: argv) {
            if rank[finding.level, default: 0] > rank[level, default: 0] {
                level = finding.level
            }
        }
        return level
    }

    static func label(_ level: String) -> String {
        switch level {
        case "danger": return "高风险"
        case "write": return "会写入文件"
        default: return "只读"
        }
    }
}
