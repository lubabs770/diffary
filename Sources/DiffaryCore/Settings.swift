import Foundation
import TOMLKit

public enum SidebarPosition: String, Sendable { case right, left, bottom }
public enum DiffPosition: String, Sendable {
    case belowList = "below_list", besideList = "beside_list", replaceTerminal = "replace_terminal"
}
public enum DiffViewMode: String, Sendable { case unified, sideBySide = "side_by_side" }

public struct Settings: Sendable, Equatable {
    public var baseBranch = "master"
    public var sidebar = SidebarPosition.right
    public var sidebarSize = 0.35
    public var diffPosition = DiffPosition.belowList
    public var diffView = DiffViewMode.unified
    public var contextLines = 3
    public var ignoreWhitespace = false
    public var syntaxHighlight = true
    public var font = "JetBrains Mono"
    public var fontSize = 13.0
    public var theme = "ghostty"
    public var titlebar = false
    public init() {}

    public var diffOptions: DiffOptions {
        DiffOptions(contextLines: contextLines, ignoreWhitespace: ignoreWhitespace)
    }
}

public struct SettingsLoad: Sendable, Equatable {
    public let settings: Settings
    public let warnings: [String]
}

public enum SettingsLoader {
    public static func configDir(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let xdg = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        let root = xdg ?? ((env["HOME"] ?? NSHomeDirectory()) + "/.config")
        return URL(fileURLWithPath: root).appendingPathComponent("diffary")
    }

    public static func defaultConfigFile(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        configDir(env: env).appendingPathComponent("config.toml")
    }

    /// File first, then overrides. Never throws: problems become warnings and
    /// the affected key keeps its default.
    public static func load(file: URL, overrides: [String: String]) -> SettingsLoad {
        var settings = Settings()
        var warnings: [String] = []
        var values: [(String, String)] = []

        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                values = flatten(try TOMLTable(string: text), prefix: "")
            } catch {
                warnings.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        values += overrides.sorted { $0.key < $1.key }

        for (key, value) in values {
            guard let apply = setters[key] else {
                warnings.append("unknown config key '\(key)'")
                continue
            }
            if !apply(&settings, value) {
                warnings.append("invalid value '\(value)' for '\(key)', using default")
            }
        }
        return SettingsLoad(settings: settings, warnings: warnings)
    }

    /// Nested tables → dotted keys, scalar values → strings.
    static func flatten(_ table: TOMLTable, prefix: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for (key, value) in table {
            let full = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let sub = value.table { out += flatten(sub, prefix: full) }
            else if let s = value.string { out.append((full, s)) }
            else if let i = value.int { out.append((full, String(i))) }
            else if let d = value.double { out.append((full, String(d))) }
            else if let b = value.bool { out.append((full, String(b))) }
            else { out.append((full, "\(value)")) }
        }
        return out
    }

    typealias Setter = @Sendable (inout Settings, String) -> Bool

    static let setters: [String: Setter] = [
        "base_branch": { s, v in guard !v.isEmpty else { return false }; s.baseBranch = v; return true },
        "layout.sidebar": { s, v in set(&s.sidebar, SidebarPosition(rawValue: v)) },
        "layout.sidebar_size": { s, v in set(&s.sidebarSize, Double(v).flatMap { (0.1...0.9).contains($0) ? $0 : nil }) },
        "layout.diff_position": { s, v in set(&s.diffPosition, DiffPosition(rawValue: v)) },
        "diff.view": { s, v in set(&s.diffView, DiffViewMode(rawValue: v)) },
        "diff.context_lines": { s, v in set(&s.contextLines, Int(v).flatMap { (0...1000).contains($0) ? $0 : nil }) },
        "diff.ignore_whitespace": { s, v in set(&s.ignoreWhitespace, Bool(v)) },
        "diff.syntax_highlight": { s, v in set(&s.syntaxHighlight, Bool(v)) },
        "appearance.font": { s, v in guard !v.isEmpty else { return false }; s.font = v; return true },
        "appearance.font_size": { s, v in set(&s.fontSize, Double(v).flatMap { (6...72).contains($0) ? $0 : nil }) },
        "appearance.theme": { s, v in guard !v.isEmpty else { return false }; s.theme = v; return true },
        "appearance.titlebar": { s, v in set(&s.titlebar, Bool(v)) },
    ]

    private static func set<T>(_ target: inout T, _ value: T?) -> Bool {
        guard let value else { return false }
        target = value
        return true
    }
}
