import Foundation

/// OSC 7501 program states. `clear` is not a state and never reaches the store.
public enum ProgramState: String, Sendable, Codable, CaseIterable {
    case idle, working, done, blocked, error
}

/// Where a record came from. Records from different sources never collide.
public enum RecordSource: Hashable, Sendable {
    /// A Rex terminal block. `recordID` is the OSC 7501 `id` ("" = root record).
    case rex(blockID: String, recordID: String)
    /// A Claude Code session file, keyed by process id.
    case claudeSession(pid: Int32)
    /// A manual hold from the menu.
    case manual
}

/// A program's latest reported status, as seen by agry.
public struct StatusRecord: Equatable, Sendable {
    public var source: RecordSource
    public var state: ProgramState
    public var app: String?
    /// Short label, e.g. a subagent's task name.
    public var title: String?
    public var kind: String?
    public var message: String?
    public var ownerPID: Int32?
    /// When the record entered `state` (agry's clock). Repeated reports in the
    /// same state do not move it, so `done` timeouts run from the first `done`.
    public var stateSince: Date
    /// Explicit expiry, used by manual holds. Overrides the state policy.
    public var expiresAt: Date?

    public init(
        source: RecordSource,
        state: ProgramState,
        app: String? = nil,
        title: String? = nil,
        kind: String? = nil,
        message: String? = nil,
        ownerPID: Int32? = nil,
        stateSince: Date,
        expiresAt: Date? = nil
    ) {
        self.source = source
        self.state = state
        self.app = app
        self.title = title
        self.kind = kind
        self.message = message
        self.ownerPID = ownerPID
        self.stateSince = stateSince
        self.expiresAt = expiresAt
    }
}
