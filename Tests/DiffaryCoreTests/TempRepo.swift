import Foundation
@testable import DiffaryCore

/// A throwaway git repo in the temp dir.
struct TempRepo {
    let url: URL
    var git: Git { Git(repo: url) }

    init(branch: String = "master") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diffary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try git.run(["init", "-q", "-b", branch])
        _ = try git.run(["config", "user.email", "test@example.com"])
        _ = try git.run(["config", "user.name", "test"])
        _ = try git.run(["config", "commit.gpgsign", "false"])
    }

    func write(_ path: String, _ text: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func writeData(_ path: String, _ data: Data) throws {
        try data.write(to: url.appendingPathComponent(path))
    }

    @discardableResult
    func run(_ args: String...) throws -> String { try git.run(args) }

    func commitAll(_ message: String = "c") throws {
        try run("add", "-A")
        try run("commit", "-q", "-m", message)
    }
}
