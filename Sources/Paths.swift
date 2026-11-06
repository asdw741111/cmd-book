import Foundation

enum AppPaths {
    static let bundleIdentifier = "local.cmdbook.macos"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CmdBook", isDirectory: true)
    }

    static var snapshotURL: URL { supportDirectory.appendingPathComponent("tools.json") }
    static var savedURL: URL { supportDirectory.appendingPathComponent("saved.json") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    /// Works both when launched as a real .app bundle and when the raw binary is
    /// invoked for --scan / --verify, without placing non-Mach-O files in
    /// Contents/MacOS (which would break ad-hoc signing).
    static func resourceURL(name: String, extension ext: String) -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: name, withExtension: ext) {
            candidates.append(bundled)
        }
        candidates.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).\(ext)")
        )
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        candidates.append(executableDirectory.appendingPathComponent("\(name).\(ext)"))
        candidates.append(
            executableDirectory.deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).\(ext)")
        )
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/\(name).\(ext)")
        )
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

enum Classifier {
    static let systemPrefixes = [
        "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/usr/libexec/",
        "/System/", "/var/run/com.apple.security.cryptexd"
    ]

    static let runtimeMarkers = [
        ".app/Contents/", "/.workbuddy/", "/cli/vendor/", "/plugins/cache/"
    ]

    /// Never probed with `--help`: interactive tools, pagers, editors, login clients.
    static let helpSkipNames: Set<String> = [
        "vim", "vi", "nano", "emacs", "pico", "less", "more", "man",
        "top", "htop", "btop", "watch", "screen", "tmux",
        "ssh", "telnet", "sudo", "su", "passwd", "login", "ftp", "sftp",
        "script", "bc", "lesspipe"
    ]

    /// Never executed inside the app; routed to Terminal.app instead.
    static let terminalOnlyNames: Set<String> = [
        "vim", "vi", "nano", "emacs", "pico", "less", "more",
        "top", "htop", "btop", "watch", "screen", "tmux",
        "ssh", "telnet", "sudo", "su", "passwd", "login", "ftp", "sftp",
        "photorec", "testdisk", "script", "bc"
    ]

    /// Tools that must never be launched by the whitelist runner, even via an example.
    static let dangerousNames: Set<String> = [
        "rm", "rmdir", "sudo", "dd", "diskutil", "mkfs", "newfs", "format",
        "shutdown", "reboot", "killall", "pkill", "chown", "chmod",
        "sh", "bash", "zsh", "env", "eval", "xargs", "osascript"
    ]

    static func category(for path: String) -> ToolCategory {
        let standardized = (path as NSString).standardizingPath
        if runtimeMarkers.contains(where: { standardized.contains($0) }) { return .runtime }
        if systemPrefixes.contains(where: { standardized.hasPrefix($0) }) { return .system }
        return .user
    }

    static func isDangerous(_ name: String) -> Bool {
        dangerousNames.contains(name)
    }
}
