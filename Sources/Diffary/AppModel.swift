import AppKit
import DiffaryCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let launch: Launch
    @Published private(set) var settings = Settings()
    @Published private(set) var theme = Theme.dark
    @Published private(set) var warnings: [String] = []
    @Published private(set) var changes: ChangeSet?
    @Published private(set) var gitError: String?
    @Published private(set) var selected: FileChange?
    @Published private(set) var diff: FileDiff?

    private var repoWatcher: FileWatcher?
    private var configWatcher: FileWatcher?
    private var appearanceObserver: NSKeyValueObservation?
    private let work = DispatchQueue(label: "diffary.git")

    var themesDir: URL { launch.configFile.deletingLastPathComponent().appendingPathComponent("themes") }

    init(launch: Launch) {
        self.launch = launch
        reloadSettings()
        refresh()
        repoWatcher = FileWatcher(paths: [launch.repo], ignoring: ["/.git/objects/", "/.git/logs/"]) { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        repoWatcher?.start()
        // Watch the config dir, not the file: editors save by replacing it. If it
        // doesn't exist yet (fresh install), watch its nearest existing ancestor.
        var watched = launch.configFile.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: watched.path), watched.path != "/" {
            watched = watched.deletingLastPathComponent()
        }
        configWatcher = FileWatcher(paths: [watched], debounce: 0.1) { [weak self] in
            DispatchQueue.main.async { self?.reloadSettings() }
        }
        configWatcher?.start()
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reloadSettings() }
        }
    }

    func reloadSettings() {
        let load = SettingsLoader.load(file: launch.configFile, overrides: launch.overrides)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resolved = ThemeLoader.resolve(name: load.settings.theme, systemIsDark: isDark, themesDir: themesDir)
        let baseChanged = load.settings.baseBranch != settings.baseBranch
        let diffChanged = load.settings.diffOptions != settings.diffOptions
        settings = load.settings
        theme = resolved.theme
        warnings = load.warnings + resolved.warnings
        if baseChanged { refresh() } else if diffChanged { loadDiff() }
    }

    func refresh() {
        let repo = launch.repo, base = settings.baseBranch
        work.async {
            let result = Result { try GitChanges(repo: repo, baseBranch: base).load() }
            DispatchQueue.main.async {
                switch result {
                case .success(let set):
                    self.changes = set
                    self.gitError = nil
                    if self.selected == nil, let want = self.launch.select {
                        self.selected = set.files.first { $0.path == want }
                    }
                    // Keep the selection if the file is still changed; reload its diff.
                    if let sel = self.selected {
                        self.selected = set.files.first { $0.path == sel.path }
                        self.loadDiff()
                    }
                case .failure(let error):
                    // Keep the last good list; just surface the error.
                    self.gitError = "\(error)"
                }
            }
        }
    }

    func select(_ file: FileChange?) {
        selected = file
        loadDiff()
    }

    private func loadDiff() {
        guard let file = selected, let base = changes?.base else { diff = nil; return }
        let repo = launch.repo, options = settings.diffOptions
        work.async {
            let result = Result { try DiffLoader(repo: repo).load(file, base: base, options: options) }
            DispatchQueue.main.async {
                guard self.selected == file else { return }  // selection moved on
                switch result {
                case .success(let d): self.diff = d; self.gitError = nil
                case .failure(let e): self.diff = nil; self.gitError = "\(e)"
                }
            }
        }
    }
}
