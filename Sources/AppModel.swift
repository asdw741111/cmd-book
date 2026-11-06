import Foundation
import SwiftUI
import AppKit

enum ToolFilter: String, CaseIterable, Identifiable {
    case user
    case all
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .user: return "用户安装"
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
        let outcome = index.results(query: query, filter: filter, limit: maxRendered)
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
        return """
        \(pendingCommandText)

        风险等级：\(example.riskLabel)
        工作目录：\(workingDirectory)

        命令按参数数组直接执行，不经过 shell；执行前请确认输出文件不会覆盖重要数据。
        """
    }

    func load() {
        library = ExampleRepo.load()
        chineseDictionary = ChineseNotes.load()
        savedStore = Store.loadSaved()

        // Re-apply Chinese notes at load time so editing Resources/tool-zh.json
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
            do {
                try Store.saveSnapshot(snapshot)
            } catch {
                DispatchQueue.main.async { [self] in
                    self.notice = "快照写入失败：\(error.localizedDescription)"
                }
            }
            DispatchQueue.main.async { [self] in
                self.snapshot = snapshot
                self.isScanning = false
                self.statusText = "扫描完成 · \(snapshot.summary.discovered) 个工具 · \(snapshot.summary.withUsage) 个有用法 · \(Self.displayDate(snapshot.scannedAt))"
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
        if example.isInteractive || tool.interactive {
            openInTerminal(example: example, tool: tool)
            return
        }
        confirmRun = true
    }

    func performRun() {
        guard let example = activeExample, let tool = selectedTool else { return }
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
            try TerminalBridge.open(argv: [tool.path] + argv, loginPath: loginPath)
            notice = "已在 Terminal 中打开 \(tool.name)（交互式工具需要在真实终端运行）"
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
