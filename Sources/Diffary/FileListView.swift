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
                List(files, selection: Binding(
                    get: { model.selected?.path },
                    set: { path in model.select(files.first { $0.path == path }) }
                )) { file in
                    row(file, t).tag(file.path)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .font(.custom(model.settings.font, size: model.settings.fontSize))
        .foregroundStyle(Color(t.foreground))
        .background(Color(t.sidebarBackground))
    }

    private func row(_ f: FileChange, _ t: Theme) -> some View {
        HStack(spacing: 6) {
            Text(f.status == .untracked ? "A" : f.status.rawValue)
                .foregroundStyle(Color(color(f.status, t))).frame(width: 14)
            Text(f.oldPath.map { "\($0) → \(f.path)" } ?? f.path).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let a = f.additions { Text("+\(a)").foregroundStyle(Color(t.addedFg)) }
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
