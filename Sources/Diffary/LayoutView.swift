import DiffaryCore
import SwiftUI

/// Hosts the single long-lived TerminalView (recreating it would kill the shell).
struct TerminalHost: NSViewRepresentable {
    let terminal: TerminalView
    func makeNSView(context: Context) -> NSView {
        guard let error = terminal.startupError else { return terminal }
        let label = NSTextField(labelWithString: error)
        label.alignment = .center
        return label
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Places terminal, file list and diff per [layout]. Views don't know where they are.
struct LayoutView: View {
    @ObservedObject var model: AppModel
    let terminal: TerminalView

    /// Height of the hidden title bar: the strip the traffic lights float in.
    private static let titlebarHeight: CGFloat = 28

    var body: some View {
        panes.background(Color(model.theme.background)).ignoresSafeArea()
    }

    /// With the title bar hidden, each top-edge pane gets a drag strip in its own color.
    @ViewBuilder private func topStrip(_ color: RGBA) -> some View {
        if !model.settings.titlebar {
            WindowDragArea().frame(height: Self.titlebarHeight).background(Color(color))
        }
    }

    private var terminalColor: RGBA {
        GhosttyRuntime.shared.terminalColors?.background ?? model.theme.background
    }

    private var panes: some View {
        let s = model.settings
        return GeometryReader { geo in
            let horizontal = s.sidebar != .bottom
            let total = horizontal ? geo.size.width : geo.size.height
            let side = total * s.sidebarSize
            let main = VStack(spacing: 0) { topStrip(terminalColor); mainArea }.frame(width: horizontal ? total - side : nil,
                                      height: horizontal ? nil : total - side)
            let bar = VStack(spacing: 0) {
                if horizontal { topStrip(model.theme.sidebarBackground) }
                sidebar
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: horizontal ? side : nil, height: horizontal ? nil : side)
            switch s.sidebar {
            case .right: HStack(spacing: 0) { main; Divider(); bar }
            case .left: HStack(spacing: 0) { bar; Divider(); main }
            case .bottom: VStack(spacing: 0) { main; Divider(); bar }
            }
        }
    }

    /// Terminal, unless diff_position = replace_terminal and a file is selected.
    @ViewBuilder private var mainArea: some View {
        ZStack {
            TerminalHost(terminal: terminal)
            if model.settings.diffPosition == .replaceTerminal, model.selected != nil {
                diffPane.overlay(alignment: .topTrailing) {
                    Button("Close diff (Esc)") { model.select(nil) }
                        .keyboardShortcut(.cancelAction).padding(6)
                }
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        switch model.settings.diffPosition {
        case .belowList: VSplitView { list; diffPane }
        case .besideList: HSplitView { list; diffPane }
        case .replaceTerminal: list
        }
    }

    private var list: some View {
        FileListView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diffPane: some View {
        DiffView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty strip in the terminal's color that drags the window, standing in for
/// the hidden title bar (the content views would otherwise swallow the drag).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
