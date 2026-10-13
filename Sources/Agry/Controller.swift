import AgryCore
import Foundation

/// Owns all state: gathers records from the monitors, evaluates the policy,
/// and drives the sleep assertion. Everything runs on the main actor.
@MainActor
final class Controller {
    private(set) var store = RecordStore()
    private(set) var claudeSessions: [ClaudeSession] = []
    private(set) var decision = Decision.empty
    private(set) var log: [String] = []
    var forceRemote = false {
        didSet { note("away mode \(forceRemote ? "on" : "off")"); evaluate() }
    }

    let power = PowerMonitor()
    let rex = RexMonitor()
    private let claude = ClaudeSessionMonitor()
    private let assertion = SleepAssertion()
    private let policy = Policy(config: .defaults, isAlive: isProcessAlive)
    private var deadlineTimer: Timer?
    private var heartbeat: Timer?

    /// Called after every evaluation so the menu bar can refresh.
    var onChange: (() -> Void)?

    var remotePIDs: Set<Int32> { Set(claudeSessions.filter(\.isRemote).map(\.pid)) }

    func start() {
        power.onChange = { [weak self] onAC in
            self?.note("power: \(onAC ? "AC" : "battery")")
            self?.evaluate()
        }
        rex.onLog = { [weak self] line in self?.note(line) }
        rex.onUpdate = { [weak self] update in self?.apply(update) }
        claude.onChange = { [weak self] sessions in self?.apply(sessions) }

        power.start()
        claude.start()
        rex.start()
        // Owner liveness and stuck records are checked on a slow heartbeat.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    func stop() {
        rex.stop()
        assertion.set(held: false, reason: "")
    }

    // MARK: Manual hold

    func holdManually(for duration: TimeInterval?) {
        let now = Date()
        let expiry = duration.map { now.addingTimeInterval($0) } ?? .distantFuture
        store.remove(.manual)
        store.apply(StatusRecord(source: .manual, state: .working, app: "manual", stateSince: now, expiresAt: expiry))
        note("manual hold until \(duration == nil ? "turned off" : expiry.formatted(date: .omitted, time: .shortened))")
        evaluate()
    }

    func cancelManualHold() {
        store.remove(.manual)
        note("manual hold cancelled")
        evaluate()
    }

    var hasManualHold: Bool { store.records[.manual] != nil }

    // MARK: Inputs

    private func apply(_ update: RexMonitor.Update) {
        let now = Date()
        switch update {
        case .status(let blockID, let status):
            store.apply(status.record(blockID: blockID, observedAt: now))
        case .removed(let blockID, let ids):
            for id in ids { store.removeRexRecord(blockID: blockID, recordID: id) }
        case .blockGone(let blockID):
            store.removeBlock(blockID)
        case .disconnected:
            store.removeAll { if case .rex = $0 { true } else { false } }
        }
        evaluate()
    }

    private func apply(_ sessions: [ClaudeSession]) {
        let now = Date()
        let pids = Set(sessions.map(\.pid))
        store.removeAll { source in
            if case .claudeSession(let pid) = source { return !pids.contains(pid) }
            return false
        }
        for session in sessions {
            if let record = session.record(observedAt: now) {
                store.apply(record)
            } else {
                store.remove(.claudeSession(pid: session.pid))
            }
        }
        let summary = sessions.map { "\($0.pid):\($0.rawStatus ?? "?")\($0.isRemote ? "+rc" : "")" }
        note("claude sessions: \(summary.joined(separator: " "))")
        claudeSessions = sessions
        evaluate()
    }

    // MARK: Evaluation

    func evaluate() {
        let now = Date()
        let next = policy.evaluate(PolicyInput(
            records: store.merged(), onAC: power.onAC, remotePIDs: remotePIDs,
            forceRemote: forceRemote, now: now))
        if next.isHolding != decision.isHolding {
            note(next.isHolding ? "holding: \(summary(of: next))" : "released")
        }
        decision = next
        assertion.set(held: next.isHolding, reason: summary(of: next))
        scheduleDeadline(next.nextDeadline)
        writeDebugState()
        onChange?()
    }

    private func scheduleDeadline(_ deadline: Date?) {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline else { return }
        // Fire just after the deadline so the expired hold evaluates as released.
        let timer = Timer(fire: deadline.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    func summary(of decision: Decision) -> String {
        let holding = decision.verdicts.filter { $0.holdUntil != nil }
        guard let first = holding.first else { return "idle" }
        let label = "\(first.record.app ?? "program") \(first.reason)"
        return holding.count > 1 ? "\(label) (+\(holding.count - 1))" : label
    }

    // MARK: Debug

    /// `state.txt` and `events.log` are rewritten as things change, so the
    /// current picture is always one `cat` away.
    let debugDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "agry")
    private var lastStateText = ""

    func stateDescription() -> String {
        var lines = [
            "holding: \(decision.isHolding)  assertion: \(summary(of: decision))",
            "onAC: \(power.onAC)  rex: \(rex.isConnected) \(rex.rexURL?.path ?? "-")",
            "awayMode: \(forceRemote)  remotePIDs: \(remotePIDs.sorted())",
            "nextDeadline: \(decision.nextDeadline.map { "\($0)" } ?? "-")",
            "records:",
        ]
        for verdict in decision.verdicts {
            let r = verdict.record
            lines.append("  \(r.source) state=\(r.state.rawValue)\(r.kind.map { "/\($0)" } ?? "") app=\(r.app ?? "-") "
                + "pid=\(r.ownerPID.map(String.init) ?? "-") since=\(r.stateSince) remote=\(verdict.isRemote) "
                + "hold=\(verdict.holdUntil.map { "\($0)" } ?? "no") reason=\(verdict.reason)")
        }
        lines.append("claude sessions:")
        for session in claudeSessions {
            lines.append("  pid=\(session.pid) status=\(session.rawStatus ?? "-") remote=\(session.isRemote) cwd=\(session.cwd ?? "-")")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func writeDebugState() {
        // Times in the text change only when state changes, so this skips most writes.
        let text = stateDescription()
        guard text != lastStateText else { return }
        lastStateText = text
        try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        try? text.write(to: debugDirectory.appending(path: "state.txt"), atomically: true, encoding: .utf8)
        try? log.joined(separator: "\n").write(to: debugDirectory.appending(path: "events.log"), atomically: true, encoding: .utf8)
    }

    func note(_ line: String) {
        let stamp = Date().formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: .current, calendar: .current))
        log.append("\(stamp) \(line)")
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
