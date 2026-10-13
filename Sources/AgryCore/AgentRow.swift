import Foundation

/// One line in the panel: a terminal block, Claude session or manual hold,
/// with its child records (e.g. subagents) folded in.
public struct AgentRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var app: String?
    public var state: ProgramState
    public var kind: String?
    public var message: String?
    /// Latest hold across the row and its children; nil when not holding.
    public var holdUntil: Date?
    public var isRemote: Bool
    public var isManual: Bool
    public var reason: String
    public var childTitles: [String]

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
            let children = verdicts.filter { $0 != primary }
            let record = primary.record
            let session = record.ownerPID.flatMap { sessionsByPID[$0] }
            return AgentRow(
                id: key,
                name: displayName(record, session: session),
                app: record.app,
                state: record.state,
                kind: record.kind,
                message: record.message ?? record.title,
                holdUntil: verdicts.compactMap(\.holdUntil).max(),
                isRemote: verdicts.contains { $0.isRemote && $0.holdUntil != nil },
                isManual: record.source == .manual,
                reason: primary.reason,
                childTitles: children.map { $0.record.title ?? $0.record.app ?? "task" })
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
        case .manual: "manual"
        }
    }

    private static func isRoot(_ source: RecordSource) -> Bool {
        if case .rex(_, let recordID) = source { return recordID.isEmpty }
        return true
    }

    private static func displayName(_ record: StatusRecord, session: ClaudeSession?) -> String {
        if record.source == .manual { return "Manual" }
        if let cwd = session?.cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return record.title ?? record.app ?? "program"
    }
}
