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

    var body: some View {
        let s = model.settings
        GeometryReader { geo in
            let horizontal = s.sidebar != .bottom
            let total = horizontal ? geo.size.width : geo.size.height
            let side = total * s.sidebarSize
            let main = mainArea.frame(width: horizontal ? total - side : nil,
                                      height: horizontal ? nil : total - side)
            let bar = sidebar.frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: horizontal ? side : nil, height: horizontal ? nil : side)
            switch s.sidebar {
            case .right: HStack(spacing: 0) { main; Divider(); bar }
            case .left: HStack(spacing: 0) { bar; Divider(); main }
            case .bottom: VStack(spacing: 0) { main; Divider(); bar }
            }
        }
        .background(Color(model.theme.background))
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
