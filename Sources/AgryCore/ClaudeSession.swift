import Foundation

/// A Claude Code session, from `~/.claude/sessions/<pid>.json`.
///
/// The file format is internal to Claude Code and may change, so every field
/// except `pid` is optional and unknown statuses map to nil.
public struct ClaudeSession: Equatable, Sendable {
    public var pid: Int32
    public var sessionID: String?
    public var cwd: String?
    public var name: String?
    /// `busy` → working, `idle` → idle, anything else → nil.
    public var state: ProgramState?
    public var rawStatus: String?
    /// True when the session is bridged to claude.ai (remote control).
    public var isRemote: Bool

    public static func parse(_ data: Data) -> ClaudeSession? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return ClaudeSession(
            pid: file.pid,
            sessionID: file.sessionId,
            cwd: file.cwd,
            name: file.name,
            state: file.status.flatMap(state(forStatus:)),
            rawStatus: file.status,
            isRemote: !(file.bridgeSessionId ?? "").isEmpty)
    }

    public func record(observedAt now: Date) -> StatusRecord? {
        guard let state else { return nil }
        return StatusRecord(source: .claudeSession(pid: pid), state: state, app: "claude-code",
                            message: name, ownerPID: pid, stateSince: now)
    }

    private static func state(forStatus status: String) -> ProgramState? {
        switch status {
        case "busy": .working
        case "idle": .idle
        default: nil
        }
    }

    private struct File: Decodable {
        var pid: Int32
        var sessionId: String?
        var cwd: String?
        var name: String?
        var status: String?
        var bridgeSessionId: String?
    }
}
