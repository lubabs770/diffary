import Testing
@testable import DiffaryCore

@Suite struct DiffParserTests {
    let sample = """
    diff --git a/a.txt b/a.txt
    index 1..2 100644
    --- a/a.txt
    +++ b/a.txt
    @@ -1,3 +1,3 @@ func x
     keep
    -old1
    -old2
    +new1
    \\ No newline at end of file

    """

    @Test func parsesHunkAndNumbers() {
        guard case .text(let hunks) = DiffParser.parse(sample) else {
            Issue.record("expected text"); return
        }
        #expect(hunks.count == 1)
        #expect(hunks[0].header == "@@ -1,3 +1,3 @@ func x")
        #expect(hunks[0].lines == [
            DiffLine(kind: .context, text: "keep", oldNumber: 1, newNumber: 1),
            DiffLine(kind: .removed, text: "old1", oldNumber: 2, newNumber: nil),
            DiffLine(kind: .removed, text: "old2", oldNumber: 3, newNumber: nil),
            DiffLine(kind: .added, text: "new1", oldNumber: nil, newNumber: 2),
        ])
    }

    @Test func sideBySidePairsRemovedWithAdded() {
        guard case .text(let hunks) = DiffParser.parse(sample) else { return }
        let rows = hunks[0].sideBySideRows
        #expect(rows.count == 3)
        #expect(rows[0].left?.text == "keep" && rows[0].right?.text == "keep")
        #expect(rows[1].left?.text == "old1" && rows[1].right?.text == "new1")
        #expect(rows[2].left?.text == "old2" && rows[2].right == nil)
    }

    @Test func binary() {
        #expect(DiffParser.parse("diff --git a/x b/x\nBinary files a/x and b/x differ\n") == .binary)
    }

    @Test func empty() {
        #expect(DiffParser.parse("") == .empty)
    }

    @Test func tooLarge() {
        let raw = "@@ -1 +1 @@\n" + String(repeating: "+x\n", count: DiffParser.maxLines + 1)
        #expect(DiffParser.parse(raw) == .tooLarge(lines: DiffParser.maxLines + 2))
    }
}
