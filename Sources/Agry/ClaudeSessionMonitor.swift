import AgryCore
import CoreServices
import Foundation

/// Watches `~/.claude/sessions` and reports the current set of Claude Code
/// sessions whenever it changes (FSEvents, plus a slow safety rescan).
@MainActor
final class ClaudeSessionMonitor {
    var onChange: (([ClaudeSession]) -> Void)?

    private let directory: URL
    private var stream: FSEventStreamRef?
    private var rescanTimer: Timer?
    private var last: [ClaudeSession] = []

    init(directory: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/sessions")) {
        self.directory = directory
    }

    func start() {
        startStream()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        rescan()
    }

    func rescan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap(ClaudeSession.parse) }
            .sorted { $0.pid < $1.pid }
        guard sessions != last else { return }
        last = sessions
        onChange?(sessions)
    }

    private func startStream() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ClaudeSessionMonitor>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.rescan() }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
