import Foundation

public struct GitError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Runs the git CLI in one repo. The only place diffary spawns git.
public struct Git: Sendable {
    public let repo: URL
    public init(repo: URL) { self.repo = repo }

    /// The work tree root containing `dir`, or nil if it isn't in one.
    public static func toplevel(of dir: URL) -> URL? {
        guard let out = try? Git(repo: dir).run(["rev-parse", "--show-toplevel"]) else { return nil }
        let path = out.trimmingCharacters(in: .newlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Returns stdout. Throws GitError carrying stderr's first line when the
    /// exit code isn't in `allowExitCodes`.
    public func run(_ args: [String], allowExitCodes: Set<Int32> = [0]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // fsmonitor would spawn a daemon that inherits our stdout/stderr.
        process.arguments = ["git", "-C", repo.path, "-c", "core.fsmonitor=false"] + args
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_OPTIONAL_LOCKS": "0", "GIT_LITERAL_PATHSPECS": "1"]) { $1 }
        // Output goes to unlinked temp files, not pipes: nothing waits for a
        // pipe's EOF, which a lingering grandchild (hook, daemon) could hold open.
        let out = try Self.tempFile(), err = try Self.tempFile()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        try out.seek(toOffset: 0)
        try err.seek(toOffset: 0)
        let outData = out.readDataToEndOfFile(), errData = err.readDataToEndOfFile()
        guard allowExitCodes.contains(process.terminationStatus) else {
            let first = String(decoding: errData, as: UTF8.self)
                .split(separator: "\n").first.map(String.init)
            throw GitError(first ?? "git \(args.first ?? "") exited \(process.terminationStatus)")
        }
        return String(decoding: outData, as: UTF8.self)
    }

    private static func tempFile() throws -> FileHandle {
        var template = Array((NSTemporaryDirectory() + "diffary-git.XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw GitError("mkstemp failed: errno \(errno)") }
        unlink(template)
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
