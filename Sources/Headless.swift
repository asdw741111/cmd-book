import Foundation

enum Headless {
    static func scan(limit: Int?, forceFull: Bool = false) {
        let library = ExampleRepo.load()
        let exampleTools = ExampleRepo.toolNames(in: library)
        print("解析登录 PATH 并开始扫描…\(forceFull ? "（强制全量）" : "")")
        let previous: Snapshot? = (limit == nil && !forceFull)
            ? Store.loadSnapshot() : nil
        let snapshot = Scanner.scan(
            limit: limit, exampleTools: exampleTools,
            previous: previous, forceFull: forceFull
        ) { done, total in
            if done % 100 == 0 || done == total {
                fputs("  已扫描 \(done)/\(total)\n", stderr)
            }
        }
        // A limited scan is a debug aid: never let it overwrite the app's index.
        let destination = limit == nil ? AppPaths.snapshotURL : Store.debugSnapshotURL
        var saved = false
        var writeError: String?
        do {
            saved = try Store.saveSnapshot(
                snapshot, to: destination, protectExisting: limit == nil
            )
        } catch {
            let underlying = error as NSError
            writeError = "\(error.localizedDescription)"
                + " [domain=\(underlying.domain) code=\(underlying.code)"
                + " underlying=\(underlying.userInfo[NSUnderlyingErrorKey] ?? "none")]"
        }

        print("=== 扫描结果 ===")
        print("PATH 条目      : \(snapshot.loginPath.split(separator: ":").count)")
        print("发现工具       : \(snapshot.summary.discovered)")
        print("实际扫描       : \(snapshot.summary.scanned)")
        print("有用法文本     : \(snapshot.summary.withUsage)")
        print("增量复用       : \(snapshot.reuseCount ?? 0) / \(snapshot.summary.scanned) 个工具（未变化的可执行文件跳过探测）")
        print("未执行二进制   : \(snapshot.skippedBinaryProbes ?? 0) 个（系统 shim / GUI / 钥匙串类，仅查 man 与 whatis）")
        print("分类           : \(snapshot.summary.byCategory)")
        print("用法来源       : \(snapshot.summary.bySource)")
        for name in ["ffmpeg", "ffprobe", "photorec", "testdisk", "rg", "jq", "yt-dlp"] {
            if let tool = snapshot.tools.first(where: { $0.name == name }) {
                let preview = tool.usage.isEmpty ? "无" : "\(tool.usage.count) 字符"
                print("  \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(tool.category.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) 用法=\(preview) man示例=\(!tool.manExamples.isEmpty) 交互=\(tool.interactive) 路径=\(tool.path)")
            } else {
                print("  \(name): 未发现")
            }
        }
        print("中文说明       : \(snapshot.tools.filter { !$0.summaryZh.isEmpty }.count) / \(snapshot.tools.count) 个工具")
        print("中文精确词条   : \(snapshot.tools.filter { !$0.titleZh.isEmpty && $0.titleZh != $0.name }.count) 个工具")
        print("man EXAMPLES   : \(snapshot.tools.filter { !$0.manExamples.isEmpty }.count) 个工具")
        if let limit = limit {
            print("调试快照       : \(destination.path)（限量 \(limit) 个工具，不影响生产索引）")
        } else if let writeError = writeError {
            print("写入失败       : \(writeError)（已保留原有索引）")
        } else if !saved {
            print("写入被拒绝     : 本次结果明显差于上一份（工具数或用法文本数下降超过 10%），已保留原有索引")
        } else {
            print("快照文件       : \(destination.path)")
        }
        if let writeError = writeError { fputs("快照写入失败: \(writeError)\n", stderr) }
    }

