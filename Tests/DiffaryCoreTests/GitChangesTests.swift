import Foundation
import Testing
@testable import DiffaryCore

@Suite struct GitChangesTests {
    /// master: a, b, c. feat: a modified (committed), b deleted, c renamed to d,
    /// e added (committed), a modified again (uncommitted), f untracked.
    func featureRepo() throws -> TempRepo {
        let repo = try TempRepo()
        try repo.write("a.txt", "one\ntwo\n")
        try repo.write("b.txt", "bee\n")
        try repo.write("c.txt", "same content for rename detection\nline2\nline3\n")
        try repo.commitAll("base")
        try repo.run("checkout", "-q", "-b", "feat")
        try repo.write("a.txt", "one\ntwo\nthree\n")
        try repo.run("rm", "-q", "b.txt")
        try repo.run("mv", "c.txt", "d.txt")
        try repo.write("e.txt", "new\n")
        try repo.commitAll("feat work")
        try repo.write("a.txt", "zero\none\ntwo\nthree\n")
        try repo.write("f.txt", "untracked\nfile\n")
        return repo
    }

    @Test func listsCommittedUncommittedAndUntracked() throws {
        let repo = try featureRepo()
        let set = try GitChanges(repo: repo.url, baseBranch: "master").load()
        let byPath = Dictionary(uniqueKeysWithValues: set.files.map { ($0.path, $0) })

        #expect(set.files.map(\.path) == ["a.txt", "b.txt", "d.txt", "e.txt", "f.txt"])
        #expect(byPath["a.txt"]?.status == .modified)
        #expect(byPath["a.txt"]?.additions == 2)
        #expect(byPath["a.txt"]?.deletions == 0)
        #expect(byPath["b.txt"]?.status == .deleted)
        #expect(byPath["b.txt"]?.deletions == 1)
        #expect(byPath["d.txt"]?.status == .renamed)
        #expect(byPath["d.txt"]?.oldPath == "c.txt")
        #expect(byPath["e.txt"]?.status == .added)
        #expect(byPath["f.txt"]?.status == .untracked)
        #expect(byPath["f.txt"]?.additions == 2)
    }

    @Test func baseIsMergeBaseNotMasterTip() throws {
        let repo = try featureRepo()
        let expected = try repo.run("rev-parse", "master").trimmingCharacters(in: .whitespacesAndNewlines)
        // featureRepo leaves uncommitted edits; stash them so checkout can move.
        try repo.run("stash", "push", "-u", "-q")
        try repo.run("checkout", "-q", "master")
        try repo.write("later.txt", "x\n")
        try repo.commitAll("master moves on")
        try repo.run("checkout", "-q", "feat")
        try repo.run("stash", "pop", "-q")
        let set = try GitChanges(repo: repo.url, baseBranch: "master").load()
        #expect(set.base == expected)
        #expect(!set.files.map(\.path).contains("later.txt"))
    }

    @Test func fallsBackToMainWhenMasterMissing() throws {
        let repo = try TempRepo(branch: "main")
        try repo.write("a.txt", "a\n")
        try repo.commitAll()
        try repo.write("a.txt", "b\n")
        let set = try GitChanges(repo: repo.url, baseBranch: "master").load()
        #expect(set.files.map(\.path) == ["a.txt"])
    }

    @Test func noFallbackForCustomBase() throws {
        let repo = try TempRepo(branch: "main")
        try repo.write("a.txt", "a\n")
        try repo.commitAll()
        #expect(throws: GitError.self) {
            try GitChanges(repo: repo.url, baseBranch: "develop").load()
        }
    }

    @Test func notARepoThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(throws: GitError.self) {
            try GitChanges(repo: dir, baseBranch: "master").load()
        }
    }

    @Test func binaryFileHasNilCounts() throws {
        let repo = try TempRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll()
        try repo.writeData("img.bin", Data([0, 1, 2, 0, 255]))
        try repo.run("add", "img.bin")
        let set = try GitChanges(repo: repo.url, baseBranch: "master").load()
        #expect(set.files.first?.path == "img.bin")
        #expect(set.files.first?.additions == nil)
    }
}
