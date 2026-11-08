import AppKit
import Foundation
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--resources") {
    Headless.resources()
    exit(0)
}

if arguments.contains("--favorites") {
    exit(Headless.favorites())
}

if arguments.contains("--bench") {
    exit(Headless.bench())
}

if let searchIndex = arguments.firstIndex(of: "--search"),
   searchIndex + 1 < arguments.count {
    exit(Headless.search(query: arguments[searchIndex + 1]))
}

if arguments.contains("--runprobe") {
    exit(Headless.runProbe())
}

if arguments.contains("--scan") || arguments.contains("--verify") {
    var exitCode: Int32 = 0
    if arguments.contains("--verify") {
        exitCode = Headless.verify()
    }
    if arguments.contains("--scan") {
        var limit: Int? = nil
        if let index = arguments.firstIndex(of: "--limit"), index + 1 < arguments.count {
            limit = Int(arguments[index + 1])
        }
        Headless.scan(limit: limit, forceFull: arguments.contains("--full"))
    }
    exit(exitCode)
}

if let exportIndex = arguments.firstIndex(of: "--export"),
   exportIndex + 1 < arguments.count {
    exit(Headless.exportBackup(to: arguments[exportIndex + 1]))
}

if let importIndex = arguments.firstIndex(of: "--import"),
   importIndex + 1 < arguments.count {
    exit(Headless.importBackup(from: arguments[importIndex + 1]))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
