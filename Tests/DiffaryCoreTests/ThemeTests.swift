import Foundation
import Testing
@testable import DiffaryCore

@Suite struct ThemeTests {
    func themesDir(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: dir.appendingPathComponent("\(name).toml"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    @Test func hex() {
        #expect(RGBA(hex: "#ff0000") == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(RGBA(hex: "#00ff0080")?.a == Double(0x80) / 255)
        #expect(RGBA(hex: "red") == nil)
        #expect(RGBA(hex: "#ff000080")?.hex == "#ff000080")
    }

    @Test func autoFollowsSystem() throws {
        let dir = try themesDir([:])
        #expect(ThemeLoader.resolve(name: "auto", systemIsDark: true, themesDir: dir).theme == .dark)
        #expect(ThemeLoader.resolve(name: "auto", systemIsDark: false, themesDir: dir).theme == .light)
        #expect(ThemeLoader.resolve(name: "light", systemIsDark: true, themesDir: dir).theme == .light)
    }

    @Test func userThemeOverridesAndInheritsBase() throws {
        let dir = try themesDir(["mocha": """
        base = "light"
        background = "#1e1e2e"
        [syntax]
        keyword = "#cba6f7"
        """])
        let (theme, warnings) = ThemeLoader.resolve(name: "mocha", systemIsDark: true, themesDir: dir)
        #expect(warnings.isEmpty)
        #expect(theme.background == RGBA(hex: "#1e1e2e"))
        #expect(theme.foreground == Theme.light.foreground)
        #expect(theme.syntax["keyword"] == RGBA(hex: "#cba6f7"))
        #expect(theme.syntax["string"] == Theme.light.syntax["string"])
    }

    @Test func missingThemeWarnsAndUsesAuto() throws {
        let (theme, warnings) = ThemeLoader.resolve(name: "nope", systemIsDark: true, themesDir: try themesDir([:]))
        #expect(theme == .dark)
        #expect(warnings.count == 1)
    }

    @Test func badColorWarnsAndKeepsBase() throws {
        let dir = try themesDir(["t": "background = \"blue\"\nwat = \"#000000\"\n"])
        let (theme, warnings) = ThemeLoader.resolve(name: "t", systemIsDark: true, themesDir: dir)
        #expect(theme.background == Theme.dark.background)
        #expect(warnings.count == 2)
    }
}
