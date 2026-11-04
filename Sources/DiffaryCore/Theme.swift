import Foundation
import TOMLKit

public struct RGBA: Sendable, Equatable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// "#rrggbb" or "#rrggbbaa".
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8, let v = UInt32(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? (v << 8) | 0xFF : v
        r = Double((full >> 24) & 0xFF) / 255
        g = Double((full >> 16) & 0xFF) / 255
        b = Double((full >> 8) & 0xFF) / 255
        a = Double(full & 0xFF) / 255
    }

    public var hex: String {
        String(format: "#%02x%02x%02x%02x",
               Int((r * 255).rounded()), Int((g * 255).rounded()),
               Int((b * 255).rounded()), Int((a * 255).rounded()))
    }
}

public struct Theme: Sendable, Equatable {
    public var isDark: Bool
    public var background, foreground, sidebarBackground, selection: RGBA
    public var addedBg, addedFg, removedBg, removedFg: RGBA
    public var hunkHeader, lineNumber: RGBA
    public var statusAdded, statusModified, statusDeleted, statusRenamed: RGBA
    public var syntax: [String: RGBA]

    // Immutable after init; key paths aren't Sendable, so the static needs an opt-out.
    nonisolated(unsafe) static let colorKeys: [String: WritableKeyPath<Theme, RGBA>] = [
        "background": \.background, "foreground": \.foreground,
        "sidebar_background": \.sidebarBackground, "selection": \.selection,
        "added_bg": \.addedBg, "added_fg": \.addedFg,
        "removed_bg": \.removedBg, "removed_fg": \.removedFg,
        "hunk_header": \.hunkHeader, "line_number": \.lineNumber,
        "status_added": \.statusAdded, "status_modified": \.statusModified,
        "status_deleted": \.statusDeleted, "status_renamed": \.statusRenamed,
    ]
    static let syntaxKeys: Set<String> = ["keyword", "string", "comment", "number", "type"]

    private static func c(_ hex: String) -> RGBA { RGBA(hex: hex)! }

    public static let dark = Theme(
        isDark: true,
        background: c("#1e1e1e"), foreground: c("#d4d4d4"), sidebarBackground: c("#181818"), selection: c("#264f78"),
        addedBg: c("#2ea04326"), addedFg: c("#3fb950"), removedBg: c("#f8514926"), removedFg: c("#f85149"),
        hunkHeader: c("#58a6ff"), lineNumber: c("#6e7681"),
        statusAdded: c("#3fb950"), statusModified: c("#d29922"), statusDeleted: c("#f85149"), statusRenamed: c("#58a6ff"),
        syntax: ["keyword": c("#c586c0"), "string": c("#ce9178"), "comment": c("#6a9955"),
                 "number": c("#b5cea8"), "type": c("#4ec9b0")])

    public static let light = Theme(
        isDark: false,
        background: c("#ffffff"), foreground: c("#1f2328"), sidebarBackground: c("#f6f8fa"), selection: c("#b6d7ff"),
        addedBg: c("#1a7f3720"), addedFg: c("#1a7f37"), removedBg: c("#cf222e20"), removedFg: c("#cf222e"),
        hunkHeader: c("#0969da"), lineNumber: c("#8c959f"),
        statusAdded: c("#1a7f37"), statusModified: c("#9a6700"), statusDeleted: c("#cf222e"), statusRenamed: c("#0969da"),
        syntax: ["keyword": c("#cf222e"), "string": c("#0a3069"), "comment": c("#6e7781"),
                 "number": c("#0550ae"), "type": c("#953800")])
}

/// The embedded terminal's own colors (from Ghostty's config).
public struct TerminalColors: Sendable, Equatable {
    public var background, foreground: RGBA
    public var selection: RGBA?
    public init(background: RGBA, foreground: RGBA, selection: RGBA?) {
        self.background = background; self.foreground = foreground; self.selection = selection
    }
}

extension RGBA {
    /// Relative luminance, 0 (black) … 1 (white).
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// `self` moved `t` of the way toward `other`.
    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: 1)
    }
}

extension Theme {
    /// Panels in the terminal's colors; diff and syntax colors from the matching built-in.
    public static func matching(_ t: TerminalColors) -> Theme {
        var theme = t.background.luminance < 0.5 ? Theme.dark : Theme.light
        theme.background = t.background
        theme.sidebarBackground = t.background
        theme.foreground = t.foreground
        theme.selection = t.selection ?? t.background.mixed(with: t.foreground, 0.2)
        theme.lineNumber = t.background.mixed(with: t.foreground, 0.45)
        return theme
    }
}

public enum ThemeLoader {
    public static func resolve(name: String, systemIsDark: Bool, themesDir: URL,
                               terminal: TerminalColors? = nil) -> (theme: Theme, warnings: [String]) {
        let auto = systemIsDark ? Theme.dark : Theme.light
        switch name {
        case "ghostty": return (terminal.map(Theme.matching) ?? auto, [])
        case "auto": return (auto, [])
        case "dark": return (.dark, [])
        case "light": return (.light, [])
        default: break
        }
        let file = themesDir.appendingPathComponent("\(name).toml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return (auto, ["theme '\(name)' not found at \(file.path), using auto"])
        }
        let table: TOMLTable
        do { table = try TOMLTable(string: text) } catch {
            return (auto, ["theme '\(name)': \(error)"])
        }

        var warnings: [String] = []
        var theme = table["base"]?.string == "light" ? Theme.light : Theme.dark
        for (key, value) in table {
            if key == "base" { continue }
            if key == "syntax", let syntax = value.table {
                for (sk, sv) in syntax {
                    guard Theme.syntaxKeys.contains(sk), let color = sv.string.flatMap(RGBA.init(hex:)) else {
                        warnings.append("theme '\(name)': bad syntax.\(sk)"); continue
                    }
                    theme.syntax[sk] = color
                }
                continue
            }
            guard let path = Theme.colorKeys[key] else {
                warnings.append("theme '\(name)': unknown key '\(key)'"); continue
            }
            guard let color = value.string.flatMap(RGBA.init(hex:)) else {
                warnings.append("theme '\(name)': bad color for '\(key)'"); continue
            }
            theme[keyPath: path] = color
        }
        return (theme, warnings)
    }
}
