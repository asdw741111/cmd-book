import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let cmdbookFocusSearch = Notification.Name("cmdbook.focusSearch")
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView()
            } content: {
                DetailView()
            } detail: {
                ConsoleView()
            }
            if let notice = model.notice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                    Text(notice).font(.caption).lineLimit(2)
                    Spacer()
                    Button("关闭") { model.notice = nil }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.10))
            }
        }
        .frame(minWidth: 1060, minHeight: 640)
        .alert("确认执行命令", isPresented: $model.confirmRun) {
            Button("取消", role: .cancel) { }
            Button("执行", role: .destructive) { model.performRun() }
        } message: {
            Text(model.confirmationMessage)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CmdBook").font(.headline)
                    Spacer()
                    Button {
                        model.rescan()
                    } label: {
                        Label(model.isScanning ? "扫描中…" : "重新扫描", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                }
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("搜索名称、中文说明或关键词，如：数据恢复", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onExitCommand { model.query = "" }
                    .onReceive(NotificationCenter.default.publisher(for: .cmdbookFocusSearch)) { _ in
                        searchFocused = true
                    }

                Picker("范围", selection: $model.filter) {
                    Text("用户安装").tag(ToolFilter.user)
                    Text("全部").tag(ToolFilter.all)
                    Text("系统自带").tag(ToolFilter.system)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("\(model.matches.count) 个结果")
                    Spacer()
                    if model.matches.count > model.visibleMatches.count {
                        Text("仅显示前 \(model.visibleMatches.count) 个")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("内置中文词条 \(model.exactChineseCount) 条 · 其余由规则与分类兜底")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if model.scopeExpanded {
                    Text("当前筛选无结果，已自动扩大到全部工具")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)

            Divider()

            List(model.visibleMatches, selection: $model.selectedName) { tool in
                ToolRow(tool: tool).tag(tool.name)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 290)
    }
}

struct ToolRow: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(tool.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                if !tool.titleZh.isEmpty && tool.titleZh != tool.name {
                    Text(tool.titleZh)
                        .font(.caption)
                        .lineLimit(1)
                }
                SourceBadge(text: tool.usageSource)
            }
            Text(tool.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            let summary = tool.summaryZh.isEmpty ? tool.description : tool.summaryZh
            if !summary.isEmpty || !tool.categoryZh.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    if !tool.categoryZh.isEmpty {
                        Text(tool.categoryZh)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct SourceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeColor.opacity(0.16))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var badgeColor: Color {
        switch text {
        case "help": return .green
        case "man": return .blue
        default: return .secondary
        }
    }
}

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let tool = model.selectedTool {
                ToolDetail(tool: tool)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "text.book.closed").font(.largeTitle)
                    Text("从左侧选择一个工具")
                    Text("用法文本、内置示例和保存的参数组合会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 390)
    }
}

struct ToolDetail: View {
    @EnvironmentObject var model: AppModel
    let tool: Tool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(tool.category.label)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        SourceBadge(text: tool.usageSource)
                    }
                    if !tool.description.isEmpty {
                        Text(tool.description).font(.body)
                    }
                    Text(tool.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ForEach(tool.allPaths.dropFirst(), id: \.self) { path in
                        Text("同时位于：\(path)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if tool.interactive {
                        Text("交互式终端程序：应用内不执行，示例会转交 Terminal。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !tool.summaryZh.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("中文说明").font(.headline)
                            if !tool.categoryZh.isEmpty {
                                Text(tool.categoryZh)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        if !tool.titleZh.isEmpty && tool.titleZh != tool.name {
                            Text(tool.titleZh).font(.title3).fontWeight(.medium)
                        }
                        Text(tool.summaryZh).font(.body)
                        if !tool.keywords.isEmpty {
                            Text("中文关键词 · 点击可直接搜索")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 84), spacing: 6)],
                                alignment: .leading, spacing: 6
                            ) {
                                ForEach(tool.keywords, id: \.self) { keyword in
                                    Button {
                                        model.query = keyword
                                    } label: {
                                        Text(keyword).font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                sectionHeader("常用示例", count: model.examplesForSelectedTool.count)
                if model.examplesForSelectedTool.isEmpty {
                    Text("该工具暂无内置示例，可使用下方用法文本或 man 补充示例。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.examplesForSelectedTool) { example in
                        ExampleCard(example: example, tool: tool)
                    }
                }

                let saved = model.savedItems(for: tool.name)
                if !saved.isEmpty {
                    sectionHeader("已保存的参数组合", count: saved.count)
                    ForEach(saved) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.example.title).font(.caption)
                                Text(item.saved.values.values.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("载入") { model.applySaved(item.saved) }
                            Button("删除") { model.deleteSaved(item.saved.id) }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                if !tool.manExamples.isEmpty {
                    sectionHeader("man 页面中的 EXAMPLES", count: nil)
                    CodeBlock(text: tool.manExamples)
                }

                sectionHeader("用法文本 · \(tool.usageSource)", count: nil)
                CodeBlock(text: tool.usage.isEmpty ? "（未捕获到用法文本，可在终端执行 man \(tool.name)）" : tool.usage)
                Button("复制用法文本") { AppModel.copy(tool.usage) }
                    .disabled(tool.usage.isEmpty)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title).font(.headline)
            if let count = count { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ExampleCard: View {
    @EnvironmentObject var model: AppModel
    let example: Example
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(example.title).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(example.riskLabel)
                    .font(.caption2)
                    .foregroundStyle(example.risk == "danger" ? .red : (example.risk == "write" ? .orange : .secondary))
            }
            if let summary = example.summary, !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Text(ExampleRepo.commandPreview(example, values: [:]))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(example.isInteractive || tool.interactive ? "在 Terminal 打开" : "运行") {
                    model.selectExample(example)
                    model.requestRun()
                }
                .buttonStyle(.borderedProminent)
                Button("填入参数") { model.selectExample(example) }
                Button("复制命令") {
                    AppModel.copy(ExampleRepo.commandPreview(example, values: [:]))
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 280)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ConsoleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行控制台").font(.headline)

            if let example = model.activeExample {
                Text(example.title).font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(example.fields) { field in
                    HStack(alignment: .top, spacing: 8) {
                        Text(field.label)
                            .font(.caption)
                            .frame(width: 100, alignment: .trailing)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField(field.hint ?? "", text: Binding(
                                get: { model.fieldValues[field.key] ?? field.value },
                                set: { model.fieldValues[field.key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            if let hint = field.hint, !hint.isEmpty {
                                Text(hint).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                HStack {
                    Text("工作目录").font(.caption).frame(width: 100, alignment: .trailing)
                    Text(model.workingDirectory)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("选择…") { model.chooseDirectory() }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("最终命令（参数数组，不经 shell）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.pendingCommandText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button(model.isRunning ? "运行中…" : "执行") { model.requestRun() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRunning || model.selectedTool == nil)
                    Button("停止") { model.stopRun() }.disabled(!model.isRunning)
                    Button("复制命令") { AppModel.copy(model.pendingCommandText) }
                    Button("保存参数") { model.saveCurrentExample() }
                }

                Divider()

                HStack {
                    Text("输出").font(.subheadline)
                    Spacer()
                    Text(model.exitText).font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(model.runOutput.isEmpty ? "（尚无输出）" : model.runOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("在中间栏选择一个示例，这里会展开参数表单、执行确认与实时输出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
