import OSLog

/// Unified logging. Filter in Console.app by subsystem `local.cmdbook.macos`.
/// Replaces the silent `try?` failures that made resource/snapshot problems
/// impossible to diagnose from the GUI.
enum AppLog {
    static let subsystem = "local.cmdbook.macos"
    static let resources = Logger(subsystem: subsystem, category: "resources")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let runner = Logger(subsystem: subsystem, category: "runner")
    static let backup = Logger(subsystem: subsystem, category: "backup")
}
