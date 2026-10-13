import Foundation

/// One line in the panel: a terminal block, Claude session, app or manual
/// hold, with its child records (e.g. subagents) folded in.
public struct AgentRow: Identifiable, Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case rex(blockID: String)
        case claudeSession
        case app
        case manual

        public var label: String {
            switch self {
            case .rex: "Rex · OSC 7501"
            case .claudeSession: "Claude session file"
            case .app: "App sleep assertion"
            case .manual: "Manual hold"
            }
        }
    }

    public struct Child: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var state: ProgramState
        public var holdUntil: Date?
    }

    public var id: String
    public var name: String
    public var app: String?
    public var origin: Origin
    public var state: ProgramState
    public var kind: String?
    public var message: String?
    /// When the row's main record entered its state.
    public var since: Date
    public var pid: Int32?
    public var cwd: String?
    /// Latest hold across the row and its children; nil when not holding.
    public var holdUntil: Date?
    public var isRemote: Bool
    public var remoteControlEnabled: Bool
    public var isDismissed: Bool
    public var reason: String
    public var children: [Child]
    /// Every record in the row, for acting on it as a whole.
    public var sources: [RecordSource]

    public var isManual: Bool { origin == .manual }
    /// True when the row or any child is working and holding, so its hold
    /// lasts as long as the work rather than a countdown.
    public var isHoldingForWork: Bool {
        guard !isManual else { return false }
        if state == .working && holdUntil != nil { return true }
        return children.contains { $0.state == .working && $0.holdUntil != nil }
    }
    public var childTitles: [String] { children.map(\.title) }

    /// Builds rows from a decision, naming Claude sessions after their project.
    public static func build(_ decision: Decision, sessions: [ClaudeSession]) -> [AgentRow] {
        let sessionsByPID = Dictionary(sessions.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [String: [RecordVerdict]] = [:]
        var order: [String] = []
        for verdict in decision.verdicts {
            let key = groupKey(verdict.record.source)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(verdict)
        }
        return order.compactMap { key in
            guard let verdicts = groups[key] else { return nil }
            let primary = verdicts.first(where: { isRoot($0.record.source) }) ?? verdicts[0]
            let record = primary.record
            let session = record.ownerPID.flatMap { sessionsByPID[$0] }
            return AgentRow(
                id: key,
                name: displayName(record, session: session),
                app: record.app,
                origin: origin(record.source),
                state: record.state,
                kind: record.kind,
                message: detailMessage(record),
                since: record.stateSince,
                pid: record.ownerPID,
                cwd: session?.cwd,
                holdUntil: verdicts.compactMap(\.holdUntil).max(),
                isRemote: verdicts.contains { $0.isRemote && $0.holdUntil != nil },
                remoteControlEnabled: session?.isRemote ?? false,
                isDismissed: record.isDismissed,
                reason: primary.reason,
                children: verdicts.filter { $0 != primary }.map { child in
                    Child(id: "\(child.record.source)",
                          title: child.record.title ?? child.record.app ?? "task",
                          state: child.record.state,
                          holdUntil: child.holdUntil)
                },
                sources: verdicts.map(\.record.source))
        }
        .sorted { lhs, rhs in
            if (lhs.holdUntil != nil) != (rhs.holdUntil != nil) { return lhs.holdUntil != nil }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func groupKey(_ source: RecordSource) -> String {
        switch source {
        case .rex(let blockID, _): "rex:\(blockID)"
        case .claudeSession(let pid): "claude:\(pid)"
        case .app(let pid): "app:\(pid)"
        case .manual: "manual"
        }
    }

    private static func origin(_ source: RecordSource) -> Origin {
        switch source {
        case .rex(let blockID, _): .rex(blockID: blockID)
        case .claudeSession: .claudeSession
        case .app: .app
        case .manual: .manual
        }
    }

    private static func isRoot(_ source: RecordSource) -> Bool {
        if case .rex(_, let recordID) = source { return recordID.isEmpty }
        return true
    }

    /// An app row is already named by its title, so it has no separate message.
    private static func detailMessage(_ record: StatusRecord) -> String? {
        if case .app = record.source { return record.message }
        return record.message ?? record.title
    }

    private static func displayName(_ record: StatusRecord, session: ClaudeSession?) -> String {
        if record.source == .manual { return "Manual" }
        if let cwd = session?.cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return record.title ?? record.app ?? "program"
    }
}
