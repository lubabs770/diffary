import AppKit
import GhosttyKit

/// Owns the one ghostty_app_t. Terminal fonts, colors and keys come from
/// Ghostty's own config files (~/.config/ghostty/config), not from diffary.
@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()
    private(set) var app: ghostty_app_t?
    private(set) var error: String?

    private init() {
        // ghostty_init may keep argv, so pass the process's own (lives forever).
        // argc 1: only the program name, so diffary's own flags aren't parsed
        // as Ghostty CLI actions.
        guard ghostty_init(1, CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else { error = "ghostty_init failed"; return }
        guard let config = ghostty_config_new() else { error = "ghostty_config_new failed"; return }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        var runtime = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GhosttyRuntime.shared.tick() } }
            },
            action_cb: { _, _, action in
                // Tabs/splits/titles: not ours. Quit (Cmd-Q keybind) is.
                guard action.tag == GHOSTTY_ACTION_QUIT else { return false }
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return true
            },
            read_clipboard_cb: { userdata, _, state, mimes, count, _ in
                TerminalView.readClipboard(userdata, state: state, mimes: mimes, count: count)
            },
            confirm_read_clipboard_cb: { userdata, confirm, state, request in
                TerminalView.confirmReadClipboard(userdata, confirm: confirm, state: state, request: request)
            },
            write_clipboard_cb: { _, _, contents, count, confirm in
                GhosttyRuntime.writeClipboard(contents, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in
                guard let userdata else { return }
                let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    if processAlive, !TerminalView.ask("A process is still running. Close?",
                                                       "Closing ends it.", ok: "Close") { return }
                    view.window?.close()
                }
            })
        guard let app = ghostty_app_new(&runtime, config) else { error = "ghostty_app_new failed"; return }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
    }

    func tick() {
        if let app { ghostty_app_tick(app) }
    }

    /// `confirm`: Ghostty's policy wants the user to OK this write (e.g. OSC 52).
    nonisolated static func writeClipboard(_ contents: UnsafePointer<ghostty_clipboard_content_s>?,
                                           count: Int, confirm: Bool) {
        guard let contents else { return }
        for i in 0..<count where String(cString: contents[i].mime) == "text/plain" {
            let data = Data(bytes: contents[i].data, count: contents[i].len)
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                if confirm, !TerminalView.ask("A program wants to write to your clipboard",
                                              String(text.prefix(500)), ok: "Allow") { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return
        }
    }
}
