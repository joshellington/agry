import AgryCore
import Foundation

/// Follows OSC 7501 status in every Rex session through one `rex do --all`
/// process running `rexWatchScript`. Restarts with backoff when Rex goes away.
@MainActor
final class RexMonitor {
    enum Update {
        case status(blockID: String, RexStatus)
        case removed(blockID: String, recordIDs: [String])
        case blockGone(blockID: String)
        case disconnected
    }

    var onUpdate: ((Update) -> Void)?
    var onLog: ((String) -> Void)?
    private(set) var isConnected = false
    private(set) var rexURL: URL?

    private var watcher: LineProcess?
    private var sessionBlocks: [String: Set<String>] = [:]
    private var retryDelay: TimeInterval = 2

    func start() {
        guard let url = RexMonitor.locateRex() else {
            onLog?("rex: binary not found; retrying in 30s")
            schedule(after: 30) { $0.start() }
            return
        }
        rexURL = url
        connect()
    }

    private func connect() {
        guard let rexURL else { return }
        let process = LineProcess(executable: rexURL, arguments: ["do", "--all", "--autostart=false", "-e", rexWatchScript])
        process.onLine = { [weak self] line in self?.handle(line) }
        process.onExit = { [weak self] status in self?.watcherExited(status) }
        do {
            try process.start()
            watcher = process
        } catch {
            onLog?("rex: failed to start watcher: \(error)")
            reconnectLater()
        }
    }

    private func handle(_ line: String) {
        guard let event = RexParser.event(fromLine: line) else { return }
        switch event {
        case .ready:
            isConnected = true
            retryDelay = 2
            onLog?("rex: connected")
        case .statusChanged(let sessionID, let blockID, let status):
            onLog?("rex: \(blockID.suffix(6)) \(status.recordID.isEmpty ? "" : status.recordID + " ")\(status.app ?? "?") \(status.state.rawValue)\(status.kind.map { "/\($0)" } ?? "")")
            sessionBlocks[sessionID, default: []].insert(blockID)
            onUpdate?(.status(blockID: blockID, status))
        case .statusRemoved(_, let blockID, let ids):
            onLog?("rex: \(blockID.suffix(6)) removed \(ids)")
            onUpdate?(.removed(blockID: blockID, recordIDs: ids))
        case .blockClosed(let sessionID, let blockID):
            sessionBlocks[sessionID]?.remove(blockID)
            onUpdate?(.blockGone(blockID: blockID))
        case .sessionDestroyed(let sessionID):
            for blockID in sessionBlocks.removeValue(forKey: sessionID) ?? [] {
                onUpdate?(.blockGone(blockID: blockID))
            }
        case .sessionCreated:
            break
        }
    }

    private func watcherExited(_ status: Int32) {
        onLog?("rex: watcher exited (\(status))")
        watcher = nil
        isConnected = false
        sessionBlocks.removeAll()
        onUpdate?(.disconnected)
        reconnectLater()
    }

    private func reconnectLater() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        schedule(after: delay) { $0.connect() }
    }

    func stop() {
        watcher?.onExit = nil
        watcher?.stop()
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor (RexMonitor) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
    }

    /// GUI apps do not inherit the shell PATH, so look in the usual places.
    static func locateRex() -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["AGRY_REX"] { candidates.append(override) }
        for app in ["Rex Beta.app", "Rex.app"] {
            candidates.append("/Applications/\(app)/Contents/Helpers/Rex Server.app/Contents/MacOS/rex")
        }
        candidates += [
            "\(NSHomeDirectory())/.local/bin/rex",
            "/opt/homebrew/bin/rex",
            "/usr/local/bin/rex",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }
}
