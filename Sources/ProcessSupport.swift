import Foundation
import Darwin

struct CapturedProcess {
    var stdout: String = ""
    var stderr: String = ""
    var exitCode: Int32? = nil
    var timedOut: Bool = false
}

enum ProcessSupport {
    /// Deterministic environment for help/man probes. PATH is intentionally minimal;
    /// the tool itself is always launched by absolute path.
    static let probeEnvironment: [String: String] = [
        "PAGER": "cat",
        "MANPAGER": "cat",
        "GIT_PAGER": "cat",
        "LC_ALL": "C",
        "TERM": "dumb",
        "COLUMNS": "80",
        "HOME": NSHomeDirectory(),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
    ]

    /// Runs a child process with a hard timeout, capturing stdout/stderr via temp files.
    /// Temp files avoid the pipe deadlock that occurs when a child writes more than
    /// the pipe buffer while nobody is reading.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        maxBytes: Int = 262144
    ) -> CapturedProcess {
        let fm = FileManager.default
        let tag = UUID().uuidString
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let outURL = base.appendingPathComponent("cmdbook-\(tag)-out")
        let errURL = base.appendingPathComponent("cmdbook-\(tag)-err")
        // Some CLI tools create files even when invoked with --help. Isolate every
        // probe in its own throwaway CWD so scanning never touches the workspace.
        let cwdURL = base.appendingPathComponent("cmdbook-\(tag)-cwd", isDirectory: true)

        guard fm.createFile(atPath: outURL.path, contents: nil),
              fm.createFile(atPath: errURL.path, contents: nil) else {
            return CapturedProcess()
        }
        try? fm.createDirectory(at: cwdURL, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
            try? fm.removeItem(at: cwdURL)
        }

        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            return CapturedProcess()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.currentDirectoryURL = cwdURL

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            return CapturedProcess()
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1.0)
        }

        try? outHandle.close()
        try? errHandle.close()

        return CapturedProcess(
            stdout: readPrefix(outURL, maxBytes: maxBytes),
            stderr: readPrefix(errURL, maxBytes: maxBytes),
            exitCode: timedOut ? nil : process.terminationStatus,
            timedOut: timedOut
        )
    }

    private static func readPrefix(_ url: URL, maxBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return "" }
        return String(decoding: data.prefix(maxBytes), as: UTF8.self)
    }

    /// A GUI app launched from Finder does not inherit the shell PATH. `/etc/paths.d`
    /// (including the Homebrew entry) is only applied by path_helper in a LOGIN shell,
    /// so `-l` is mandatory; `-i` additionally picks up ~/.zshrc additions.
    /// Sources are merged rather than short-circuited, because any single source
    /// can be incomplete.
    static func resolveLoginPath() -> String {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        environment["USER"] = NSUserName()
        environment["SHELL"] = "/bin/zsh"
        environment["TERM"] = "dumb"
        if environment["PATH"]?.isEmpty ?? true {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }

        var sources: [String] = []
        for flags in [["-l", "-i"], ["-l"]] {
            let result = run(
                executable: "/bin/zsh",
                arguments: flags + ["-c", "printf \"%s\" \"$PATH\""],
                environment: environment,
                timeout: 3.0,
                maxBytes: 65536
            )
            let line = result.stdout
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last(where: { $0.contains(":") && $0.hasPrefix("/") }) ?? ""
            if !line.isEmpty { sources.append(line) }
        }
        sources.append(systemPathsValue())
        sources.append(ProcessInfo.processInfo.environment["PATH"] ?? "")

        var seen: Set<String> = []
        var merged: [String] = []
        for source in sources {
            for raw in source.split(separator: ":", omittingEmptySubsequences: true) {
                let directory = (String(raw) as NSString).standardizingPath
                guard !directory.isEmpty, !seen.contains(directory) else { continue }
                seen.insert(directory)
                merged.append(directory)
            }
        }
        return merged.isEmpty ? "/usr/bin:/bin:/usr/sbin:/sbin" : merged.joined(separator: ":")
    }

    /// Direct fallback when zsh is unavailable: /etc/paths plus /etc/paths.d/*.
    private static func systemPathsValue() -> String {
        var entries: [String] = []
        if let text = try? String(contentsOfFile: "/etc/paths", encoding: .utf8) {
            entries += text.split(separator: "\n").map(String.init)
        }
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(atPath: "/etc/paths.d") {
            for file in files.sorted() {
                let path = "/etc/paths.d/" + file
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                entries += text.split(separator: "\n").map(String.init)
            }
        }
        return entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }
}

/// A small thread-safe box used by the scanner's concurrent probe loop.
final class LockedBox<T> {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    func withValue<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
