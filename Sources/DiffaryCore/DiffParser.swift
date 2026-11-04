import Foundation

public enum DiffLineKind: Sendable, Equatable { case context, added, removed }

public struct DiffLine: Sendable, Equatable {
    public let kind: DiffLineKind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
}

public struct SideBySideRow: Sendable, Equatable {
    public let left: DiffLine?
    public let right: DiffLine?
}

public struct Hunk: Sendable, Equatable {
    public let header: String
    public let lines: [DiffLine]

    /// Context on both sides; each run of removals is paired line-by-line with
    /// the run of additions that follows it.
    public var sideBySideRows: [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var removed: [DiffLine] = [], added: [DiffLine] = []
        func flush() {
            for i in 0..<max(removed.count, added.count) {
                rows.append(SideBySideRow(left: i < removed.count ? removed[i] : nil,
                                          right: i < added.count ? added[i] : nil))
            }
            removed = []; added = []
        }
        for line in lines {
            switch line.kind {
            case .removed:
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added: added.append(line)
            case .context: flush(); rows.append(SideBySideRow(left: line, right: line))
            }
        }
        flush()
        return rows
    }
}

public enum FileDiff: Sendable, Equatable {
    case text([Hunk]), binary, tooLarge(lines: Int), empty
}

public enum DiffParser {
    public static let maxLines = 20_000

    public static func parse(_ raw: String) -> FileDiff {
        var lines = raw.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if lines.contains(where: { $0.hasPrefix("Binary files ") }) { return .binary }
        if lines.count > maxLines { return .tooLarge(lines: lines.count) }

        var hunks: [Hunk] = []
        var header: String?
        var body: [DiffLine] = []
        var old = 0, new = 0

        func close() {
            if let header { hunks.append(Hunk(header: header, lines: body)) }
            body = []
        }

        for line in lines {
            if line.hasPrefix("@@") {
                close()
                header = line
                (old, new) = startNumbers(line)
                continue
            }
            guard header != nil, let first = line.first else { continue }
            let text = String(line.dropFirst())
            switch first {
            case " ": body.append(DiffLine(kind: .context, text: text, oldNumber: old, newNumber: new)); old += 1; new += 1
            case "-": body.append(DiffLine(kind: .removed, text: text, oldNumber: old, newNumber: nil)); old += 1
            case "+": body.append(DiffLine(kind: .added, text: text, oldNumber: nil, newNumber: new)); new += 1
            default: continue  // "\ No newline at end of file"
            }
        }
        close()
        return hunks.isEmpty ? .empty : .text(hunks)
    }

    /// "@@ -12,3 +14,5 @@" → (12, 14)
    static func startNumbers(_ header: String) -> (Int, Int) {
        let parts = header.split(separator: " ")
        func start(_ prefix: Character) -> Int {
            guard let p = parts.first(where: { $0.first == prefix }) else { return 1 }
            return Int(p.dropFirst().split(separator: ",").first ?? "1") ?? 1
        }
        return (start("-"), start("+"))
    }
}
