import Foundation

/// Reads other apps' sleep assertions (from `IOPMCopyAssertionsByProcess`).
public enum AppAssertions {
    /// Assertion types that mean "this app is keeping the Mac awake".
    public static let holdingTypes: Set<String> = [
        "NoIdleSleepAssertion", "PreventUserIdleSystemSleep", "PreventSystemSleep",
    ]

    /// The watched processes that currently hold a sleep-preventing assertion.
    public static func holdingPIDs(_ typesByPID: [Int32: [String]], watched: Set<Int32>) -> Set<Int32> {
        Set(typesByPID.compactMap { pid, types in
            watched.contains(pid) && types.contains(where: holdingTypes.contains) ? pid : nil
        })
    }

    /// Records for watched apps: `working` while an assertion is held, `done`
    /// once it drops (so the finished-linger applies). Apps never seen holding
    /// produce nothing.
    public static func records(holding: Set<Int32>, previouslySeen: Set<Int32>, names: [Int32: String],
                               now: Date) -> [StatusRecord] {
        holding.union(previouslySeen).sorted().map { pid in
            StatusRecord(source: .app(pid: pid), state: holding.contains(pid) ? .working : .done,
                         app: "claude-desktop", title: names[pid] ?? "app", ownerPID: pid, stateSince: now)
        }
    }
}
