import AppKit
import Combine
import DiffaryCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let launch: Launch
    var window: NSWindow?
    var terminal: TerminalView?
    var model: AppModel?
    private var titlebarSub: AnyCancellable?
    private var zoomMonitor: Any?

    init(launch: Launch) { self.launch = launch }

    func applicationDidFinishLaunching(_ note: Notification) {
        let terminal = TerminalView(workingDirectory: launch.repo)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false  // we hold it in self.window
        window.delegate = self
        self.terminal = terminal
        window.title = "diffary — \(launch.repo.lastPathComponent)"
        let model = AppModel(launch: launch)
        self.model = model
        window.contentView = NSHostingView(rootView: LayoutView(model: model, terminal: terminal))
        // Follow appearance.titlebar live (config reload).
        titlebarSub = model.$settings.map(\.titlebar).removeDuplicates()
            .sink { [weak window] show in window.map { Self.setTitlebar($0, visible: show) } }
        // Cmd-=/-/0 zoom the panels; the event still reaches the terminal,
        // whose Ghostty keybinds resize the terminal font.
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let step = Zoom.step(characters: event.charactersIgnoringModifiers ?? "",
                                    command: mods.contains(.command),
                                    otherModifiers: !mods.subtracting(.command).isEmpty) {
                model?.zoom(step)
            }
            return event
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        self.window = window
        // No NSApp.activate(): `open` activates on a normal launch, and
        // `open -g` (scripts, screenshots) must leave focus alone.
    }

    /// Hidden = no title strip; traffic lights float over the content.
    static func setTitlebar(_ window: NSWindow, visible: Bool) {
        if visible { window.styleMask.remove(.fullSizeContentView) } else { window.styleMask.insert(.fullSizeContentView) }
        window.titlebarAppearsTransparent = !visible
        window.titleVisibility = visible ? .visible : .hidden
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { terminal?.confirmClose() ?? true }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        terminal?.confirmClose() ?? true ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
