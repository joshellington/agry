import AgryCore
import AppKit

/// Follows OSC 7501 status in every Rex session through one `rex do --all`
/// process running `rexWatchScript`. Restarts with backoff when Rex goes away.
@MainActor
final class RexMonitor {
    enum Update {
        case connected
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

    func sessionID(forBlock blockID: String) -> String? {
        sessionBlocks.first { $0.value.contains(blockID) }?.key
    }

    enum ShowOutcome {
        case shown
        /// The pane was focused, but Rex refused to switch sessions because its
        /// Remote Control setting is off.
        case needsRemoteControl
        case unavailable
    }

    /// Brings Rex forward on a block: selects its session in the Rex app,
    /// focuses the block, and activates the app.
    func show(blockID: String) async -> ShowOutcome {
        guard let rexURL, let sessionID = sessionID(forBlock: blockID) else { return .unavailable }
        let clients = await runProcess(rexURL, ["client", "ls", "--json", "--autostart=false"])
        guard let app = RexParser.appClient(fromJSON: clients.output) else { return .unavailable }
        let selected = await runProcess(rexURL, ["do", "-C", app.clientID, "session.select", "session_id=\(sessionID)"])
        _ = await runProcess(rexURL, ["focus", "-s", sessionID, blockID, "--autostart=false"])
        if let pid = app.pid, let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            // A menu bar app's plain activate() is ignored by cooperative
            // activation; opening the app asks the system to bring it forward.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        }
        if selected.status != 0 {
            onLog?("rex: session.select refused (Remote Control is off in Rex settings)")
            return .needsRemoteControl
        }
        return .shown
    }

    /// Opens Rex's server settings, where its Remote Control switch lives.
    static func openRemoteControlSettings() {
        if let url = URL(string: "rex://settings/server") { NSWorkspace.shared.open(url) }
    }

    private var sessionBlocks: [String: Set<String>] = [:]
    private var retryDelay: TimeInterval = 2

    func start() {
        connect()
    }

    /// Locates `rex` afresh on every attempt: Rex can swap its server build
    /// (and so the binary's path) while agry runs.
    private func connect() {
        guard let rexURL = RexMonitor.locateRex() else {
            onLog?("rex: binary not found; retrying in 30s")
            schedule(after: 30) { $0.connect() }
            return
        }
        if rexURL != self.rexURL { onLog?("rex: using \(rexURL.path)") }
        self.rexURL = rexURL
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
            onUpdate?(.connected)
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

    static func locateRex() -> URL? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let versionNames = (try? fm.contentsOfDirectory(atPath: RexLocator.versionsDirectory(home: home))) ?? []
        let candidates = RexLocator.candidates(
            home: home,
            override: ProcessInfo.processInfo.environment["AGRY_REX"],
            versionNames: versionNames)
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }
}
