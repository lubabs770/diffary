import Foundation

public struct DiffOptions: Sendable, Equatable {
    public var contextLines: Int
    public var ignoreWhitespace: Bool
    public init(contextLines: Int, ignoreWhitespace: Bool) {
        self.contextLines = contextLines
        self.ignoreWhitespace = ignoreWhitespace
    }
}

/// Loads the diff for one file vs the change set's base.
public struct DiffLoader: Sendable {
    public let git: Git
    public init(repo: URL) { git = Git(repo: repo) }

    public func load(_ change: FileChange, base: String, options: DiffOptions) throws -> FileDiff {
        var args = ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "-U\(options.contextLines)"]
        if options.ignoreWhitespace { args.append("-w") }
        if change.status == .untracked {
            // --no-index exits 1 when the files differ.
            args += ["--no-index", "--", "/dev/null", change.path]
            return DiffParser.parse(try git.run(args, allowExitCodes: [0, 1]))
        }
        args += ["-M", base, "--"] + [change.oldPath, change.path].compactMap { $0 }
        return DiffParser.parse(try git.run(args))
    }
}
