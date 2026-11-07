import Foundation
import SwiftUI
import AppKit

enum ToolFilter: String, CaseIterable, Identifiable {
    case user
    case favorites
    case all
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .user: return "用户安装"
        case .favorites: return "已收藏"
        case .all: return "全部"
        case .system: return "系统自带"
        }
    }
}

final class AppModel: ObservableObject {
    @Published var snapshot: Snapshot? {
        didSet {
            rebuildIndex()
            recomputeResults()
        }
    }
    @Published var library = ExampleLibrary(version: 1, examples: [])
    @Published var chineseDictionary = ChineseDictionary.empty
    @Published var savedStore = SavedStore()
    @Published var query = "" {
        didSet { recomputeResults() }
    }
    @Published var filter: ToolFilter = .user {
        didSet { recomputeResults() }
    }
    @Published var selectedName: String? {
        didSet {
            guard selectedName != oldValue else { return }
            guard let name = selectedName,
                  let first = ExampleRepo.examples(for: name, in: library).first else {
                activeExample = nil
                fieldValues = [:]
                return
            }
            selectExample(first)
        }
    }
    @Published var isScanning = false
    @Published var statusText = "正在载入…"
    @Published var notice: String?
    @Published var activeExample: Example?
    @Published var fieldValues: [String: String] = [:]
    @Published var workingDirectory = NSHomeDirectory()
    @Published var runOutput = ""
    @Published var isRunning = false
    @Published var exitText = ""
    @Published var confirmRun = false
    @Published var confirmPolicy: ExecutionPolicy = .inApp
    @Published var favorites = FavoriteStore()
    @Published var history = RunHistory()
    @Published var showingExampleEditor = false

    // Search results are cached. SwiftUI reads `matches.count`, `visibleMatches`
    // and `scopeExpanded` several times per body evaluation, so recomputing them
    // as computed properties used to run a full 2101-tool sort up to 6 times per
    // keystroke (~1.8 s). Now one query change performs exactly one lookup.
    @Published private(set) var matches: [Tool] = []
    @Published private(set) var visibleMatches: [Tool] = []
    @Published private(set) var scopeExpanded = false
    @Published private(set) var exactChineseCount = 0

    private var runner: RunningProcess?
    private var searchIndex: SearchIndex?
    private let maxRendered = 300

    var tools: [Tool] { snapshot?.tools ?? [] }
    var selectedTool: Tool? { tools.first { $0.name == selectedName } }

    private func rebuildIndex() {
        searchIndex = SearchIndex(tools: tools)
        exactChineseCount = tools.filter {
            chineseDictionary.tools[$0.name] != nil
        }.count
    }

    private func recomputeResults() {
        guard let index = searchIndex else {
            matches = []
            visibleMatches = []
            scopeExpanded = false
            return
        }
        let outcome = index.results(
            query: query, filter: filter, limit: maxRendered,
            favorites: filter == .favorites ? Set(favorites.tools) : nil
        )
        matches = outcome.matches
        visibleMatches = outcome.visible
        scopeExpanded = outcome.scopeExpanded
    }

    var examplesForSelectedTool: [Example] {
        guard let name = selectedName else { return [] }
        return ExampleRepo.examples(for: name, in: library)
    }

    var pendingCommandText: String {
        guard let example = activeExample, let tool = selectedTool else {
            return "（未选择示例）"
        }
        let argv = (try? Runner.expandedArguments(example, values: fieldValues)) ?? []
        return ([tool.path] + argv).joined(separator: " ")
    }

    var confirmationMessage: String {
        guard let example = activeExample else { return "" }
        let warning: String
        switch confirmPolicy {
        case .confirmWrite:
            warning = "注意：此示例会写入或覆盖文件。请确认输出路径与工作目录无误。\n命令按参数数组直接执行，不经过 shell。"
        case .inApp:
            warning = "命令按参数数组直接执行，不经过 shell。"
        case .terminalOnly:
            warning = "此命令将在 Terminal 中运行。"
        }
        return """
        \(pendingCommandText)

        风险等级：\(example.riskLabel)
        工作目录：\(workingDirectory)

        \(warning)
        """
    }

