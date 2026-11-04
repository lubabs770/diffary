import Foundation
import Testing
@testable import DiffaryCore

@Suite struct HighlightSpansTests {
    @Test func nestingKeepsInnerAfterOuter() {
        let r = HighlightSpans.parse(#"<span class="hljs-string">"a<span class="hljs-number">1</span>"</span>"#)
        #expect(r.text == "\"a1\"")
        #expect(r.spans == [.init(range: NSRange(location: 0, length: 4), key: "string"),
                            .init(range: NSRange(location: 2, length: 1), key: "number")])
    }

    @Test func decodesEntitiesAndCountsUTF16() {
        let r = HighlightSpans.parse(#"é &lt;<span class="hljs-keyword">a&amp;b</span>&quot;&#x27;"#)
        #expect(r.text == "é <a&b\"'")
        #expect(r.spans == [.init(range: NSRange(location: 3, length: 3), key: "keyword")])
    }

    @Test func unknownClassHasNoSpanAndClassMapping() {
        #expect(HighlightSpans.parse(#"<span class="hljs-attr">x</span>"#).spans.isEmpty)
        #expect(HighlightSpans.key(forClasses: "hljs-title class_") == "type")
        #expect(HighlightSpans.key(forClasses: "hljs-built_in") == "keyword")
    }
}
