import SwiftUI

/// In-app editor for user-defined examples. Saves into the user's
/// `examples.json` overlay so no rebuild or manual JSON editing is needed.
struct ExampleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var tool: String
    @State private var title = ""
    @State private var summary = ""
    @State private var argvText = ""
    @State private var risk = "safe"
    @State private var interactive = false
    @State private var errorMessage: String?

    init(defaultTool: String) {
        _tool = State(initialValue: defaultTool)
    }

    private var parsedArguments: [String] {
        argvText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var detectedFields: [String] {
        ExampleRepo.extractFields(parsedArguments).map { $0.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建自定义示例").font(.title2).fontWeight(.semibold)
            Text("每行一个参数，按参数数组直接执行、不经过 shell；用 {{key}} 表示运行时可编辑的字段。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("工具名（如 ffmpeg）", text: $tool)
                TextField("标题", text: $title)
                TextField("说明（可选）", text: $summary)
                Picker("风险等级", selection: $risk) {
                    Text("只读").tag("safe")
                    Text("会写入文件").tag("write")
                    Text("高风险（一律转交 Terminal）").tag("danger")
                }
                Toggle("交互式终端程序", isOn: $interactive)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("参数（每行一个）").font(.subheadline)
                TextEditor(text: $argvText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                if !detectedFields.isEmpty {
                    Text("自动识别字段：\(detectedFields.joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存示例") {
                    if let error = model.saveCustomExample(
                        tool: tool, title: title, summary: summary,
                        argv: parsedArguments, risk: risk, interactive: interactive
                    ) {
                        errorMessage = error
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    tool.trimmingCharacters(in: .whitespaces).isEmpty
                        || title.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}
