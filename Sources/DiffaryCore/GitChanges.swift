import Foundation

public enum ChangeStatus: String, Sendable {
    case added = "A", modified = "M", deleted = "D", renamed = "R", untracked = "?"
}

public struct FileChange: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let oldPath: String?
    public let status: ChangeStatus
    /// nil for binary files.
    public let additions: Int?
    public let deletions: Int?
}

public struct ChangeSet: Sendable, Equatable {
    /// merge-base commit sha the files are diffed against.
    public let base: String
    public let files: [FileChange]
}

/// Lists what the working tree changed vs merge-base(baseBranch, HEAD).
public struct GitChanges: Sendable {
    public let git: Git
    public let baseBranch: String

    public init(repo: URL, baseBranch: String) {
        self.git = Git(repo: repo)
        self.baseBranch = baseBranch
    }

    public func load() throws -> ChangeSet {
        _ = try git.run(["rev-parse", "--is-inside-work-tree"])
        let base = try mergeBase()
        let numstat = parseNumstat(try git.run(["diff", "--numstat", "-M", "-z", base]))
        var files = parseNameStatus(try git.run(["diff", "--name-status", "-M", "-z", base]))
            .map { entry in
                let counts = numstat[entry.path]
                return FileChange(path: entry.path, oldPath: entry.oldPath, status: entry.status,
                                  additions: counts?.0, deletions: counts?.1)
            }
        let untracked = try git.run(["ls-files", "--others", "--exclude-standard", "-z"])
            .split(separator: "\0").map(String.init)
        files += untracked.map { path in
            FileChange(path: path, oldPath: nil, status: .untracked,
                       additions: lineCount(git.repo.appendingPathComponent(path)), deletions: 0)
        }
        return ChangeSet(base: base, files: files.sorted { $0.path < $1.path })
    }

    func mergeBase() throws -> String {
        let candidates = baseBranch == "master" ? ["master", "main"] : [baseBranch]
        for branch in candidates {
            if (try? git.run(["rev-parse", "--verify", "--quiet", "\(branch)^{commit}"])) != nil {
                return try git.run(["merge-base", branch, "HEAD"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        throw GitError("base branch '\(baseBranch)' not found")
    }

    /// `-z` name-status: "M\0path\0", renames "R100\0old\0new\0".
    func parseNameStatus(_ raw: String) -> [(path: String, oldPath: String?, status: ChangeStatus)] {
        var fields = raw.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        var result: [(String, String?, ChangeStatus)] = []
        while let code = fields.popFirst(), !code.isEmpty {
            switch code.first {
            case "R", "C":
                guard let old = fields.popFirst(), let new = fields.popFirst() else { break }
                result.append((new, old, .renamed))
            case "A": if let p = fields.popFirst() { result.append((p, nil, .added)) }
            case "D": if let p = fields.popFirst() { result.append((p, nil, .deleted)) }
            default: if let p = fields.popFirst() { result.append((p, nil, .modified)) }
            }
        }
        return result
    }

    /// `-z` numstat: "add\tdel\tpath\0", renames "add\tdel\t\0old\0new\0". Binary shows "-".
    func parseNumstat(_ raw: String) -> [String: (Int?, Int?)] {
        var fields = raw.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        var result: [String: (Int?, Int?)] = [:]
        while let head = fields.popFirst(), !head.isEmpty {
            let parts = head.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            if path.isEmpty { _ = fields.popFirst(); path = fields.popFirst() ?? "" }
            result[path] = (Int(parts[0]), Int(parts[1]))
        }
        return result
    }

    /// Lines in an untracked file; nil if it isn't a regular file (symlinks
    /// aren't followed), is over 16 MB, or looks binary (contains NUL).
    func lineCount(_ url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= 16 << 20,
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        if data.contains(0) { return nil }
        let newlines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        return newlines + (data.last.map { $0 == 0x0A ? 0 : 1 } ?? 0)
    }
}
