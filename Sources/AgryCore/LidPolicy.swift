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

    /// macOS sleeps a closed Mac only at the moment the lid closes or its last
    /// display goes away. If agry kept it awake through that moment, nothing
    /// sleeps it later, so agry does once it lets go. `clamshellCausesSleep`
    /// is the kernel's own view, which keeps counting a display that is on
    /// another input; `externalDisplay` double-checks it.
    public static func shouldSleepAfterDisarm(lidClosed: Bool, clamshellCausesSleep: Bool, externalDisplay: Bool) -> Bool {
        lidClosed && clamshellCausesSleep && !externalDisplay
    }
}

/// Reads the system's actual disablesleep flag from `pmset -g` output, so a
/// flag cleared by another tool can be noticed and re-applied.
public enum PmsetOutput {
    /// `SleepDisabled 1` → true, `0` → false, missing → nil.
    public static func sleepDisabled(from output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" { return fields[1] == "1" }
        }
        return nil
    }

    /// The idle sleep timer in use, in minutes: `sleep 1` → 1, `sleep 0` (never) → 0.
    public static func systemSleepMinutes(from output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "sleep" { return Int(fields[1]) }
        }
        return nil
    }
}
