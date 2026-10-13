import Foundation

/// Rules for the manual "stay awake" hold.
public enum ManualHold {
    /// Durations offered by the slider, in seconds. `nil` means until stopped,
    /// which is only offered on AC power.
    public static func stops(onAC: Bool) -> [TimeInterval?] {
        let timed: [TimeInterval?] = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480].map { $0 * 60 }
        return onAC ? timed + [nil] : timed
    }

    /// An open-ended hold on battery becomes this long, counted from unplugging.
    public static let batteryCap: TimeInterval = 2 * 3600

    /// The expiry to use for a hold, given the power source. Unlimited holds are
    /// capped on battery; timed holds are left alone.
    public static func expiry(_ requested: Date, onAC: Bool, now: Date) -> Date {
        guard !onAC, requested == .distantFuture else { return requested }
        return now.addingTimeInterval(batteryCap)
    }

    /// Extends a hold by `extra`, from now if it has already lapsed.
    public static func extended(_ expiry: Date, by extra: TimeInterval, now: Date) -> Date {
        guard expiry != .distantFuture else { return expiry }
        return max(expiry, now).addingTimeInterval(extra)
    }
}
