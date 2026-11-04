import Foundation

public struct GitError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Carries stderr from the drain thread back; written before `group.wait()` returns.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Runs the git CLI in one repo. The only place diffary spawns git.
public struct Git: Sendable {
    public let repo: URL
    public init(repo: URL) { self.repo = repo }

    /// Returns stdout. Throws GitError carrying stderr's first line when the
    /// exit code isn't in `allowExitCodes`.
    public func run(_ args: [String], allowExitCodes: Set<Int32> = [0]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo.path] + args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Drain stderr concurrently so a chatty stderr can't block stdout.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard allowExitCodes.contains(process.terminationStatus) else {
            let first = String(decoding: errBox.data, as: UTF8.self)
                .split(separator: "\n").first.map(String.init)
            throw GitError(first ?? "git \(args.first ?? "") exited \(process.terminationStatus)")
        }
        return String(decoding: outData, as: UTF8.self)
    }
}