    /// Performance regression test for the interactive search hot path.
    /// "输入" simulates one SwiftUI body evaluation (the sidebar reads the match
    /// list several times). "点击" simulates selecting a row. Budget is one 60 fps
    /// frame (16.7 ms); selection has a tighter 5 ms budget because it should not
    /// recompute the search at all.
    static func bench() -> Int32 {
        let model = AppModel()
        model.load()
        guard let snapshot = model.snapshot else {
            print("没有快照，请先执行 --scan")
            return 1
        }

        let indexStart = CFAbsoluteTimeGetCurrent()
        let index = SearchIndex(tools: snapshot.tools)
        let indexMs = (CFAbsoluteTimeGetCurrent() - indexStart) * 1000

        let queries = ["数据恢复", "ff", "转码", "压缩", "zzzz不存在"]
        for _ in 0..<3 { _ = index.results(query: "数据恢复", filter: .user, limit: 300) }
        let queryStart = CFAbsoluteTimeGetCurrent()
        let queryRounds = 30
        for _ in 0..<queryRounds {
            for query in queries {
                _ = index.results(query: query, filter: .user, limit: 300)
            }
        }
        let queryMs = (CFAbsoluteTimeGetCurrent() - queryStart)
            / Double(queryRounds * queries.count) * 1000

        func oneInput(_ query: String) {
            model.query = query
            for _ in 0..<6 { _ = model.matches.count }
            _ = model.visibleMatches.count
            _ = model.scopeExpanded
            _ = model.exactChineseCount
        }
        for query in queries { oneInput(query) }
        let inputStart = CFAbsoluteTimeGetCurrent()
        let inputRounds = 10
        for _ in 0..<inputRounds {
            for query in queries { oneInput(query) }
        }
        let inputMs = (CFAbsoluteTimeGetCurrent() - inputStart)
            / Double(inputRounds * queries.count) * 1000

        let names = ["photorec", "ffmpeg", "rg", "jq", "yt-dlp"]
        func oneSelection(_ name: String) {
            model.selectedName = name
            for _ in 0..<6 { _ = model.matches.count }
            _ = model.selectedTool?.name
            _ = model.pendingCommandText
            _ = model.examplesForSelectedTool.count
        }
        for name in names { oneSelection(name) }
        let selectStart = CFAbsoluteTimeGetCurrent()
        let selectRounds = 20
        for _ in 0..<selectRounds {
            for name in names { oneSelection(name) }
        }
        let selectMs = (CFAbsoluteTimeGetCurrent() - selectStart)
            / Double(selectRounds * names.count) * 1000

        func line(_ label: String, _ ms: Double, _ budget: Double) -> Bool {
            let passed = ms < budget
            let padded = label.padding(toLength: 20, withPad: " ", startingAt: 0)
            print(padded + String(
                format: "%8.2f ms  (预算 %5.2f ms)  %@",
                ms, budget, passed ? "PASS" : "FAIL"
            ))
            return passed
        }

        print("tools=\(snapshot.tools.count)")
        var passed = true
        passed = line("索引构建（仅一次）", indexMs, 250) && passed
        passed = line("单次索引查询", queryMs, 16.7) && passed
        passed = line("输入 + 界面刷新", inputMs, 16.7) && passed
        passed = line("点击选择结果", selectMs, 5.0) && passed
        print(passed ? "性能回归：全部通过" : "性能回归：未通过")
        return passed ? 0 : 1
    }

    /// Lists the tools in the "已收藏" scope, mirroring the GUI filter.
    static func favorites() -> Int32 {
        guard let snapshot = Store.loadSnapshot() else {
            print("没有快照，请先执行 --scan")
            return 1
        }
        let stored = Store.loadFavorites()
        let outcome = SearchIndex(tools: snapshot.tools).results(
            query: "", filter: .favorites, limit: Int.max,
            favorites: Set(stored.tools)
        )
        print("已收藏 \(outcome.matches.count) 个工具：")
        for tool in outcome.matches {
            let title = tool.titleZh.isEmpty ? "" : " — \(tool.titleZh)"
            print("  \(tool.name)\(title)")
        }
        return 0
    }

