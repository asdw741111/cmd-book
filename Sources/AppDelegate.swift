import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        model.load()

        let hosting = NSHostingController(
            rootView: ContentView().environmentObject(model)
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdBook — 本机命令行工具手册"
        window.contentViewController = hosting
        window.setFrameAutosaveName("CmdBookMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if model.snapshot == nil { model.rescan() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "关于 CmdBook",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            NSMenuItem(title: "退出 CmdBook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        let toolsItem = NSMenuItem()
        mainMenu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "工具")
        toolsItem.submenu = toolsMenu

        let find = NSMenuItem(title: "搜索工具", action: #selector(focusSearch), keyEquivalent: "f")
        find.keyEquivalentModifierMask = [.command]
        find.target = self
        toolsMenu.addItem(find)

        let rescan = NSMenuItem(title: "重新扫描", action: #selector(rescanTools), keyEquivalent: "r")
        rescan.keyEquivalentModifierMask = [.command]
        rescan.target = self
        toolsMenu.addItem(rescan)

        let newExampleItem = NSMenuItem(
            title: "新建示例", action: #selector(createExample), keyEquivalent: "n"
        )
        newExampleItem.keyEquivalentModifierMask = [.command]
        newExampleItem.target = self
        toolsMenu.addItem(newExampleItem)

        toolsMenu.addItem(NSMenuItem.separator())

        let reload = NSMenuItem(
            title: "重新载入资源", action: #selector(reloadResources), keyEquivalent: "r"
        )
        reload.keyEquivalentModifierMask = [.command, .option]
        reload.target = self
        toolsMenu.addItem(reload)

        let openDirectory = NSMenuItem(
            title: "打开用户资源目录", action: #selector(openUserResourcesDirectory),
            keyEquivalent: ""
        )
        openDirectory.target = self
        toolsMenu.addItem(openDirectory)

        let clearHistory = NSMenuItem(
            title: "清空运行历史", action: #selector(clearRunHistory), keyEquivalent: ""
        )
        clearHistory.target = self
        toolsMenu.addItem(clearHistory)

        NSApp.mainMenu = mainMenu
    }

    @objc private func focusSearch() { model.focusSearch() }
    @objc private func rescanTools() { model.rescan() }
    @objc private func reloadResources() { model.reloadResources() }
    @objc private func openUserResourcesDirectory() { model.openUserResourcesDirectory() }
    @objc private func createExample() { model.showingExampleEditor = true }
    @objc private func clearRunHistory() { model.clearHistory() }
}
