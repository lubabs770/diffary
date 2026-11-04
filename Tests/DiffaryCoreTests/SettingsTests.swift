import Foundation
import Testing
@testable import DiffaryCore

@Suite struct SettingsTests {
    func file(_ toml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diffary-\(UUID()).toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func missingFileGivesDefaultsNoWarnings() {
        let load = SettingsLoader.load(file: URL(fileURLWithPath: "/nonexistent/config.toml"), overrides: [:])
        #expect(load.settings == Settings())
        #expect(load.warnings.isEmpty)
    }

    @Test func readsAllSections() throws {
        let load = SettingsLoader.load(file: try file("""
        base_branch = "develop"
        [layout]
        sidebar = "bottom"
        sidebar_size = 0.5
        diff_position = "replace_terminal"
        [diff]
        view = "side_by_side"
        context_lines = 8
        ignore_whitespace = true
        syntax_highlight = false
        [appearance]
        font = "Menlo"
        font_size = 15
        theme = "mocha"
        """), overrides: [:])
        let s = load.settings
        #expect(load.warnings.isEmpty)
        #expect(s.baseBranch == "develop")
        #expect(s.sidebar == .bottom && s.sidebarSize == 0.5 && s.diffPosition == .replaceTerminal)
        #expect(s.diffView == .sideBySide && s.contextLines == 8 && s.ignoreWhitespace && !s.syntaxHighlight)
        #expect(s.font == "Menlo" && s.fontSize == 15 && s.theme == "mocha")
    }

    @Test func badValuesFallBackWithWarnings() throws {
        let load = SettingsLoader.load(file: try file("""
        [layout]
        sidebar = "top"
        sidebar_size = 2.0
        [diff]
        context_lines = -1
        bogus = 1
        """), overrides: [:])
        #expect(load.settings == Settings())
        #expect(load.warnings.count == 4)
        #expect(load.warnings.contains { $0.contains("layout.sidebar") })
        #expect(load.warnings.contains { $0.contains("diff.bogus") })
    }

    @Test func parseErrorWarnsAndUsesDefaults() throws {
        let load = SettingsLoader.load(file: try file("this is = = not toml"), overrides: [:])
        #expect(load.settings == Settings())
        #expect(load.warnings.count == 1)
    }

    @Test func unreadableFileWarnsAndUsesDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diffary-\(UUID()).toml")
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        let load = SettingsLoader.load(file: url, overrides: [:])
        #expect(load.settings == Settings())
        #expect(load.warnings.count == 1)
    }

    @Test func overridesApplyAfterFile() throws {
        let load = SettingsLoader.load(
            file: try file("[diff]\nview = \"unified\"\ncontext_lines = 2\n"),
            overrides: ["diff.view": "side_by_side", "base_branch": "main"])
        #expect(load.settings.diffView == .sideBySide)
        #expect(load.settings.contextLines == 2)
        #expect(load.settings.baseBranch == "main")
    }

    @Test func xdgPaths() {
        #expect(SettingsLoader.defaultConfigFile(env: ["XDG_CONFIG_HOME": "/x", "HOME": "/h"]).path
                == "/x/diffary/config.toml")
        #expect(SettingsLoader.defaultConfigFile(env: ["HOME": "/h"]).path == "/h/.config/diffary/config.toml")
        #expect(SettingsLoader.defaultConfigFile(env: ["XDG_CONFIG_HOME": "", "HOME": "/h"]).path
                == "/h/.config/diffary/config.toml")
    }
}

@Suite struct AppearanceDefaultsTests {
    @Test func defaultsMatchTerminalAndHideTitlebar() {
        #expect(Settings().theme == "ghostty")
        #expect(Settings().titlebar == false)
    }

    @Test func titlebarCanBeTurnedOn() {
        let load = SettingsLoader.load(file: URL(fileURLWithPath: "/nonexistent"), overrides: ["appearance.titlebar": "true"])
        #expect(load.settings.titlebar)
        #expect(load.warnings.isEmpty)
    }
}

@Suite struct ExampleConfigTests {
    /// config.example.toml (copied on install) must load cleanly as plain defaults.
    @Test func exampleConfigIsDefaultsWithNoWarnings() {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("config.example.toml")
        let load = SettingsLoader.load(file: file, overrides: [:])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(load.warnings.isEmpty)
        #expect(load.settings == Settings())
    }
}

@Suite struct HyphenAliasTests {
    @Test func enumValuesAcceptHyphens() {
        let load = SettingsLoader.load(file: URL(fileURLWithPath: "/nonexistent"), overrides: [
            "layout.diff_position": "beside-list", "diff.view": "side-by-side",
        ])
        #expect(load.warnings.isEmpty)
        #expect(load.settings.diffPosition == .besideList)
        #expect(load.settings.diffView == .sideBySide)
    }
}