    func load() {
        loadResources()
        savedStore = Store.loadSaved()
        favorites = Store.loadFavorites()
        history = Store.loadHistory()

        // Re-apply Chinese notes at load time so editing the user dictionary
        // takes effect on next launch without requiring a full rescan.
        if var loaded = Store.loadSnapshot() {
            loaded.tools = loaded.tools.map { tool in
                var updated = tool
                ChineseNotes.apply(&updated, dictionary: chineseDictionary)
                return updated
            }
            snapshot = loaded
        } else {
            snapshot = nil
        }

        if let snapshot = snapshot {
            statusText = "上次扫描：\(Self.displayDate(snapshot.scannedAt)) · 共 \(snapshot.summary.discovered) 个工具"
        } else {
            statusText = "尚无索引，点击「重新扫描」开始"
        }

        // Open on a useful tool instead of an empty detail pane.
        if selectedName == nil {
            let preferred = ["ffmpeg", "rg", "jq"]
            selectedName = preferred.first { name in tools.contains { $0.name == name } }
                ?? tools.first { $0.category == .user }?.name
                ?? tools.first?.name
        }
    }

    private func loadResources() {
        library = ExampleRepo.load()
        chineseDictionary = ChineseNotes.load()
    }

    var userResourceStatus: String {
        let fileManager = FileManager.default
        let hasExamples = fileManager.fileExists(
            atPath: AppPaths.userResourceURL(name: "examples", extension: "json").path
        )
        let hasDictionary = fileManager.fileExists(
            atPath: AppPaths.userResourceURL(name: "tool-zh", extension: "json").path
        )
        switch (hasExamples, hasDictionary) {
        case (true, true): return "用户资源：自定义示例 + 中文词典已生效"
        case (true, false): return "用户资源：自定义示例已生效"
        case (false, true): return "用户资源：中文词典已生效"
        case (false, false): return "用户资源：未启用（工具菜单可打开目录）"
        }
    }

    /// Re-reads bundle + user overlays and re-applies Chinese metadata without
    /// rescanning or restarting. `snapshot.didSet` rebuilds the search index.
    func reloadResources() {
        loadResources()
        if var current = snapshot {
            current.tools = current.tools.map { tool in
                var updated = tool
                ChineseNotes.apply(&updated, dictionary: chineseDictionary)
                return updated
            }
            snapshot = current
        } else {
            rebuildIndex()
            recomputeResults()
        }
        notice = "资源已重新载入 · \(library.examples.count) 条示例 · \(chineseDictionary.tools.count) 条中文词条"
    }

    func openUserResourcesDirectory() {
        AppPaths.prepare()
        NSWorkspace.shared.open(AppPaths.supportDirectory)
    }

    // MARK: - Favourites

    func isFavorite(_ name: String) -> Bool { favorites.contains(tool: name) }

    func toggleFavorite(tool name: String) {
        favorites.toggle(tool: name)
        do {
            try Store.saveFavorites(favorites)
            notice = isFavorite(name)
                ? "已收藏 \(name) · 可在「已收藏」范围查看"
                : "已取消收藏 \(name)"
        } catch {
            notice = "收藏保存失败：\(error.localizedDescription)"
        }
        if filter == .favorites { recomputeResults() }
    }

    // MARK: - Run history

    func historyDate(_ iso: String) -> String { Self.displayDate(iso) }

    func clearHistory() {
        history = RunHistory()
        do {
            try Store.saveHistory(history)
            notice = "运行历史已清空"
        } catch {
            notice = "清空失败：\(error.localizedDescription)"
        }
    }

