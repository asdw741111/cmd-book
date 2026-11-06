import Foundation

enum Scanner {
    static let maxConcurrency = 12
    static let probeTimeout: TimeInterval = 1.5
    static let globalDeadline: TimeInterval = 180

    static func discover(pathEnv: String) -> (dirs: [String], tools: [DiscoveredTool]) {
        var seenDirectories: Set<String> = []
        var dirs: [String] = []
        for raw in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
            let directory = (String(raw) as NSString).standardizingPath
            if seenDirectories.contains(directory) { continue }
            seenDirectories.insert(directory)
            dirs.append(directory)
        }

        let fileManager = FileManager.default
        var byName: [String: DiscoveredTool] = [:]

        for directory in dirs {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in entries.sorted() {
                let candidate = (directory as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      fileManager.isExecutableFile(atPath: candidate) else { continue }

                let resolved = (candidate as NSString).resolvingSymlinksInPath
                if var existing = byName[name] {
                    if !existing.allPaths.contains(resolved) {
                        existing.allPaths.append(resolved)
                        byName[name] = existing
                    }
                } else {
                    byName[name] = DiscoveredTool(
                        name: name, path: resolved, allPaths: [resolved]
                    )
                }
            }
        }

        let tools = byName.keys.sorted().compactMap { byName[$0] }
        return (dirs, tools)
    }

    static func scan(
        pathEnv: String? = nil,
        limit: Int? = nil,
        exampleTools: Set<String> = [],
        progress: ((Int, Int) -> Void)? = nil
    ) -> Snapshot {
        let loginPath = pathEnv ?? ProcessSupport.resolveLoginPath()
        let (_, discovered) = discover(pathEnv: loginPath)
        let targets: [DiscoveredTool] = limit.map { Array(discovered.prefix($0)) } ?? discovered
        let dictionary = ChineseNotes.load()

        let started = Date()
        let results = LockedBox<[Tool?]>(Array(repeating: nil, count: targets.count))
        let counter = LockedBox<Int>(0)
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: maxConcurrency)

        for (index, raw) in targets.enumerated() {
            if Date().timeIntervalSince(started) > globalDeadline {
                results.withValue { $0[index] = makeTool(
                    raw, usage: "", source: "none", manExamples: "",
                    description: "", dictionary: dictionary
                ) }
                continue
            }
            gate.wait()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    gate.signal()
                    group.leave()
                }
                let tool = probe(
                    raw, wantsMan: exampleTools.contains(raw.name), dictionary: dictionary
                )
                results.withValue { $0[index] = tool }
                let done = counter.withValue { value -> Int in
                    value += 1
                    return value
                }
                progress?(done, targets.count)
            }
        }
        group.wait()

        let tools = results.withValue { $0.compactMap { $0 } }
        var summary = ScanSummary()
        summary.discovered = discovered.count
        summary.scanned = targets.count
        summary.withUsage = tools.filter { !$0.usage.isEmpty }.count
        for tool in tools {
            summary.byCategory[tool.category.rawValue, default: 0] += 1
            summary.bySource[tool.usageSource, default: 0] += 1
        }

        let formatter = ISO8601DateFormatter()
        return Snapshot(
            version: 1,
            scannedAt: formatter.string(from: Date()),
            loginPath: loginPath,
            summary: summary,
            tools: tools
        )
    }

    private static func probe(
        _ raw: DiscoveredTool, wantsMan: Bool, dictionary: ChineseDictionary
    ) -> Tool {
        var usage = ""
        var source = "none"
        var manExamples = ""

        // Never execute binaries shipped inside other applications' bundles:
        // they may write caches or configuration even for --help.
        let category = Classifier.category(for: raw.path)
        let skipHelp = Classifier.helpSkipNames.contains(raw.name) || category == .runtime
        if !skipHelp {
            let result = ProcessSupport.run(
                executable: raw.path,
                arguments: ["--help"],
                environment: ProcessSupport.probeEnvironment,
                timeout: probeTimeout
            )
            let combined = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let normalized = TextCleanup.normalize(combined)
            if TextCleanup.looksLikeUsage(normalized) && !Self.looksLikeProbeError(normalized) {
                usage = normalized
                source = "help"
            }
        }

        if source == "none" || wantsMan {
            let man = ProcessSupport.run(
                executable: "/usr/bin/man",
                arguments: ["-P", "cat", raw.name],
                environment: ProcessSupport.probeEnvironment,
                timeout: probeTimeout + 0.5
            )
            let body = TextCleanup.cleaned(
                [man.stdout, man.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            )
            manExamples = TextCleanup.manExamples(from: body)
            if source == "none" {
                let normalized = TextCleanup.normalize(body)
                if TextCleanup.looksLikeUsage(normalized) && !Self.looksLikeProbeError(normalized) {
                    usage = normalized
                    source = "man"
                }
            }
        }

        var description = TextCleanup.description(from: usage)
        if description.isEmpty && usage.isEmpty {
            let whatis = ProcessSupport.run(
                executable: "/usr/bin/whatis",
                arguments: [raw.name],
                environment: ProcessSupport.probeEnvironment,
                timeout: 1.0,
                maxBytes: 8192
            )
            description = TextCleanup.whatisDescription(
                from: [whatis.stdout, whatis.stderr].filter { !$0.isEmpty }.joined(separator: "\n"),
                tool: raw.name
            )
        }
        return makeTool(
            raw, usage: usage, source: source,
            manExamples: manExamples, description: description, dictionary: dictionary
        )
    }

    /// Short error messages ("illegal option -- -h", "No manual entry for X")
    /// are not usage text. Long help bodies may legitimately mention these
    /// phrases, so gate on length too.
    private static func looksLikeProbeError(_ text: String) -> Bool {
        guard text.count < 500 else { return false }
        let lower = text.lowercased()
        let markers = [
            "illegal option", "unknown option", "unrecognized option",
            "invalid option", "unknown argument", "unknown architecture",
            "command not found", "no such file or directory",
            "no manual entry", "no entry for", "could not refer to file",
            "未能打开文件", "无此文件或目录", "未能完成该操作"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func makeTool(
        _ raw: DiscoveredTool, usage: String, source: String,
        manExamples: String, description: String, dictionary: ChineseDictionary
    ) -> Tool {
        var tool = Tool(
            name: raw.name,
            path: raw.path,
            allPaths: raw.allPaths,
            category: Classifier.category(for: raw.path),
            description: description,
            usage: usage,
            usageSource: source,
            manExamples: manExamples,
            interactive: Classifier.terminalOnlyNames.contains(raw.name)
        )
        ChineseNotes.apply(&tool, dictionary: dictionary)
        return tool
    }
}
