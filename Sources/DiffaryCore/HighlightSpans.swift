import Foundation

/// Parses highlight.js HTML (`<span class="hljs-…">…</span>` plus entities) into plain
/// text and colored ranges (UTF-16 offsets). Inner spans come after outer ones, so
/// applying them in order lets the innermost win. Unknown classes produce no span.
public enum HighlightSpans {
    public struct Span: Equatable, Sendable {
        public let range: NSRange
        public let key: String
    }

    /// Theme [syntax] key for an hljs class list, e.g. "hljs-title class_" -> "type".
    public static func key(forClasses classes: String) -> String? {
        let names = Set(classes.split(separator: " ").map { $0.hasPrefix("hljs-") ? String($0.dropFirst(5)) : String($0) })
        for (key, wanted) in [("keyword", ["keyword", "built_in", "literal"]), ("string", ["string", "regexp"]),
                              ("comment", ["comment", "quote"]), ("number", ["number"]),
                              ("type", ["type", "class", "class_"])] where !names.isDisjoint(with: wanted) {
            return key
        }
        return nil
    }

    private static let entities = ["&lt;": "<", "&gt;": ">", "&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'"]

    public static func parse(_ html: String) -> (text: String, spans: [Span]) {
        var text = "", spans: [Span] = []
        var open: [(start: Int, key: String?, index: Int?)] = []
        var length = 0  // UTF-16 length of text
        var i = html.startIndex
        func append(_ s: String) { text += s; length += s.utf16.count }
        while i < html.endIndex {
            let rest = html[i...]
            if rest.hasPrefix("<span") , let close = rest.firstIndex(of: ">") {
                let tag = rest[..<close]
                var key: String?
                if let r = tag.range(of: "class=\"") , let end = tag[r.upperBound...].firstIndex(of: "\"") {
                    key = Self.key(forClasses: String(tag[r.upperBound..<end]))
                }
                var index: Int?
                if let key { spans.append(Span(range: NSRange(location: length, length: 0), key: key)); index = spans.count - 1 }
                open.append((length, key, index))
                i = html.index(after: close)
            } else if rest.hasPrefix("</span>") {
                if let o = open.popLast(), let idx = o.index {
                    spans[idx] = Span(range: NSRange(location: o.start, length: length - o.start), key: o.key!)
                }
                i = html.index(i, offsetBy: 7)
            } else if rest.first == "&", let (e, v) = entities.first(where: { rest.hasPrefix($0.key) }) {
                append(v)
                i = html.index(i, offsetBy: e.count)
            } else {
                append(String(html[i]))
                i = html.index(after: i)
            }
        }
        return (text, spans.filter { $0.range.length > 0 })
    }
}
