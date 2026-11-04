import AppKit
import DiffaryCore
import GhosttyKit

/// Owns the one ghostty_app_t. Terminal fonts, colors and keys come from
/// Ghostty's own config files (~/.config/ghostty/config), not from diffary.
@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()
    private(set) var app: ghostty_app_t?
    private(set) var error: String?
    /// Kept for reading values back (colors); never freed, lives as long as the app.
    private var config: ghostty_config_t?
    /// PostScript name of the terminal's font, set once the first surface exists.
    var terminalFontName: String?

    private var configWatcher: FileWatcher?

    private init() {
        Self.useGhosttyAppResources()
        // ghostty_init may keep argv, so pass the process's own (lives forever).
        // argc 1: only the program name, so diffary's own flags aren't parsed
        // as Ghostty CLI actions.
        guard ghostty_init(1, CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else { error = "ghostty_init failed"; return }
        guard let config = Self.loadConfig() else { error = "ghostty_config_new failed"; return }
        self.config = config

        var runtime = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GhosttyRuntime.shared.tick() } }
            },
            action_cb: { _, _, action in
                // Tabs/splits/titles: not ours. Quit and config reload are.
                switch action.tag {
                case GHOSTTY_ACTION_QUIT:
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                    return true
                case GHOSTTY_ACTION_RELOAD_CONFIG:
                    let soft = action.action.reload_config.soft
                    DispatchQueue.main.async { MainActor.assumeIsolated { GhosttyRuntime.shared.reloadConfig(soft: soft) } }
                    return true
                default:
                    return false
                }
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
                    view.closeConfirmed = true  // the quit that follows mustn't ask again
                    view.window?.close()
                }
            })
        guard let app = ghostty_app_new(&runtime, config) else { error = "ghostty_app_new failed"; return }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)

        // Ghostty itself only reloads on its keybind; diffary also reloads when
        // the config files are saved, since that keypress never reaches us.
        let dirs = Self.configDirs().filter { FileManager.default.fileExists(atPath: $0.path) }
        if !dirs.isEmpty {
            configWatcher = FileWatcher(paths: dirs, debounce: 0.3) {
                DispatchQueue.main.async { MainActor.assumeIsolated { GhosttyRuntime.shared.reloadConfig() } }
            }
            configWatcher?.start()
        }
    }

    static let configReloaded = Notification.Name("diffary.ghosttyConfigReloaded")

    /// Re-read Ghostty's config into the running terminal, then tell diffary's
    /// panels (colors, font) to follow.
    func reloadConfig(soft: Bool = false) {
        guard let app else { return }
        if !soft, let fresh = Self.loadConfig() {
            // ponytail: the previous config is leaked, not freed; reloads are rare
            // and Ghostty may still reference it during the swap.
            config = fresh
        }
        guard let config else { return }
        ghostty_app_update_config(app, config)
        if !soft { Self.reloadGhosttyApp() }
        // Surfaces apply the new font a beat later; read it back after that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: Self.configReloaded, object: nil)
        }
    }

    /// Keep Ghostty.app in step: a reload here reloads every Ghostty window, as
    /// Cmd-Shift-, does there. Only if Ghostty is already running (never launch
    /// it), off the main thread, and fire-and-forget. macOS asks the user once
    /// to allow Diffary to control Ghostty.
    private static func reloadGhosttyApp() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").isEmpty
        else { return }
        let script = """
            tell application id "com.mitchellh.ghostty"
              if (count of windows) > 0 then perform action "reload_config" on focused terminal of selected tab of front window
            end tell
            """
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    private static func loadConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        return config
    }

    /// Where Ghostty reads its config on macOS.
    private static func configDirs() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let xdg = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.config"
        return [URL(fileURLWithPath: xdg).appendingPathComponent("ghostty"),
                URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")]
    }

    /// Built-in themes (`theme = TokyoNight`) and shell integration live in
    /// Ghostty.app's resources; point libghostty at them unless the user did.
    private static func useGhosttyAppResources() {
        guard ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] == nil,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
        else { return }
        let dir = app.appendingPathComponent("Contents/Resources/ghostty")
        if FileManager.default.fileExists(atPath: dir.path) { setenv("GHOSTTY_RESOURCES_DIR", dir.path, 1) }
    }

    /// The terminal's background/foreground/selection from Ghostty's config.
    var terminalColors: TerminalColors? {
        guard let bg = color("background"), let fg = color("foreground") else { return nil }
        return TerminalColors(background: bg, foreground: fg, selection: color("selection-background"))
    }

    private func color(_ key: String) -> RGBA? {
        guard let config else { return nil }
        var c = ghostty_config_color_s()
        guard ghostty_config_get(config, &c, key, UInt(key.utf8.count)) else { return nil }
        return RGBA(r: Double(c.r) / 255, g: Double(c.g) / 255, b: Double(c.b) / 255, a: 1)
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
