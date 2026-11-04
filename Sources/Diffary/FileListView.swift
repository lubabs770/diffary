import DiffaryCore
import SwiftUI

struct FileListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let t = model.theme
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.warnings, id: \.self) { w in
                Text("⚠ \(w)").font(.caption).foregroundStyle(Color(t.statusModified))
                    .padding(.horizontal, 8).padding(.vertical, 2)
            }
            if let error = model.gitError {
                Text(error).font(.caption).foregroundStyle(Color(t.statusDeleted)).padding(8)
            }
            if let files = model.changes?.files {
                if files.isEmpty {
                    Text("No changes vs \(model.settings.baseBranch)").foregroundStyle(Color(t.lineNumber)).padding(8)
                }
                // Plain rows rather than List: the system selection highlight ignores the theme.
                let scroll = model.settings.longPaths == .scroll
                GeometryReader { geo in
                    ScrollView(scroll ? [.vertical, .horizontal] : .vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(files) { file in
                                row(file, t, scroll: scroll)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(model.selected?.path == file.path ? Color(t.selection) : .clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.select(file) }
                            }
                        }
                        // Scrolling: every row as wide as the longest one (measured, since a
                        // lazy stack never sizes rows it hasn't drawn), at least the pane.
                        .frame(width: scroll ? max(geo.size.width, rowWidth(files)) : nil, alignment: .leading)
                    }
                }
                // Never ask the split view for the list's full content width.
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
            }
        }
        .font(Font(monoFont(name: model.settings.font, size: model.panelFontSize) as CTFont))
        .foregroundStyle(Color(t.foreground))
        .background(Color(t.sidebarBackground))
    }

    /// Width of the widest row: path text plus padding, status column, gaps and counts.
    private func rowWidth(_ files: [FileChange]) -> CGFloat {
        let font = monoFont(name: model.settings.font, size: model.panelFontSize)
        let longest = files.map { f in f.oldPath.map { "\($0) → \(f.path)" } ?? f.path }
            .max { $0.count < $1.count } ?? ""
        let text = (longest as NSString).size(withAttributes: [.font: font]).width
        let counts = ("+99999 -99999" as NSString).size(withAttributes: [.font: font]).width
        return ceil(16 + 14 + 3 * 6 + text + counts)
    }

    private func row(_ f: FileChange, _ t: Theme, scroll: Bool) -> some View {
        HStack(spacing: 6) {
            Text(f.status == .untracked ? "A" : f.status.rawValue)
                .foregroundStyle(Color(color(f.status, t))).frame(width: 14)
            Text(f.oldPath.map { "\($0) → \(f.path)" } ?? f.path).lineLimit(1)
                .truncationMode(.head)  // keep the file name visible
                .fixedSize(horizontal: scroll, vertical: false)  // scroll: never truncate
            Spacer()
            if let a = f.additions, a > 0 { Text("+\(a)").foregroundStyle(Color(t.addedFg)) }
            if let d = f.deletions, d > 0 { Text("-\(d)").foregroundStyle(Color(t.removedFg)) }
        }
    }

    private func color(_ s: ChangeStatus, _ t: Theme) -> RGBA {
        switch s {
        case .added, .untracked: t.statusAdded
        case .modified: t.statusModified
        case .deleted: t.statusDeleted
        case .renamed: t.statusRenamed
        }
    }
}
