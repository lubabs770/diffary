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
            let side = total * (model.draggedSidebarShare ?? s.sidebarSize)
            let main = VStack(spacing: 0) { topStrip(terminalColor); mainArea }
                .frame(width: horizontal ? total - side : nil, height: horizontal ? nil : total - side)
            let bar = VStack(spacing: 0) {
                if horizontal { topStrip(model.theme.sidebarBackground) }
                sidebar
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: horizontal ? side : nil, height: horizontal ? nil : side)
            let handle = SplitHandle(horizontal: horizontal) { location in
                let pos = horizontal ? location.x : location.y
                let share = s.sidebar == .left ? pos / total : (total - pos) / total
                model.draggedSidebarShare = min(max(share, 0.1), 0.9)
            }
            switch s.sidebar {
            case .right: HStack(spacing: 0) { main; handle; bar }
            case .left: HStack(spacing: 0) { bar; handle; main }
            case .bottom: VStack(spacing: 0) { main; handle; bar }
            }
        }
        .coordinateSpace(name: SplitHandle.space)
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

/// Draggable border between the terminal and the sidebar: a 1pt line with a
/// wider invisible grab area and the resize cursor.
struct SplitHandle: View {
    static let space = "diffary.panes"
    let horizontal: Bool
    let onDrag: (CGPoint) -> Void

    var body: some View {
        Divider()
            .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
            .overlay(
                Color.clear
                    .frame(width: horizontal ? 7 : nil, height: horizontal ? nil : 7)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                        .onChanged { onDrag($0.location) })
            )
            .zIndex(1)
    }
}
