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
        // ghostty_init wants argv; give it only a program name so diffary's
        // own flags aren't parsed as Ghostty CLI actions.
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup("diffary"), nil]
        guard ghostty_init(1, &argv) == GHOSTTY_SUCCESS else { error = "ghostty_init failed"; return }
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
            action_cb: { _, _, _ in false },  // tabs/splits/titles: not ours
            read_clipboard_cb: { userdata, _, state, mimes, count, _ in
                TerminalView.readClipboard(userdata, state: state, mimes: mimes, count: count)
            },
            confirm_read_clipboard_cb: { userdata, confirm, state, _ in
                TerminalView.confirmReadClipboard(userdata, confirm: confirm, state: state)
            },
            write_clipboard_cb: { _, _, contents, count, _ in
                GhosttyRuntime.writeClipboard(contents, count: count)
            },
            close_surface_cb: { userdata, _ in
                guard let userdata else { return }
                let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async { view.window?.close() }
            })
        guard let app = ghostty_app_new(&runtime, config) else { error = "ghostty_app_new failed"; return }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
    }

    func tick() {
        if let app { ghostty_app_tick(app) }
    }

    nonisolated static func writeClipboard(_ contents: UnsafePointer<ghostty_clipboard_content_s>?, count: Int) {
        guard let contents else { return }
        for i in 0..<count where String(cString: contents[i].mime) == "text/plain" {
            let data = Data(bytes: contents[i].data, count: contents[i].len)
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return
        }
    }
}
