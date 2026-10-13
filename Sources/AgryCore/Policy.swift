import Foundation

/// Everything the policy needs to know about the world at one instant.
public struct PolicyInput: Sendable {
    public var records: [StatusRecord]
    public var onAC: Bool
    /// Claude Code pids with remote control enabled.
    public var remotePIDs: Set<Int32>
    /// Last keyboard or mouse input on this Mac. nil means unknown (never away).
    public var lastLocalInput: Date?
    public var now: Date

    public init(records: [StatusRecord], onAC: Bool, remotePIDs: Set<Int32> = [], lastLocalInput: Date? = nil, now: Date) {
        self.records = records
        self.onAC = onAC
        self.remotePIDs = remotePIDs
        self.lastLocalInput = lastLocalInput
        self.now = now
    }
}

public struct RecordVerdict: Equatable, Sendable {
    public var record: StatusRecord
    /// nil means this record does not hold the Mac awake.
    public var holdUntil: Date?
    public var isRemote: Bool
    public var reason: String
}

public struct Decision: Equatable, Sendable {
    public var verdicts: [RecordVerdict]
    public var isHolding: Bool
    /// The earliest future moment a verdict changes; re-evaluate then.
    public var nextDeadline: Date?

    public static let empty = Decision(verdicts: [], isHolding: false, nextDeadline: nil)
}

public struct Policy: Sendable {
    public var config: PolicyConfig
    public var isAlive: @Sendable (Int32) -> Bool

    public init(config: PolicyConfig = .defaults, isAlive: @escaping @Sendable (Int32) -> Bool) {
        self.config = config
        self.isAlive = isAlive
    }

    public func evaluate(_ input: PolicyInput) -> Decision {
        let timeouts = config.timeouts(onAC: input.onAC)
        let verdicts = input.records.map { verdict(for: $0, input: input, timeouts: timeouts) }
        let active = verdicts.compactMap(\.holdUntil).filter { $0 > input.now }
        return Decision(verdicts: verdicts, isHolding: !active.isEmpty, nextDeadline: active.min())
    }

    private func verdict(for record: StatusRecord, input: PolicyInput, timeouts: Timeouts) -> RecordVerdict {
        let remote = isRemote(record, input: input)

        func hold(_ duration: TimeInterval, _ reason: String) -> RecordVerdict {
            let until = record.stateSince.addingTimeInterval(duration)
            let expired = until <= input.now
            return RecordVerdict(
                record: record,
                holdUntil: expired ? nil : until,
                isRemote: remote,
                reason: expired ? "\(reason), expired" : reason
            )
        }

        if let expiresAt = record.expiresAt {
            let live = expiresAt > input.now
            return RecordVerdict(record: record, holdUntil: live ? expiresAt : nil, isRemote: remote,
                                 reason: live ? "manual hold" : "manual hold, expired")
        }
        if let pid = record.ownerPID, !isAlive(pid) {
            return RecordVerdict(record: record, holdUntil: nil, isRemote: remote, reason: "owner process exited")
        }

        let remoteFloor = remote ? timeouts.remote : 0
        switch record.state {
        case .working:
            return hold(timeouts.workingCap, "working")
        case .blocked:
            return hold(max(timeouts.blocked, remoteFloor), remote ? "blocked, remote" : "blocked")
        case .done, .error:
            return hold(max(timeouts.finished, remoteFloor), remote ? "\(record.state.rawValue), remote" : record.state.rawValue)
        case .idle:
            if remote { return hold(remoteFloor, "idle, remote") }
            return RecordVerdict(record: record, holdUntil: nil, isRemote: false, reason: "idle")
        }
    }

    /// A record is remote when its session has remote control enabled and nobody
    /// has touched this Mac since the record entered its state: the user left it
    /// to finish and may answer from their phone. Local input means they saw it.
    private func isRemote(_ record: StatusRecord, input: PolicyInput) -> Bool {
        guard let lastInput = input.lastLocalInput, lastInput < record.stateSince else { return false }
        if case .claudeSession(let pid) = record.source, input.remotePIDs.contains(pid) { return true }
        if let pid = record.ownerPID, input.remotePIDs.contains(pid) { return true }
        return false
    }
}
