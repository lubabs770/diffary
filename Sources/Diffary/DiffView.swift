import AppKit
import DiffaryCore
import Highlightr
import SwiftUI

struct DiffView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let t = model.theme
        Group {
            switch model.diff {
            case nil: placeholder(model.selected == nil ? "Select a file" : "Loading…")
            case .binary?: placeholder("Binary file")
            case .tooLarge(let n)?: placeholder("Diff too large (\(n) lines). Open it in the terminal.")
            case .empty?: placeholder("No differences with current options")
            case .text(let hunks)?:
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                            Text(hunk.header).foregroundStyle(Color(t.hunkHeader)).padding(.vertical, 2)
                            if model.settings.diffView == .unified {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in unifiedRow(line) }
                            } else {
                                ForEach(Array(hunk.sideBySideRows.enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 0) {
                                        half(row.left, number: row.left?.oldNumber)
                                        Divider()
                                        half(row.right, number: row.right?.newNumber)
                                    }
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .font(.custom(model.settings.font, size: model.settings.fontSize))
        .foregroundStyle(Color(t.foreground))
        .background(Color(t.background))
    }

    private func placeholder(_ s: String) -> some View {
        Text(s).foregroundStyle(Color(model.theme.lineNumber)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unifiedRow(_ line: DiffLine) -> some View {
        HStack(spacing: 8) {
            num(line.oldNumber); num(line.newNumber)
            Text(marker(line.kind)).foregroundStyle(Color(fg(line.kind)))
            code(line.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(bg(line.kind)))
    }

    private func half(_ line: DiffLine?, number: Int?) -> some View {
        HStack(spacing: 8) {
            num(number)
            if let line { code(line.text) } else { Text("") }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
        .background(Color(line.map { bg($0.kind) } ?? RGBA(r: 0, g: 0, b: 0, a: 0)))
    }

    private func num(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "").foregroundStyle(Color(model.theme.lineNumber))
            .frame(width: 40, alignment: .trailing)
    }

    private func code(_ text: String) -> some View {
        codeText(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private func codeText(_ text: String) -> Text {
        guard model.settings.syntaxHighlight,
              let language = SyntaxHighlighter.language(for: model.selected?.path),
              let attr = SyntaxHighlighter.shared.highlight(text, language: language, theme: model.theme),
              // \.appKit scope keeps Highlightr's NSColor foregrounds visible to SwiftUI.
              let styled = try? AttributedString(attr, including: \.appKit)
        else { return Text(text) }
        return Text(styled)
    }

    private func marker(_ k: DiffLineKind) -> String { k == .added ? "+" : k == .removed ? "-" : " " }
    private func fg(_ k: DiffLineKind) -> RGBA {
        k == .added ? model.theme.addedFg : k == .removed ? model.theme.removedFg : model.theme.lineNumber
    }
    private func bg(_ k: DiffLineKind) -> RGBA {
        k == .added ? model.theme.addedBg : k == .removed ? model.theme.removedBg : RGBA(r: 0, g: 0, b: 0, a: 0)
    }
}

/// Highlightr wrapper. Highlightr's Theme init is internal, so a custom CSS theme
/// can't be loaded. Instead we highlight with the bundled atom-one-dark and remap
/// its token colors onto the diffary theme's [syntax] colors, dropping fonts.
@MainActor
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private let highlightr: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: "atom-one-dark")
        return h
    }()

    static func language(for path: String?) -> String? {
        guard let ext = path.map({ ($0 as NSString).pathExtension.lowercased() }), !ext.isEmpty else { return nil }
        let map = ["swift": "swift", "ts": "typescript", "tsx": "typescript", "js": "javascript", "jsx": "javascript",
                   "py": "python", "rb": "ruby", "go": "go", "rs": "rust", "zig": "zig", "c": "c", "h": "c",
                   "cpp": "cpp", "m": "objectivec", "java": "java", "kt": "kotlin", "sh": "bash", "zsh": "bash",
                   "json": "json", "yml": "yaml", "yaml": "yaml", "toml": "ini", "md": "markdown",
                   "html": "xml", "css": "css", "sql": "sql"]
        return map[ext]
    }

    // atom-one-dark token color (rgb hex) -> diffary [syntax] key; anything else is plain foreground.
    private static let roles = ["c678dd": "keyword", "56b6c2": "keyword", "98c379": "string", "5c6370": "comment",
                                "d19a66": "number", "e6c07b": "type", "61aeee": "type"]

    func highlight(_ code: String, language: String, theme: DiffaryCore.Theme) -> NSAttributedString? {
        guard let src = highlightr?.highlight(code, as: language, fastRender: true) else { return nil }
        let out = NSMutableAttributedString(string: src.string)
        let base = NSColor(theme.foreground)
        out.addAttribute(.foregroundColor, value: base, range: NSRange(location: 0, length: out.length))
        src.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: src.length)) { value, range, _ in
            guard let c = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02x%02x%02x", Int((c.redComponent * 255).rounded()),
                             Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            if let key = Self.roles[hex], let color = theme.syntax[key] {
                out.addAttribute(.foregroundColor, value: NSColor(color), range: range)
            }
        }
        return out
    }
}
