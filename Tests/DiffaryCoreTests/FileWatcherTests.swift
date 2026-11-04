import Foundation
import Testing
@testable import DiffaryCore

@Suite(.serialized) struct FileWatcherTests {
    func tempDir() throws -> URL {
        // Resolve /var → /private/var so FSEvents paths match.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git/objects"),
                                                withIntermediateDirectories: true)
        return dir
    }

    @Test func firesOnceForABurst() throws {
        let dir = try tempDir()
        let counter = Counter()
        let watcher = FileWatcher(paths: [dir], debounce: 0.3) { counter.bump() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)
        for i in 0..<5 { try "x".write(to: dir.appendingPathComponent("f\(i)"), atomically: true, encoding: .utf8) }
        Thread.sleep(forTimeInterval: 1.5)
        #expect(counter.value == 1)
    }

    @Test func ignoresIgnoredPaths() throws {
        let dir = try tempDir()
        let counter = Counter()
        let watcher = FileWatcher(paths: [dir], ignoring: ["/.git/objects/"], debounce: 0.1) { counter.bump() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)
        try "x".write(to: dir.appendingPathComponent(".git/objects/ab"), atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 1.0)
        #expect(counter.value == 0)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
