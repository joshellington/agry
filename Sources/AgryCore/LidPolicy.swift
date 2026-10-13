import Foundation

/// Mirrors `ProcessInfo.ThermalState` so the core stays free of app types.
public enum ThermalLevel: Int, Sendable, Comparable {
    case nominal, fair, serious, critical

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Decides whether to arm `pmset disablesleep`, which keeps the Mac awake with
/// the lid closed. It must be armed before the lid closes, so it follows the
/// hold, but only when a closed lid is safe: cool, and either on AC or holding
/// for someone who is away and working remotely.
public struct LidContext: Equatable, Sendable {
    public var enabled: Bool
    public var onAC: Bool
    /// 0–100, nil when there is no battery.
    public var batteryPercent: Int?
    public var thermal: ThermalLevel

    public init(enabled: Bool, onAC: Bool, batteryPercent: Int?, thermal: ThermalLevel) {
        self.enabled = enabled
        self.onAC = onAC
        self.batteryPercent = batteryPercent
        self.thermal = thermal
    }
}

public enum LidVerdict: Equatable, Sendable {
    /// Why lid-closed mode is not keeping the Mac awake right now.
    public enum Reason: Equatable, Sendable {
        /// The user turned the mode off (or it isn't set up).
        case off
        /// Nothing is holding the Mac awake, so there is nothing to protect.
        case nothingToHold
        case tooWarm
        case lowBattery
        /// On battery, lid-closed only applies while away with remote control.
        case batteryNotRemote
    }

    case armed
    case disarmed(Reason)

    public var isArmed: Bool { self == .armed }
}

public enum LidPolicy {
    public static let minimumBatteryPercent = 25

    public static func evaluate(_ decision: Decision, _ context: LidContext) -> LidVerdict {
        guard context.enabled else { return .disarmed(.off) }
        guard decision.isHolding else { return .disarmed(.nothingToHold) }
        guard context.thermal < .serious else { return .disarmed(.tooWarm) }
        if context.onAC { return .armed }
        if let percent = context.batteryPercent, percent < minimumBatteryPercent {
            return .disarmed(.lowBattery)
        }
        let remoteHold = decision.verdicts.contains { $0.isRemote && $0.holdUntil != nil }
        return remoteHold ? .armed : .disarmed(.batteryNotRemote)
    }
}
