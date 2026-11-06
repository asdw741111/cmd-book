import Foundation
import Darwin

enum RunnerError: Error, LocalizedError {
    case dangerousTool(String)
    case interactiveTool(String)
    case missingExecutable(String)
    case invalidValue(String)
    case tempFileUnavailable

    var errorDescription: String? {
        switch self {
        case .dangerousTool(let name):
            return "出于安全考虑，不允许在应用内执行 \(name)。"
        case .interactiveTool(let name):
            return "\(name) 是交互式终端程序，请在 Terminal 中打开。"
        case .missingExecutable(let path):
            return "找不到可执行文件：\(path)"
        case .invalidValue(let key):
            return "参数 \(key) 含有非法字符。"
        case .tempFileUnavailable:
            return "无法创建临时输出文件。"
        }
    }
}

struct RunRequest {
    var tool: Tool
    var example: Example
    var values: [String: String]
    var workingDirectory: URL
    var loginPath: String
}

enum Runner {
    /// Expands `{{key}}` placeholders inside individual argv elements only.
    /// No shell string is ever constructed for the in-app runner.
    static func expandedArguments(
        _ example: Example, values: [String: String]
    ) throws -> [String] {
        let defaults = Dictionary(uniqueKeysWithValues: example.fields.map { ($0.key, $0.value) })
        return try example.argv.map { try expand($0, values: values, defaults: defaults) }
    }

    private static func expand(
        _ template: String, values: [String: String], defaults: [String: String]
    ) throws -> String {
        var output = ""
        var cursor = template.startIndex
        while let open = template.range(of: "{{", range: cursor..<template.endIndex) {
            output += template[cursor..<open.lowerBound]
            guard let close = template.range(
                of: "}}", range: open.upperBound..<template.endIndex
            ) else {
                output += template[open.lowerBound...]
                return output
            }
            let key = String(template[open.upperBound..<close.lowerBound])
            let value = values[key] ?? defaults[key] ?? ""
            if value.contains("\u{0}") { throw RunnerError.invalidValue(key) }
            output += value
            cursor = close.upperBound
        }
        output += template[cursor...]
        return output
    }

    static func validate(tool: Tool, example: Example) throws {
        if Classifier.isDangerous(tool.name) {
            throw RunnerError.dangerousTool(tool.name)
        }
        if tool.interactive || example.isInteractive {
            throw RunnerError.interactiveTool(tool.name)
        }
        if !FileManager.default.isExecutableFile(atPath: tool.path) {
            throw RunnerError.missingExecutable(tool.path)
        }
    }
}

/// Executes one whitelisted example. Output is streamed by polling two temp files,
/// which avoids the readabilityHandler / readDataToEndOfFile conflict on macOS.
final class RunningProcess {
    var onOutput: ((String) -> Void)?
    var onFinish: ((Int32?, Bool) -> Void)?
    /// Main queue in the GUI app; overridable so headless verification does not
    /// depend on an NSApplication run loop.
    var callbackQueue: DispatchQueue = .main

    private let lock = NSLock()
    private var process: Process?
    private var timer: DispatchSourceTimer?
    private var outHandle: FileHandle?
    private var errHandle: FileHandle?
    private var outURL: URL?
    private var errURL: URL?
    private var outOffset: UInt64 = 0
    private var errOffset: UInt64 = 0
    private var finished = false
    private var killed = false

    func start(_ request: RunRequest, timeout: TimeInterval = 60) throws {
        let argv = try Runner.expandedArguments(request.example, values: request.values)
        try Runner.validate(tool: request.tool, example: request.example)

        let fileManager = FileManager.default
        let tag = UUID().uuidString
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let outURL = base.appendingPathComponent("cmdbook-run-\(tag)-out")
        let errURL = base.appendingPathComponent("cmdbook-run-\(tag)-err")
        guard fileManager.createFile(atPath: outURL.path, contents: nil),
              fileManager.createFile(atPath: errURL.path, contents: nil) else {
            throw RunnerError.tempFileUnavailable
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        self.outURL = outURL
        self.errURL = errURL
        self.outHandle = outHandle
        self.errHandle = errHandle

        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.tool.path)
        process.arguments = argv
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = request.loginPath
        environment["PAGER"] = "cat"
        environment["MANPAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        environment["LC_ALL"] = "C"
        environment["TERM"] = "dumb"
        environment["COLUMNS"] = "120"
        process.environment = environment
        process.currentDirectoryURL = request.workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.terminationHandler = { [weak self] terminated in
            self?.complete(status: terminated.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            try? fileManager.removeItem(at: outURL)
            try? fileManager.removeItem(at: errURL)
            throw error
        }
        self.process = process

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.stop()
        }
    }

    func stop() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        killed = true
        let pid = process?.processIdentifier
        lock.unlock()
        if let pid = pid { kill(pid, SIGKILL) }
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        drainLocked()
    }

    private func complete(status: Int32) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        drainLocked()
        let wasKilled = killed
        let timer = self.timer
        let outHandle = self.outHandle
        let errHandle = self.errHandle
        let urls = [self.outURL, self.errURL].compactMap { $0 }
        lock.unlock()

        timer?.cancel()
        try? outHandle?.close()
        try? errHandle?.close()
        for url in urls { try? FileManager.default.removeItem(at: url) }
        let queue = callbackQueue
        queue.async { [weak self] in
            self?.onFinish?(wasKilled ? nil : status, wasKilled)
        }
    }

    private func drainLocked() {
        if let url = outURL, let text = readNew(url, offset: &outOffset), !text.isEmpty {
            emit(text)
        }
        if let url = errURL, let text = readNew(url, offset: &errOffset), !text.isEmpty {
            emit(text)
        }
    }

    private func readNew(_ url: URL, offset: inout UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        guard end > offset else { return nil }
        try? handle.seek(toOffset: offset)
        let length = Int(min(end - offset, 262144))
        let data = (try? handle.read(upToCount: length)) ?? Data()
        offset += UInt64(data.count)
        return String(decoding: data, as: UTF8.self)
    }

    private func emit(_ text: String) {
        let queue = callbackQueue
        queue.async { [weak self] in self?.onOutput?(text) }
    }
}

enum TerminalBridge {
    static func open(argv: [String], loginPath: String) throws {
        let quoted = argv.map(shellQuote).joined(separator: " ")
        let script = """
        #!/bin/zsh
        export PATH=\(shellQuote(loginPath))
        \(quoted)
        echo
        echo "命令已结束。可关闭此窗口。"
        exec zsh
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmdbook-\(UUID().uuidString).command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path
        )
        _ = ProcessSupport.run(
            executable: "/usr/bin/open",
            arguments: ["-a", "Terminal", url.path],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5.0
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
