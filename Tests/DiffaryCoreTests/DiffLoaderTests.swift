import Foundation
import Testing
@testable import DiffaryCore

@Suite struct DiffLoaderTests {
    func repoWithChange() throws -> (TempRepo, ChangeSet) {
        let repo = try TempRepo()
        try repo.write("a.txt", (1...20).map { "line\($0)" }.joined(separator: "\n") + "\n")
        try repo.commitAll()
        var lines = (1...20).map { "line\($0)" }
        lines[9] = "CHANGED"
        try repo.write("a.txt", lines.joined(separator: "\n") + "\n")
        try repo.write("new.txt", "hello\n")
        return (repo, try GitChanges(repo: repo.url, baseBranch: "master").load())
    }

    @Test func contextLinesControlsSurroundingLines() throws {
        let (repo, set) = try repoWithChange()
        let a = set.files.first { $0.path == "a.txt" }!
        let loader = DiffLoader(repo: repo.url)
        guard case .text(let h1) = try loader.load(a, base: set.base, options: .init(contextLines: 1, ignoreWhitespace: false)),
              case .text(let h5) = try loader.load(a, base: set.base, options: .init(contextLines: 5, ignoreWhitespace: false))
        else { Issue.record("expected text"); return }
        #expect(h1[0].lines.filter { $0.kind == .context }.count == 2)
        #expect(h5[0].lines.filter { $0.kind == .context }.count == 10)
    }

    @Test func ignoreWhitespaceHidesWhitespaceOnlyChange() throws {
        let repo = try TempRepo()
        try repo.write("a.txt", "x = 1\n")
        try repo.commitAll()
        try repo.write("a.txt", "x  =  1\n")
        let set = try GitChanges(repo: repo.url, baseBranch: "master").load()
        let diff = try DiffLoader(repo: repo.url)
            .load(set.files[0], base: set.base, options: .init(contextLines: 3, ignoreWhitespace: true))
        #expect(diff == .empty)
    }

    @Test func untrackedFileShowsAsAllAdded() throws {
        let (repo, set) = try repoWithChange()
        let n = set.files.first { $0.path == "new.txt" }!
        let diff = try DiffLoader(repo: repo.url).load(n, base: set.base, options: .init(contextLines: 3, ignoreWhitespace: false))
        guard case .text(let hunks) = diff else { Issue.record("expected text"); return }
        #expect(hunks[0].lines == [DiffLine(kind: .added, text: "hello", oldNumber: nil, newNumber: 1)])
    }
}