    private func makeRecord(
        tool: Tool, example: Example, command: String, startedAt: Date,
        exitCode: Int32?, viaTerminal: Bool, outputBytes: Int
    ) -> RunRecord {
        RunRecord(
            id: UUID().uuidString,
            tool: tool.name,
            title: example.title,
            command: command,
            workingDirectory: workingDirectory,
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            durationMs: Int(max(0, Date().timeIntervalSince(startedAt) * 1000)),
            exitCode: exitCode,
            viaTerminal: viaTerminal,
            outputBytes: outputBytes
        )
    }

    private func appendHistory(_ record: RunRecord) {
        history.items.insert(record, at: 0)
        if history.items.count > Store.historyLimit {
            history.items = Array(history.items.prefix(Store.historyLimit))
        }
        do {
            try Store.saveHistory(history)
        } catch {
            notice = "运行历史保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Custom examples

    func isUserExample(_ example: Example) -> Bool {
        example.id.hasPrefix("user-")
    }

    /// Returns nil on success, or a human-readable validation/error message.
    func saveCustomExample(
        tool: String, title: String, summary: String, argv: [String],
        risk: String, interactive: Bool
    ) -> String? {
        let trimmedTool = tool.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTool.isEmpty, !trimmedTitle.isEmpty, !argv.isEmpty else {
            return "工具名、标题和参数都不能为空。"
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = Example(
            id: "user-\(UUID().uuidString.prefix(8))",
            tool: trimmedTool,
            title: trimmedTitle,
            summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
            argv: argv,
            fields: ExampleRepo.extractFields(argv),
            risk: risk,
            interactive: interactive ? true : nil
        )
        var patch = ExampleRepo.userPatch() ?? UserExamplePatch(examples: nil, remove: nil)
        var items = patch.examples ?? []
        items.append(example)
        patch.examples = items
        do {
            try ExampleRepo.saveUserPatch(patch)
            reloadResources()
            return nil
        } catch {
            return "保存失败：\(error.localizedDescription)"
        }
    }

    func deleteCustomExample(_ example: Example) {
        guard var patch = ExampleRepo.userPatch() else { return }
        patch.examples?.removeAll { $0.id == example.id }
        do {
            try ExampleRepo.saveUserPatch(patch)
            reloadResources()
        } catch {
            notice = "删除失败：\(error.localizedDescription)"
        }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        statusText = "正在解析登录 PATH 并扫描…"
        let exampleTools = ExampleRepo.toolNames(in: library)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let snapshot = Scanner.scan(exampleTools: exampleTools) { done, total in
                DispatchQueue.main.async { [self] in
                    self.statusText = "已扫描 \(done) / \(total) 个工具"
                }
            }
            var failure: String?
            do {
                if try Store.saveSnapshot(snapshot) == false {
                    failure = "本次扫描结果明显差于上一份索引（工具数或用法文本数下降超过 10%），已保留原有数据，未覆盖快照。"
                }
            } catch {
                failure = "快照写入失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async { [self] in
                self.isScanning = false
                if let failure = failure {
                    self.notice = failure
                    self.statusText = "扫描未更新 · 已保留上一份索引"
                } else {
                    self.snapshot = snapshot
                    self.statusText = "扫描完成 · \(snapshot.summary.discovered) 个工具 · \(snapshot.summary.withUsage) 个有用法 · \(Self.displayDate(snapshot.scannedAt))"
                }
            }
        }
    }

    func selectExample(_ example: Example) {
        activeExample = example
        fieldValues = Dictionary(uniqueKeysWithValues: example.fields.map { ($0.key, $0.value) })
        runOutput = ""
        exitText = ""
    }

    func requestRun() {
        guard let example = activeExample, let tool = selectedTool else { return }
        let policy = Runner.policy(for: tool, example: example)
        confirmPolicy = policy
        guard policy == .terminalOnly else {
            confirmRun = true
            return
        }
        // Terminal hand-off must pass the same safety checks as in-app runs.
        do {
            try Runner.validateSafety(tool: tool)
        } catch {
            notice = error.localizedDescription
            return
        }
        openInTerminal(example: example, tool: tool)
    }

    func performRun() {
        guard let example = activeExample, let tool = selectedTool else { return }
        if Runner.policy(for: tool, example: example) == .terminalOnly {
            notice = "此命令需要在 Terminal 中运行，不能在应用内执行。"
            return
        }
        do {
            try Runner.validate(tool: tool, example: example)
        } catch {
            notice = error.localizedDescription
            return
        }

        let loginPath = snapshot?.loginPath
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let request = RunRequest(
            tool: tool,
            example: example,
            values: fieldValues,
            workingDirectory: URL(fileURLWithPath: workingDirectory),
            loginPath: loginPath
        )
        let startedAt = Date()
        let command = pendingCommandText

        let process = RunningProcess()
        process.onOutput = { [weak self] text in
            guard let self = self else { return }
            self.runOutput += text
            if self.runOutput.count > 200000 {
                self.runOutput = "[输出已截断]\n" + String(self.runOutput.suffix(180000))
            }
        }
        process.onFinish = { [weak self] status, killed in
            guard let self = self else { return }
            self.isRunning = false
            self.runner = nil
            if killed {
                self.exitText = "已终止（超时或手动停止）"
            } else if let status = status {
                self.exitText = status == 0 ? "退出码 0 · 成功" : "退出码 \(status)"
            } else {
                self.exitText = "未取得退出码"
            }
            self.appendHistory(self.makeRecord(
                tool: tool, example: example, command: command,
                startedAt: startedAt, exitCode: killed ? nil : status,
                viaTerminal: false, outputBytes: self.runOutput.utf8.count
            ))
        }

        do {
            try process.start(request)
            runner = process
            runOutput = ""
            exitText = "运行中…"
            isRunning = true
        } catch {
            notice = error.localizedDescription
        }
    }

    func stopRun() { runner?.stop() }

    func openInTerminal(example: Example, tool: Tool) {
        let argv = (try? Runner.expandedArguments(example, values: fieldValues)) ?? []
        let loginPath = snapshot?.loginPath
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        do {
            try TerminalBridge.open(
                argv: [tool.path] + argv,
                loginPath: loginPath,
                workingDirectory: URL(fileURLWithPath: workingDirectory)
            )
            notice = "已在 Terminal 中打开 \(tool.name)（高风险或交互式命令需要在真实终端运行）"
            appendHistory(makeRecord(
                tool: tool, example: example,
                command: ([tool.path] + argv).joined(separator: " "),
                startedAt: Date(), exitCode: nil,
                viaTerminal: true, outputBytes: 0
            ))
        } catch {
            notice = "无法打开 Terminal：\(error.localizedDescription)"
        }
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    func savedItems(for tool: String) -> [SavedItem] {
        savedStore.items.compactMap { item in
            guard let example = library.examples.first(where: { $0.id == item.exampleID }),
                  example.tool == tool else { return nil }
            return SavedItem(saved: item, example: example)
        }
    }

    func applySaved(_ item: SavedExample) {
        guard let example = library.examples.first(where: { $0.id == item.exampleID }) else { return }
        selectExample(example)
        fieldValues = item.values
        notice = "已载入保存的参数组合"
    }

    func saveCurrentExample() {
        guard let example = activeExample else { return }
        savedStore.items.append(
            SavedExample(id: UUID().uuidString, exampleID: example.id, values: fieldValues)
        )
        do {
            try Store.saveSaved(savedStore)
            notice = "已保存当前参数组合"
        } catch {
            notice = "保存失败：\(error.localizedDescription)"
        }
    }

    func deleteSaved(_ id: String) {
        savedStore.items.removeAll { $0.id == id }
        try? Store.saveSaved(savedStore)
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func focusSearch() {
        NotificationCenter.default.post(name: .cmdbookFocusSearch, object: nil)
    }

    private static func displayDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.dateStyle = .short
        output.timeStyle = .short
        output.locale = Locale(identifier: "zh_CN")
        return output.string(from: date)
    }
}
