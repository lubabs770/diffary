import AppKit
import GhosttyKit

/// NSView hosting one Ghostty surface. Knows nothing about git.
final class TerminalView: NSView {
    private(set) var surface: ghostty_surface_t?
    private(set) var startupError: String?
    /// Set once the user has OK'd ending the shell, so close and quit don't ask twice.
    var closeConfirmed = false

    /// Asks before ending a running process. True when it's fine to close.
    func confirmClose() -> Bool {
        if closeConfirmed { return true }
        guard let surface, ghostty_surface_needs_confirm_quit(surface) else { return true }
        closeConfirmed = Self.ask("A process is still running. Close?", "Closing ends it.", ok: "Close")
        return closeConfirmed
    }

    init(workingDirectory: URL) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        guard let app = GhosttyRuntime.shared.app else {
            startupError = GhosttyRuntime.shared.error ?? "Ghostty failed to start"
            return
        }
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()))
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        surface = workingDirectory.path.withCString { dir in
            cfg.working_directory = dir
            return ghostty_surface_new(app, &cfg)
        }
        if surface == nil { startupError = "ghostty_surface_new failed" }
        // Ghostty hands back a +1 CTFont copy.
        if let surface, let raw = ghostty_surface_quicklook_font(surface) {
            let font = Unmanaged<CTFont>.fromOpaque(raw).takeRetainedValue()
            GhosttyRuntime.shared.terminalFontName = CTFontCopyPostScriptName(font) as String
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { if let surface { ghostty_surface_free(surface) } }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return true
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return true
    }

    // MARK: Size

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        ghostty_surface_set_content_scale(surface, scale, scale)
        updateSize()
    }

    private func updateSize() {
        guard let surface else { return }
        let px = convertToBacking(bounds.size)
        ghostty_surface_set_size(surface, UInt32(max(px.width, 1)), UInt32(max(px.height, 1)))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) { sendKey(event, event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS) }
    override func keyUp(with event: NSEvent) { sendKey(event, GHOSTTY_ACTION_RELEASE) }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        var key = keyEvent(event, GHOSTTY_ACTION_PRESS)
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }

    /// Let Ghostty see Cmd-shortcuts (copy/paste/etc. come from its keybinds).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else { return false }
        // Only claim keys Ghostty consumed, so unbound Cmd keys reach AppKit.
        return sendKey(event, event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
    }

    // ponytail: no IME/dead-key composition (interpretKeyEvents path). Port
    // keyDown + NSTextInputClient from SurfaceView_AppKit.swift if needed.
    @discardableResult
    private func sendKey(_ event: NSEvent, _ action: ghostty_input_action_e) -> Bool {
        guard let surface else { return false }
        var key = keyEvent(event, action)
        let text = action == GHOSTTY_ACTION_RELEASE ? nil : Self.ghosttyText(event)
        guard let text else { return ghostty_surface_key(surface, key) }
        return text.withCString { ptr in
            key.text = ptr
            return ghostty_surface_key(surface, key)
        }
    }

    private func keyEvent(_ event: NSEvent, _ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = Self.mods(event.modifierFlags)
        key.consumed_mods = Self.mods(event.modifierFlags.subtracting([.control, .command]))
        key.composing = false
        if event.type == .keyDown || event.type == .keyUp,
           let scalar = event.characters(byApplyingModifiers: [])?.unicodeScalars.first {
            key.unshifted_codepoint = scalar.value
        }
        return key
    }

    /// Same rules as Ghostty's NSEvent.ghosttyCharacters.
    private static func ghosttyText(_ event: NSEvent) -> String? {
        guard let chars = event.characters else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 { return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control)) }
            if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        }
        return chars
    }

    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); button(e, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT) }
    override func mouseUp(with e: NSEvent) { button(e, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT) }
    override func rightMouseDown(with e: NSEvent) { button(e, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT) }
    override func rightMouseUp(with e: NSEvent) { button(e, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT) }
    override func otherMouseDown(with e: NSEvent) { button(e, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE) }
    override func otherMouseUp(with e: NSEvent) { button(e, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE) }
    override func mouseMoved(with e: NSEvent) { position(e) }
    override func mouseDragged(with e: NSEvent) { position(e) }
    override func rightMouseDragged(with e: NSEvent) { position(e) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func button(_ e: NSEvent, _ state: ghostty_input_mouse_state_e, _ b: ghostty_input_mouse_button_e) {
        guard let surface else { return }
        position(e)
        _ = ghostty_surface_mouse_button(surface, state, b, Self.mods(e.modifierFlags))
    }

    private func position(_ e: NSEvent) {
        guard let surface else { return }
        let p = convert(e.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, p.x, bounds.height - p.y, Self.mods(e.modifierFlags))
    }

    override func scrollWheel(with e: NSEvent) {
        guard let surface else { return }
        var x = e.scrollingDeltaX, y = e.scrollingDeltaY
        if e.hasPreciseScrollingDeltas { x *= 2; y *= 2 }
        // Bit 0 of scroll mods = precision (trackpad) scrolling.
        ghostty_surface_mouse_scroll(surface, x, y, e.hasPreciseScrollingDeltas ? 1 : 0)
    }

    // MARK: Clipboard (called from GhosttyRuntime's C callbacks)

    static func readClipboard(_ userdata: UnsafeMutableRawPointer?, state: UnsafeMutableRawPointer,
                              mimes: UnsafePointer<UnsafePointer<CChar>>, count: Int) -> ghostty_clipboard_read_result_e {
        guard let userdata else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
        let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
        let wantsText = (0..<count).contains { String(cString: mimes[$0]) == "text/plain" }
        guard wantsText, let text = NSPasteboard.general.string(forType: .string) else {
            return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
        }
        complete(surface, state: state, text: text, confirmed: false)
        return GHOSTTY_CLIPBOARD_READ_STARTED
    }

    /// Ghostty asks this before an unsafe paste (e.g. contains newlines) or a
    /// program's clipboard read (OSC 52 / kitty). Keep that protection: ask.
    static func confirmReadClipboard(_ userdata: UnsafeMutableRawPointer?,
                                     confirm: UnsafePointer<ghostty_clipboard_confirm_s>,
                                     state: UnsafeMutableRawPointer,
                                     request: ghostty_clipboard_request_e) {
        // No view/surface means nothing to complete or deny against.
        guard let userdata else { return }
        let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return }
        let c = confirm.pointee
        var text: String?
        if let contents = c.contents {
            for i in 0..<c.contents_len where String(cString: contents[i].mime) == "text/plain" {
                text = String(decoding: Data(bytes: contents[i].data, count: contents[i].len), as: UTF8.self)
            }
        }
        let title: String, ok: String
        switch request {
        case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
            (title, ok) = ("Paste into terminal?", "Paste")
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ, GHOSTTY_CLIPBOARD_REQUEST_KITTY_READ:
            let who = c.name.map { " (\(String(cString: $0)))" } ?? ""
            (title, ok) = ("A program\(who) wants to read your clipboard", "Allow")
        default:
            ghostty_surface_deny_clipboard_request(surface, state); return
        }
        guard let text else { ghostty_surface_deny_clipboard_request(surface, state); return }
        DispatchQueue.main.async {
            let allowed = ask(title, String(text.prefix(500)), ok: ok)
            // The surface may have closed while the alert was up.
            guard let surface = view.surface else { return }
            if allowed {
                complete(surface, state: state, text: text, confirmed: true)
            } else {
                ghostty_surface_deny_clipboard_request(surface, state)
            }
        }
    }

    /// Modal yes/no. Main thread only.
    static func ask(_ title: String, _ detail: String, ok: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func complete(_ surface: ghostty_surface_t, state: UnsafeMutableRawPointer, text: String, confirmed: Bool) {
        "text/plain".withCString { mime in
            text.withCString { data in
                var content = ghostty_clipboard_content_s(mime: mime, data: data, len: strlen(data))
                withUnsafePointer(to: &content) { contentPtr in
                    var done = ghostty_clipboard_complete_s(
                        contents: contentPtr, contents_len: 1,
                        available: nil, available_len: 0,
                        confirmed: confirmed, remember: false)
                    ghostty_surface_complete_clipboard_request(surface, &done, state)
                }
            }
        }
    }
}
