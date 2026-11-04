import AppKit
import DiffaryCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let launch: Launch
    var window: NSWindow?
    var model: AppModel?

    init(launch: Launch) { self.launch = launch }

    func applicationDidFinishLaunching(_ note: Notification) {
        let terminal = TerminalView(workingDirectory: launch.repo)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false  // we hold it in self.window
        window.title = "diffary — \(launch.repo.lastPathComponent)"
        let model = AppModel(launch: launch)
        self.model = model
        window.contentView = NSHostingView(rootView: LayoutView(model: model, terminal: terminal))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        self.window = window
        // No NSApp.activate(): `open` activates on a normal launch, and
        // `open -g` (scripts, screenshots) must leave focus alone.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
