import Foundation

/// Timeouts for one power profile, in seconds.
public struct Timeouts: Equatable, Sendable, Codable {
    /// Longest a single `working` record may hold before it is treated as stuck.
    public var workingCap: TimeInterval
    public var blocked: TimeInterval
    /// Linger after `done` or `error`.
    public var finished: TimeInterval
    /// Minimum hold for any non-working state while remote control is active.
    public var remote: TimeInterval

    public init(workingCap: TimeInterval, blocked: TimeInterval, finished: TimeInterval, remote: TimeInterval) {
        self.workingCap = workingCap
        self.blocked = blocked
        self.finished = finished
        self.remote = remote
    }
}

public struct PolicyConfig: Equatable, Sendable, Codable {
    public var ac: Timeouts
    public var battery: Timeouts

    public init(ac: Timeouts, battery: Timeouts) {
        self.ac = ac
        self.battery = battery
    }

    public func timeouts(onAC: Bool) -> Timeouts { onAC ? ac : battery }

    public static let defaults = PolicyConfig(
        ac: Timeouts(workingCap: 4 * 3600, blocked: 30 * 60, finished: 5 * 60, remote: 60 * 60),
        battery: Timeouts(workingCap: 1 * 3600, blocked: 10 * 60, finished: 2 * 60, remote: 20 * 60)
    )
}