    static func exportBackup(to path: String) -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            try Backup.export(to: url)
            print("已导出用户数据：\(url.path)")
            return 0
        } catch {
            fputs("导出失败：\(error)\n", stderr)
            return 1
        }
    }

    static func importBackup(from path: String) -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            let report = try Backup.restore(from: url)
            print("导入完成：示例 \(report.examples) 条、中文词条/规则 \(report.dictionaryEntries) 条、"
                  + "参数组合 \(report.saved) 个、收藏 \(report.favorites) 个、历史 \(report.history) 条")
            return 0
        } catch {
            fputs("导入失败：\(error)\n", stderr)
            return 1
        }
    }

    /// Prints the effective resource set so users can verify their overlays
    /// without launching the GUI.
    static func resources() {
        let library = ExampleRepo.load()
        let examplePatch = ExampleRepo.userPatch()
        let dictionary = ChineseNotes.load()
        let chinesePatch = ChineseNotes.userPatch()
        let favorites = Store.loadFavorites()
        let history = Store.loadHistory()

        print("=== 生效资源 ===")
        print("已收藏工具     : \(favorites.tools.count) 个\(favorites.tools.isEmpty ? "" : "（" + favorites.tools.joined(separator: "、") + "）")")
        print("运行历史       : \(history.items.count) 条（上限 \(Store.historyLimit)）")
        print("示例总数       : \(library.examples.count)（覆盖 \(Set(library.examples.map { $0.tool }).count) 个工具）")
        if let patch = examplePatch {
            print("用户示例补丁   : 新增/覆盖 \(patch.examples?.count ?? 0) 条，禁用 \(patch.remove?.count ?? 0) 条")
        } else {
            print("用户示例补丁   : 未启用")
        }
        print("中文精确词条   : \(dictionary.tools.count)")
        print("中文规则       : \(dictionary.rules.count)（按最长前缀优先）")
        if let patch = chinesePatch {
            print("用户词典补丁   : 词条 \(patch.tools?.count ?? 0) 条，规则 \(patch.rules?.count ?? 0) 条，兜底 \(patch.fallback?.count ?? 0) 条")
        } else {
            print("用户词典补丁   : 未启用")
        }
        print("用户资源目录   : \(AppPaths.supportDirectory.path)")
        print("增量文件       : examples.json / tool-zh.json（与 bundle 同名，按字段合并）")
    }

    /// Query the real snapshot from the command line, using the same dictionary
    /// and ranking as the GUI. Returns 1 when nothing matched.
    static func search(query: String) -> Int32 {
        guard var snapshot = Store.loadSnapshot() else {
            print("没有快照，请先执行 --scan")
            return 1
        }
        let dictionary = ChineseNotes.load()
        snapshot.tools = snapshot.tools.map { tool in
            var updated = tool
            ChineseNotes.apply(&updated, dictionary: dictionary)
            return updated
        }
        let pool = snapshot.tools.filter { $0.category == .user }
        var hits = Search.sort(pool, query: query)
        if hits.isEmpty {
            hits = Search.sort(snapshot.tools, query: query)
            if !hits.isEmpty { print("（当前筛选无结果，已扩大到全部工具）") }
        }
        print("搜索「\(query)」，命中 \(hits.count) 个：")
        for tool in hits.prefix(10) {
            let title = tool.titleZh.isEmpty ? tool.name : tool.titleZh
            print("  \(tool.name) — \(title) [\(tool.categoryZh)]")
        }
        return hits.isEmpty ? 1 : 0
    }

    /// End-to-end check of the streaming whitelist runner (the GUI execution path).
    static func runProbe() -> Int32 {
        let tool = Tool(
            name: "echo", path: "/bin/echo", allPaths: ["/bin/echo"],
            category: .system, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        let example = Example(
            id: "probe-echo", tool: "echo", title: "流式执行验证", summary: nil,
            argv: ["cmdbook-stream-ok"], fields: [], risk: "safe", interactive: nil
        )
        let request = RunRequest(
            tool: tool, example: example, values: [:],
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            loginPath: "/usr/bin:/bin:/usr/sbin:/sbin"
        )

        let lock = NSLock()
        var output = ""
        var status: Int32?
        var wasKilled = false
        let finished = DispatchSemaphore(value: 0)
        let runner = RunningProcess()
        runner.callbackQueue = DispatchQueue(label: "cmdbook.verify.callback")
        runner.onOutput = { text in
            lock.lock(); output += text; lock.unlock()
        }
        runner.onFinish = { code, killed in
            lock.lock(); status = code; wasKilled = killed; lock.unlock()
            finished.signal()
        }

        do {
            try runner.start(request, timeout: 10)
        } catch {
            print("FAIL  流式执行器启动: \(error)")
            return 1
        }

        let waited = withExtendedLifetime(runner) {
            finished.wait(timeout: .now() + 12)
        }
        if waited == .timedOut {
            print("FAIL  流式执行器超时（未收到完成回调）")
            return 1
        }

        lock.lock()
        let captured = output
        let code = status
        let killed = wasKilled
        lock.unlock()

        let passed = captured.contains("cmdbook-stream-ok") && code == 0 && !killed
        if passed {
            print("PASS  流式执行器（输出=\(captured.trimmingCharacters(in: .whitespacesAndNewlines))，退出码=0）")
        } else {
            print("FAIL  流式执行器 output=\(captured) status=\(String(describing: code)) killed=\(killed)")
        }
        return passed ? 0 : 1
    }

    static func verify() -> Int32 {
        var failures: [String] = []
        let library = ExampleRepo.load()

        check(library.examples.count >= 30, "示例库载入（\(library.examples.count) 条）", &failures)
        check(library.examples.contains { $0.tool == "ffmpeg" }, "ffmpeg 示例存在", &failures)
        check(library.examples.contains { $0.tool == "photorec" }, "photorec 示例存在", &failures)

        if let example = library.examples.first(where: { $0.id == "ffmpeg-to-mp4" }) {
            let argv = try? Runner.expandedArguments(
                example, values: ["input": "a.mov", "output": "b.mp4"]
            )
            check(argv?.contains("a.mov") == true && argv?.contains("b.mp4") == true,
                  "占位符在 argv 元素内展开", &failures)
            check(argv?.contains("libx264") == true, "静态参数原样保留", &failures)
        } else {
            check(false, "ffmpeg-to-mp4 存在", &failures)
        }

        let echoTool = Tool(
            name: "echo", path: "/bin/echo", allPaths: ["/bin/echo"],
            category: .system, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        let dangerousTool = Tool(
            name: "rm", path: "/bin/rm", allPaths: ["/bin/rm"],
            category: .system, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        let interactiveTool = Tool(
            name: "photorec", path: "/opt/homebrew/bin/photorec", allPaths: [],
            category: .user, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: true
        )
        let echoExample = Example(
            id: "verify-echo", tool: "echo", title: "验证输出", summary: nil,
            argv: ["cmdbook-verify-ok"], fields: [], risk: "safe", interactive: nil
        )

        do {
            try Runner.validate(tool: dangerousTool, example: echoExample)
            check(false, "危险工具被拒绝", &failures)
        } catch {
            check(true, "危险工具被拒绝", &failures)
        }
        do {
            try Runner.validate(tool: interactiveTool, example: echoExample)
            check(false, "交互式工具被拒绝", &failures)
        } catch {
            check(true, "交互式工具被拒绝", &failures)
        }
        do {
            try Runner.validate(tool: echoTool, example: echoExample)
            check(true, "普通工具通过白名单校验", &failures)
        } catch {
            check(false, "普通工具通过白名单校验: \(error)", &failures)
        }

        let argv = (try? Runner.expandedArguments(echoExample, values: [:])) ?? []
        let executed = ProcessSupport.run(
            executable: "/bin/echo",
            arguments: argv,
            environment: ProcessSupport.probeEnvironment,
            timeout: 5
        )
        check(executed.stdout.contains("cmdbook-verify-ok"), "进程执行与输出捕获", &failures)
        check(executed.exitCode == 0, "退出码为 0", &failures)

        let marker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("cmdbook-probe-marker")
        try? FileManager.default.removeItem(at: marker)
        _ = ProcessSupport.run(
            executable: "/usr/bin/touch",
            arguments: ["cmdbook-probe-marker"],
            environment: ProcessSupport.probeEnvironment,
            timeout: 5
        )
        check(!FileManager.default.fileExists(atPath: marker.path),
              "探测子进程工作目录隔离（不污染工作区）", &failures)
        try? FileManager.default.removeItem(at: marker)

        check(TextCleanup.stripOverstrike("N\u{08}NA\u{08}AM\u{08}ME\u{08}E") == "NAME",
              "man 重字符清理", &failures)
        check(TextCleanup.whatisDescription(
                from: "photorec(8) - Recover lost files from harddisk", tool: "photorec"
              ) == "Recover lost files from harddisk",
              "whatis 摘要提取", &failures)
        check(!Classifier.helpSkipNames.contains("photorec")
                && Classifier.terminalOnlyNames.contains("photorec"),
              "photorec 可探测帮助但禁止内嵌执行", &failures)
        let manSample = """
        NAME
          demo - a demo tool
        EXAMPLES
          demo -v file.txt
          demo --json out.json
        SEE ALSO
          other
        """
        let extracted = TextCleanup.manExamples(from: manSample)
        check(extracted.contains("demo -v") && !extracted.contains("SEE ALSO"),
              "man EXAMPLES 段提取", &failures)

        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmdbook-verify-\(UUID().uuidString)")
        let binA = root.appendingPathComponent("a")
        let binB = root.appendingPathComponent("b")
        do {
            try fileManager.createDirectory(at: binA, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: binB, withIntermediateDirectories: true)
            for directory in [binA, binB] {
                let file = directory.appendingPathComponent("same")
                try "#!/bin/sh\necho ok\n".write(to: file, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            try "not executable".write(
                to: binA.appendingPathComponent("plain.txt"), atomically: true, encoding: .utf8
            )
            let (dirs, tools) = Scanner.discover(pathEnv: "\(binA.path):\(binB.path):\(binA.path)")
            check(dirs.count == 2, "PATH 目录去重", &failures)
            check(tools.count == 1 && tools.first?.name == "same", "basename 去重并跳过非可执行文件", &failures)
            check(tools.first?.allPaths.count == 2, "allPaths 保留所有命中", &failures)
        } catch {
            check(false, "发现逻辑测试准备: \(error)", &failures)
        }
        try? fileManager.removeItem(at: root)

        let dictionary = ChineseNotes.load()
        check(dictionary.tools.count >= 100,
              "中文词典载入（\(dictionary.tools.count) 条精确词条）", &failures)

        var zhTool = interactiveTool
        ChineseNotes.apply(&zhTool, dictionary: dictionary)
        check(zhTool.keywords.contains("数据恢复"),
              "photorec 含「数据恢复」中文关键词", &failures)
        check(!zhTool.summaryZh.isEmpty && !zhTool.categoryZh.isEmpty,
              "中文说明与中文分类非空", &failures)
        check(Search.sort([echoTool, dangerousTool, zhTool], query: "数据恢复").first?.name == "photorec",
              "搜索「数据恢复」命中 photorec", &failures)
        check(Search.sort([echoTool, dangerousTool, zhTool], query: "文件恢复").first?.name == "photorec",
              "搜索「文件恢复」命中 photorec", &failures)
        var ffmpegTool = Tool(
            name: "ffmpeg", path: "/opt/homebrew/bin/ffmpeg", allPaths: [],
            category: .user, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        ChineseNotes.apply(&ffmpegTool, dictionary: dictionary)
        check(Search.sort([echoTool, ffmpegTool, zhTool], query: "转码").first?.name == "ffmpeg",
              "搜索「转码」命中 ffmpeg", &failures)
        check(Search.sort([echoTool, ffmpegTool, zhTool], query: "数据恢复").first?.name == "photorec",
              "中文搜索不误命中无关工具", &failures)

        var obscureTool = Tool(
            name: "zz-obscure-bin", path: "/usr/bin/zz-obscure-bin", allPaths: [],
            category: .system, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        ChineseNotes.apply(&obscureTool, dictionary: dictionary)
        check(!obscureTool.summaryZh.isEmpty && !obscureTool.categoryZh.isEmpty,
              "无词条工具获得中文兜底说明", &failures)

        // Longest-prefix rule ordering: `gif2webp` must not be shadowed by `gif`.
        var gifTool = Tool(
            name: "gif2webp", path: "/opt/homebrew/bin/gif2webp", allPaths: [],
            category: .user, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        ChineseNotes.apply(&gifTool, dictionary: dictionary)
        check(gifTool.keywords.contains("GIF 转 WebP"),
              "最长前缀命中：gif2webp 未被 gif 规则遮蔽", &failures)

        // `risk` must drive real execution policy, not just the label.
        let writeExample = Example(
            id: "w", tool: "ffmpeg", title: "", summary: nil,
            argv: [], fields: [], risk: "write", interactive: nil
        )
        let dangerExample = Example(
            id: "d", tool: "photorec", title: "", summary: nil,
            argv: [], fields: [], risk: "danger", interactive: true
        )
        let dangerPlain = Example(
            id: "dp", tool: "echo", title: "", summary: nil,
            argv: [], fields: [], risk: "danger", interactive: nil
        )
        check(Runner.policy(for: echoTool, example: echoExample) == .inApp,
              "safe 示例在应用内执行", &failures)
        check(Runner.policy(for: ffmpegTool, example: writeExample) == .confirmWrite,
              "write 示例要求写入确认", &failures)
        check(Runner.policy(for: interactiveTool, example: dangerExample) == .terminalOnly,
              "danger 示例转交 Terminal", &failures)
        check(Runner.policy(for: echoTool, example: dangerPlain) == .terminalOnly,
              "非交互 danger 同样转交 Terminal", &failures)

        // Terminal hand-off now validates and produces a self-cleaning script
        // that runs in the user-selected working directory.
        do {
            try Runner.validateSafety(tool: dangerousTool)
            check(false, "Terminal 路径拒绝危险工具", &failures)
        } catch {
            check(true, "Terminal 路径拒绝危险工具", &failures)
        }
        do {
            try Runner.validateSafety(tool: echoTool)
            check(true, "Terminal 路径放行普通工具", &failures)
        } catch {
            check(false, "Terminal 路径放行普通工具: \(error)", &failures)
        }
        let terminalScript = TerminalBridge.script(
            argv: ["/bin/echo", "ok"], loginPath: "/usr/bin:/bin",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        check(terminalScript.contains("cd '/tmp'"),
              "Terminal 脚本注入工作目录", &failures)
        check(terminalScript.contains("rm -f -- \"$0\""),
              "Terminal 脚本自删除", &failures)

        // A degraded scan must never overwrite the last known good snapshot.
        let guardURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmdbook-guard-\(UUID().uuidString).json")
        var goodSummary = ScanSummary()
        goodSummary.withUsage = 90
        var good = Snapshot(tools: Array(repeating: echoTool, count: 100))
        good.summary = goodSummary
        var degradedSummary = ScanSummary()
        degradedSummary.withUsage = 10
        var degraded = Snapshot(tools: Array(repeating: echoTool, count: 10))
        degraded.summary = degradedSummary
        do {
            let first = try Store.saveSnapshot(good, to: guardURL)
            let second = try Store.saveSnapshot(degraded, to: guardURL)
            let after = Store.loadSnapshot(from: guardURL)
            check(first && !second && after?.summary.withUsage == 90,
                  "退化扫描被拒绝覆盖 last-good 快照", &failures)
        } catch {
            check(false, "快照质量闸门: \(error)", &failures)
        }
        try? fileManager.removeItem(at: guardURL)
        check(Store.debugSnapshotURL.lastPathComponent != AppPaths.snapshotURL.lastPathComponent,
              "--limit 调试快照与生产快照路径隔离", &failures)

        // User resource overlays (pure merge, no filesystem writes).
        let baseExample = Example(
            id: "base", tool: "echo", title: "内置", summary: nil,
            argv: ["base"], fields: [], risk: "safe", interactive: nil
        )
        let overrideExample = Example(
            id: "base", tool: "echo", title: "用户覆盖", summary: nil,
            argv: ["user"], fields: [], risk: "safe", interactive: nil
        )
        let extraExample = Example(
            id: "extra", tool: "jq", title: "新增", summary: nil,
            argv: ["."], fields: [], risk: "safe", interactive: nil
        )
        let baseLibrary = ExampleLibrary(version: 1, examples: [baseExample])
        let mergedLibrary = ExampleRepo.merging(
            base: baseLibrary,
            patch: UserExamplePatch(examples: [overrideExample, extraExample], remove: nil)
        )
        check(mergedLibrary.examples.count == 2
              && mergedLibrary.examples.first { $0.id == "base" }?.title == "用户覆盖",
              "用户示例按 id 覆盖内置条目", &failures)
        check(mergedLibrary.examples.contains { $0.id == "extra" },
              "用户示例可追加新工具", &failures)
        let removedLibrary = ExampleRepo.merging(
            base: mergedLibrary,
            patch: UserExamplePatch(examples: nil, remove: ["base"])
        )
        check(removedLibrary.examples.count == 1
              && removedLibrary.examples.first?.id == "extra",
              "remove 可禁用内置示例", &failures)
        check(ExampleRepo.merging(base: baseLibrary, patch: nil).examples.count == 1,
              "无用户补丁时保留内置库", &failures)
        check(ExampleRepo.examples(for: "jq", in: mergedLibrary).count == 1,
              "用户新增示例可被工具检索到", &failures)

        let baseEntry = ChineseEntry(
            title: "内置词条", summary: "内置", category: "内置分类", keywords: ["内置"]
        )
        let userEntry = ChineseEntry(
            title: "用户词条", summary: "用户", category: "用户分类",
            keywords: ["用户关键词"]
        )
        let baseDict = ChineseDictionary(
            version: 1, tools: ["mytool": baseEntry],
            rules: [ChineseRule(prefix: "my", category: "内置分类",
                                keywords: ["内置"], summary: "内置规则")],
            fallback: [:]
        )
        let mergedDict = ChineseNotes.merging(
            base: baseDict,
            patch: UserChinesePatch(
                tools: ["mytool": userEntry],
                rules: [ChineseRule(prefix: "mytool", category: "用户分类",
                                    keywords: ["用户关键词"], summary: "用户规则")],
                fallback: nil
            )
        )
        check(mergedDict.tools["mytool"]?.title == "用户词条",
              "用户中文词条覆盖内置", &failures)
        var mergeTool = Tool(
            name: "mytool", path: "/usr/bin/mytool", allPaths: [],
            category: .user, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        ChineseNotes.apply(&mergeTool, dictionary: mergedDict)
        check(mergeTool.titleZh == "用户词条",
              "合并后词典参与中文说明生成", &failures)
        var ruleTool = Tool(
            name: "mytool-extra", path: "/usr/bin/mytool-extra", allPaths: [],
            category: .user, description: "", usage: "", usageSource: "none",
            manExamples: "", interactive: false
        )
        ChineseNotes.apply(&ruleTool, dictionary: mergedDict)
        check(ruleTool.categoryZh == "用户分类",
              "用户规则按最长前缀优先生效", &failures)
        check(!AppPaths.userResourceURL(name: "examples", extension: "json")
                .path.contains(".app/Contents/Resources"),
              "用户资源目录位于签名包之外", &failures)

        let reloadModel = AppModel()
        reloadModel.load()
        let beforeReload = reloadModel.tools.count
        reloadModel.reloadResources()
        check(reloadModel.tools.count == beforeReload
              && !reloadModel.library.examples.isEmpty,
              "热重载资源不丢失索引与示例", &failures)

        // Favourites, run history and user-authored examples.
        var fav = FavoriteStore()
        fav.toggle(tool: "ffmpeg")
        fav.toggle(tool: "jq")
        check(fav.tools.count == 2 && fav.contains(tool: "ffmpeg"),
              "收藏新增与查询", &failures)
        fav.toggle(tool: "ffmpeg")
        check(fav.tools.count == 1 && !fav.contains(tool: "ffmpeg"),
              "收藏可取消", &failures)

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        let favURL = tempRoot.appendingPathComponent("cmdbook-fav-\(UUID().uuidString).json")
        let histURL = tempRoot.appendingPathComponent("cmdbook-hist-\(UUID().uuidString).json")
        let patchURL = tempRoot.appendingPathComponent("cmdbook-patch-\(UUID().uuidString).json")
        var hist = RunHistory()
        for index in 0..<(Store.historyLimit + 5) {
            hist.items.append(RunRecord(
                id: "\(index)", tool: "echo", title: "验证", command: "echo ok",
                workingDirectory: "/tmp", startedAt: "2026-11-07T00:00:00Z",
                durationMs: 1, exitCode: 0, viaTerminal: false, outputBytes: 7
            ))
        }
        do {
            try Store.saveFavorites(fav, to: favURL)
            try Store.saveHistory(hist, to: histURL)
            let loadedFav = Store.loadFavorites(from: favURL)
            let loadedHist = Store.loadHistory(from: histURL)
            check(loadedFav.tools == ["jq"],
                  "收藏持久化往返", &failures)
            check(loadedHist.items.count == Store.historyLimit,
                  "运行历史裁剪至 \(Store.historyLimit) 条", &failures)
        } catch {
            check(false, "收藏/历史持久化: \(error)", &failures)
        }

        let fields = ExampleRepo.extractFields(
            ["-i", "{{input}}", "{{output}}", "{{input}}"]
        )
        check(fields.map(\.key) == ["input", "output"],
              "从 argv 自动提取字段并去重", &failures)

        let writtenPatch = UserExamplePatch(examples: [extraExample], remove: ["base"])
        do {
            try ExampleRepo.saveUserPatch(writtenPatch, to: patchURL)
            let data = try Data(contentsOf: patchURL)
            let decoded = try JSONDecoder().decode(UserExamplePatch.self, from: data)
            check(decoded.examples?.count == 1 && decoded.remove == ["base"],
                  "用户示例补丁写回与读回", &failures)
        } catch {
            check(false, "用户示例补丁写回: \(error)", &failures)
        }

        let favIndex = SearchIndex(tools: [echoTool, ffmpegTool])
        let favOutcome = favIndex.results(
            query: "", filter: .all, limit: 50, favorites: ["ffmpeg"]
        )
        check(favOutcome.matches.count == 1
              && favOutcome.matches.first?.name == "ffmpeg",
              "只看收藏时结果被正确过滤", &failures)
        let emptyFavOutcome = favIndex.results(
            query: "ffmpeg", filter: .all, limit: 50, favorites: []
        )
        check(emptyFavOutcome.matches.isEmpty && !emptyFavOutcome.scopeExpanded,
              "收藏为空时不扩大到全部工具", &failures)
        let favoritesScope = favIndex.results(
            query: "", filter: .favorites, limit: 50, favorites: ["ffmpeg"]
        )
        check(favoritesScope.matches.count == 1
              && favoritesScope.matches.first?.name == "ffmpeg"
              && ToolFilter.favorites.label == "已收藏",
              "已收藏范围只列出收藏工具", &failures)

        // Backup format round-trip.
        let backupURL = tempRoot.appendingPathComponent(
            "cmdbook-backup-\(UUID().uuidString).json"
        )
        let sampleBackup = CmdBookBackup(
            version: 1, exportedAt: "2026-11-07T00:00:00Z",
            examples: UserExamplePatch(examples: [extraExample], remove: ["base"]),
            dictionary: nil, saved: nil,
            favorites: FavoriteStore(version: 1, tools: ["ffmpeg"], examples: []),
            history: RunHistory()
        )
        do {
            try JSONEncoder().encode(sampleBackup).write(to: backupURL)
            let decoded = try Backup.load(from: backupURL)
            check(decoded.version == 1
                  && decoded.examples?.examples?.count == 1
                  && decoded.favorites?.tools == ["ffmpeg"],
                  "备份格式编解码往返", &failures)
        } catch {
            check(false, "备份格式往返: \(error)", &failures)
        }
        try? fileManager.removeItem(at: backupURL)

        // Import merges into an isolated directory: no user data is touched.
        let importRoot = tempRoot.appendingPathComponent(
            "cmdbook-import-\(UUID().uuidString)", isDirectory: true
        )
        let importSource = tempRoot.appendingPathComponent(
            "cmdbook-import-src-\(UUID().uuidString).json"
        )
        do {
            try fileManager.createDirectory(at: importRoot, withIntermediateDirectories: true)
            let rootFavorites = importRoot.appendingPathComponent("favorites.json")
            let rootExamples = importRoot.appendingPathComponent("examples.json")
            var seedFavorites = FavoriteStore()
            seedFavorites.tools = ["seed-tool"]
            try Store.saveFavorites(seedFavorites, to: rootFavorites)
            try ExampleRepo.saveUserPatch(
                UserExamplePatch(examples: [baseExample], remove: nil), to: rootExamples
            )

            var payload = CmdBookBackup(version: 1, exportedAt: "2026-11-08T00:00:00Z")
            payload.examples = UserExamplePatch(examples: [extraExample], remove: nil)
            payload.favorites = FavoriteStore(
                version: 1, tools: ["seed-tool", "new-tool"], examples: []
            )
            try JSONEncoder().encode(payload).write(to: importSource)

            let report = try Backup.restore(from: importSource, into: importRoot)
            let mergedFavorites = Store.loadFavorites(from: rootFavorites)
            let mergedExamples = ExampleRepo.userPatch(from: rootExamples)
            check(Set(mergedFavorites.tools) == Set(["seed-tool", "new-tool"])
                  && report.favorites == 2,
                  "导入合并：收藏取并集且不重复", &failures)
            check(mergedExamples?.examples?.count == 2
                  && (mergedExamples?.examples?.contains { $0.id == "extra" } ?? false),
                  "导入合并：示例按 id 合并", &failures)
            _ = try Backup.restore(from: importSource, into: importRoot)
            let again = Store.loadFavorites(from: rootFavorites)
            check(again.tools.count == 2,
                  "重复导入保持幂等", &failures)
        } catch {
            check(false, "备份合并: \(error)", &failures)
        }
        try? fileManager.removeItem(at: importRoot)
        try? fileManager.removeItem(at: importSource)

        // Probe policy: system shims / GUI / keychain binaries are never run.
        check(Classifier.shouldSkipBinaryProbe(name: "git", path: "/usr/bin/git")
              && Classifier.shouldSkipBinaryProbe(name: "java", path: "/usr/bin/java")
              && Classifier.shouldSkipBinaryProbe(name: "security", path: "/usr/bin/security"),
              "系统 shim / Java / 钥匙串工具不执行二进制", &failures)
        check(!Classifier.shouldSkipBinaryProbe(name: "jq", path: "/opt/homebrew/bin/jq"),
              "用户安装工具仍正常探测 --help", &failures)

        // Snapshots written before probeMtime / Chinese fields must still load.
        let legacyTool = """
        {"name":"echo","path":"/bin/echo","allPaths":["/bin/echo"],
         "category":"system","description":"","usage":"echo",
         "usageSource":"help","manExamples":"","interactive":false}
        """
        if let data = legacyTool.data(using: .utf8),
           let tool = try? JSONDecoder().decode(Tool.self, from: data) {
            check(tool.probeMtime == nil && tool.titleZh.isEmpty,
                  "旧快照缺少 probeMtime 与中文字段仍可解码", &failures)
        } else {
            check(false, "旧快照兼容解码", &failures)
        }

        // Incremental scan: unchanged executable reuses the previous probe.
        let incRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmdbook-inc-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: incRoot, withIntermediateDirectories: true)
            let script = incRoot.appendingPathComponent("inctool")
            try "#!/bin/sh\necho hi\n".write(
                to: script, atomically: true, encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: script.path
            )
            var mtime: Double?
            if let attributes = try? fileManager.attributesOfItem(atPath: script.path),
               let date = attributes[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            }
            var cached = Tool(
                name: "inctool", path: script.path, allPaths: [script.path],
                category: .user, description: "", usage: "cached usage",
                usageSource: "help", manExamples: "", interactive: false
            )
            cached.probeMtime = mtime
            let previousSnapshot = Snapshot(tools: [cached])
            let incremental = Scanner.scan(
                pathEnv: incRoot.path, previous: previousSnapshot
            )
            check(incremental.reuseCount == 1
                  && incremental.tools.first?.usage == "cached usage",
                  "未变化工具复用探测结果（增量扫描）", &failures)
            let forced = Scanner.scan(
                pathEnv: incRoot.path, previous: previousSnapshot, forceFull: true
            )
            check(forced.reuseCount == 0,
                  "强制全量时跳过复用", &failures)
        } catch {
            check(false, "增量扫描测试准备: \(error)", &failures)
        }
        try? fileManager.removeItem(at: incRoot)

        for url in [favURL, histURL, patchURL] {
            try? fileManager.removeItem(at: url)
        }

        let snapshot = Snapshot(
            version: 1,
            scannedAt: "2026-11-06T00:00:00Z",
            loginPath: "/usr/bin:/bin",
            summary: ScanSummary(),
            tools: [echoTool]
        )
        let encoded = try? JSONEncoder().encode(snapshot)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        check(decoded?.tools.first?.name == "echo", "快照 JSON 编解码", &failures)

        print("=== 验证结果 ===")
        if failures.isEmpty {
            print("全部通过")
        } else {
            print("失败项：\(failures.joined(separator: "、"))")
        }
        return failures.isEmpty ? 0 : 1
    }

    private static func check(_ condition: Bool, _ label: String, _ failures: inout [String]) {
        print("\(condition ? "PASS" : "FAIL")  \(label)")
        if !condition { failures.append(label) }
    }
}
