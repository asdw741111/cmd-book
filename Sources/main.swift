import AppKit
import Foundation
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())

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
        Headless.scan(limit: limit)
    }
    exit(exitCode)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
