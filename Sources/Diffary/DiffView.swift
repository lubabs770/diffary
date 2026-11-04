import AppKit
import DiffaryCore
import JavaScriptCore
import SwiftUI

/// The configured font, or the system monospace font when that family isn't installed.
func monoFont(name: String, size: Double) -> NSFont {
    NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}

struct DiffView: View {
    @ObservedObject var model: AppModel
    private let numW: CGFloat = 40, markerW: CGFloat = 10, gap: CGFloat = 8, pad: CGFloat = 6

    var body: some View {
        let t = model.theme
        let nsFont = monoFont(name: model.settings.font, size: model.settings.fontSize)
        Group {
            switch model.diff {
            case nil: placeholder(model.selected == nil ? "Select a file" : "Loading…")
            case .binary?: placeholder("Binary file")
            case .tooLarge(let n)?: placeholder("Diff too large (\(n) lines). Open it in the terminal.")
            case .empty?: placeholder("No differences with current options")
            case .text(let hunks)?:
                GeometryReader { geo in
                    let width = contentWidth(hunks, nsFont, viewport: geo.size.width)
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
                        .padding(pad)
                        .frame(width: width, alignment: .leading)
                    }
                }
            }
        }
        .font(Font(nsFont as CTFont))
        .foregroundStyle(Color(t.foreground))
        .background(Color(t.background))
    }

    /// Every row is as wide as the viewport or the longest line, whichever is larger.
    private func contentWidth(_ hunks: [Hunk], _ font: NSFont, viewport: CGFloat) -> CGFloat {
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        let chars = CGFloat(hunks.flatMap(\.lines).map { $0.text.count }.max() ?? 0)
        let text = chars * advance
        if model.settings.diffView == .unified {
            return max(viewport, 2 * pad + 2 * numW + markerW + 3 * gap + text)
        }
        let half = max((viewport - 2 * pad - 1) / 2, numW + gap + text)
        return 2 * pad + 2 * half + 1
    }

    private func placeholder(_ s: String) -> some View {
        Text(s).foregroundStyle(Color(model.theme.lineNumber)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unifiedRow(_ line: DiffLine) -> some View {
        HStack(spacing: gap) {
            num(line.oldNumber); num(line.newNumber)
            Text(marker(line.kind)).foregroundStyle(Color(fg(line.kind)))
                .frame(width: markerW).fixedSize().layoutPriority(1)
            code(line.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(bg(line.kind)))
    }

    private func half(_ line: DiffLine?, number: Int?) -> some View {
        HStack(spacing: gap) {
            num(number)
            if let line { code(line.text) } else { Text("") }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(line.map { bg($0.kind) } ?? RGBA(r: 0, g: 0, b: 0, a: 0)))
    }

    private func num(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "").foregroundStyle(Color(model.theme.lineNumber))
            .frame(width: numW, alignment: .trailing).fixedSize().layoutPriority(1)
    }

    private func code(_ text: String) -> some View {
        codeText(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private func codeText(_ text: String) -> Text {
        guard model.settings.syntaxHighlight,
              let language = SyntaxHighlighter.language(for: model.selected?.path),
              let styled = SyntaxHighlighter.shared.highlight(text, language: language, theme: model.theme)
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

/// highlight.js (the copy shipped in Highlightr's resource bundle) run in JavaScriptCore.
/// Its HTML classes map to the diffary theme's [syntax] colors.
@MainActor
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private let fn: JSValue? = {
        let dirs = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        guard let path = dirs.compactMap({ Bundle(url: $0.appendingPathComponent("Highlightr_Highlightr.bundle")) })
                  .compactMap({ $0.path(forResource: "highlight.min", ofType: "js") }).first,
              let js = try? String(contentsOfFile: path, encoding: .utf8),
              let ctx = JSContext() else { return nil }
        ctx.evaluateScript(js)
        return ctx.evaluateScript("(function(c,l){return hljs.highlight(c,{language:l,ignoreIllegals:true}).value})")
    }()
    private var cache: [String: AttributedString] = [:]
    private var themeKey = ""

    static func language(for path: String?) -> String? {
        guard let ext = path.map({ ($0 as NSString).pathExtension.lowercased() }), !ext.isEmpty else { return nil }
        let map = ["swift": "swift", "ts": "typescript", "tsx": "typescript", "js": "javascript", "jsx": "javascript",
                   "py": "python", "rb": "ruby", "go": "go", "rs": "rust", "zig": "zig", "c": "c", "h": "c",
                   "cpp": "cpp", "m": "objectivec", "java": "java", "kt": "kotlin", "sh": "bash", "zsh": "bash",
                   "json": "json", "yml": "yaml", "yaml": "yaml", "toml": "ini", "md": "markdown",
                   "html": "xml", "css": "css", "sql": "sql"]
        return map[ext]
    }

    func highlight(_ code: String, language: String, theme: DiffaryCore.Theme) -> AttributedString? {
        let key = theme.syntax.map { "\($0.key)\($0.value.hex)" }.sorted().joined() + theme.foreground.hex
        if key != themeKey { themeKey = key; cache.removeAll() }
        let ck = language + "\0" + code
        if let hit = cache[ck] { return hit }
        guard let html = fn?.call(withArguments: [code, language]), html.isString else { return nil }
        let (text, spans) = HighlightSpans.parse(html.toString() ?? "")
        let out = NSMutableAttributedString(string: text)
        out.addAttribute(.foregroundColor, value: NSColor(theme.foreground), range: NSRange(location: 0, length: out.length))
        for span in spans {
            if let c = theme.syntax[span.key] { out.addAttribute(.foregroundColor, value: NSColor(c), range: span.range) }
        }
        // \.appKit scope keeps the NSColor foregrounds visible to SwiftUI.
        guard let styled = try? AttributedString(out, including: \.appKit) else { return nil }
        if cache.count > 5000 { cache.removeAll() }
        cache[ck] = styled
        return styled
    }
}
