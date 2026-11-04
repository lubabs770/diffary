import AppKit
import DiffaryCore

let launch: Launch
do {
    // --help/--version throw CleanExit; exit(withError:) prints them and exits 0.
    let command = try LaunchCommand.parse(Array(CommandLine.arguments.dropFirst()))
    launch = try command.resolve(cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                                 env: ProcessInfo.processInfo.environment)
} catch {
    LaunchCommand.exit(withError: error)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate(launch: launch)
app.delegate = delegate
app.run()
