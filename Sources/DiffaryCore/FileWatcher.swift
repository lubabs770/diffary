import CoreServices
import Foundation

/// FSEvents watcher with a trailing debounce. All state lives on `queue`.
public final class FileWatcher: @unchecked Sendable {
    private let paths: [URL]
    private let ignoring: [String]
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "diffary.filewatcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    public init(paths: [URL], ignoring: [String] = [], debounce: TimeInterval = 0.3,
                onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.ignoring = ignoring
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(paths.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags)
        else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        pending?.cancel()
    }

    private func handle(_ eventPaths: [String]) {
        let relevant = eventPaths.contains { path in !ignoring.contains { path.contains($0) } }
        guard relevant else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
