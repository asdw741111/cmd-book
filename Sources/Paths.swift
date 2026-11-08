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
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory, withIntermediateDirectories: true
            )
        } catch {
            AppLog.store.error(
                "无法创建应用数据目录: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Works both when launched as a real .app bundle and when the raw binary is
    /// invoked for --scan / --verify, without placing non-Mach-O files in
    /// Contents/MacOS (which would break ad-hoc signing).
    /// Location of a user-authored resource overlay. These files are outside
    /// the signed .app bundle, so editing them never invalidates code signing.
    static func userResourceURL(name: String, extension ext: String) -> URL {
        supportDirectory.appendingPathComponent("\(name).\(ext)")
    }

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

    /// Even a real binary (e.g. Homebrew's) can launch a GUI, request keychain
    /// access or trigger a system install dialog. Never execute these.
    static let guiPromptNames: Set<String> = [
        "open", "osascript", "security", "codesign", "screencapture", "qlmanage",
        "java", "java_home", "xcrun", "xcodebuild", "xcode-select",
        "launchctl", "networksetup", "systemsetup", "softwareupdate", "installer",
        "ssh-add", "git-credential-osxkeychain", "defaults", "diskutil", "hdiutil"
    ]

    /// Apple's `/usr/bin` shims (git, clang, java, python3, make ...) pop a
    /// "Command Line Developer Tools" / Java / keychain dialog even when invoked
    /// with `--help`. System tools are therefore documented from `man`/`whatis`
    /// only; their binaries are never executed during a scan.
    static func shouldSkipBinaryProbe(name: String, path: String) -> Bool {
        let toolCategory = category(for: path)
        return helpSkipNames.contains(name)
            || guiPromptNames.contains(name)
            || toolCategory == .runtime
            || toolCategory == .system
    }

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
