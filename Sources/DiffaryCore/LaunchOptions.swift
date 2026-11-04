import ArgumentParser
import Foundation

public struct Launch: Sendable, Equatable {
    public let repo: URL
    public let configFile: URL
    public let overrides: [String: String]

    public static func parse(_ args: [String], cwd: URL, env: [String: String]) throws -> Launch {
        try LaunchCommand.parse(args).resolve(cwd: cwd, env: env)
    }
}

public struct LaunchCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "diffary",
        abstract: "Ghostty terminal + live branch diff.",
        version: "0.1.0")

    @Argument(help: "Repo to watch. Default: current directory.")
    var repo: String?

    @Option(help: "Config file. Default: $XDG_CONFIG_HOME/diffary/config.toml.")
    var config: String?

    @Option(help: "Base branch for this window (overrides base_branch).")
    var base: String?

    @Option(name: .customLong("set"), help: "Override a config key, e.g. diff.view=side_by_side. Repeatable.")
    var overrides: [String] = []

    public init() {}

    public func resolve(cwd: URL, env: [String: String]) throws -> Launch {
        var map: [String: String] = [:]
        for pair in overrides {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw ValidationError("--set expects key=value, got '\(pair)'")
            }
            map[parts[0]] = parts[1]
        }
        if let base { map["base_branch"] = base }
        // cwd must be a directory URL, or "../x" resolves against its parent.
        let base = URL(fileURLWithPath: cwd.path, isDirectory: true)
        func abs(_ p: String) -> URL { URL(fileURLWithPath: p, relativeTo: base).standardizedFileURL }
        return Launch(
            repo: repo.map(abs) ?? cwd.standardizedFileURL,
            configFile: config.map(abs) ?? SettingsLoader.defaultConfigFile(env: env),
            overrides: map)
    }
}
