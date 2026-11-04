import Foundation
import Testing
@testable import DiffaryCore

@Suite struct LaunchOptionsTests {
    let cwd = URL(fileURLWithPath: "/work/repo")
    let env = ["HOME": "/h"]

    @Test func defaults() throws {
        let l = try Launch.parse([], cwd: cwd, env: env)
        #expect(l.repo.path == "/work/repo")
        #expect(l.configFile.path == "/h/.config/diffary/config.toml")
        #expect(l.overrides.isEmpty)
    }

    @Test func allFlags() throws {
        let l = try Launch.parse(
            ["../other", "--config", "my.toml", "--base", "develop",
             "--set", "diff.view=side_by_side", "--set", "layout.sidebar=left"],
            cwd: cwd, env: env)
        #expect(l.repo.path == "/work/other")
        #expect(l.configFile.path == "/work/repo/my.toml")
        #expect(l.overrides == ["base_branch": "develop", "diff.view": "side_by_side", "layout.sidebar": "left"])
    }

    @Test func equalsFormConfig() throws {
        let l = try Launch.parse(["--config=/etc/d.toml"], cwd: cwd, env: env)
        #expect(l.configFile.path == "/etc/d.toml")
    }

    @Test func badSetIsAnError() {
        #expect(throws: (any Error).self) { try Launch.parse(["--set", "novalue"], cwd: cwd, env: env) }
    }
}
