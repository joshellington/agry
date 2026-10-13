import AgryCore
import AppKit
import IOKit.pwr_mgt
import notify

/// Watches the sleep assertions of known agent apps (Claude desktop). Driven by
/// the system's assertion-change notification, so it costs nothing while idle.
@MainActor
final class AppAssertionMonitor {
    static let watchedBundleIDs: Set<String> = ["com.anthropic.claudefordesktop"]

    /// Called with the watched pids currently holding, and their app names.
    var onChange: ((Set<Int32>, [Int32: String]) -> Void)?

    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private var last: Set<Int32> = []

    func start() {
        notify_register_dispatch("com.apple.system.powermanagement.assertions.anychange", &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        rescan()
    }

    func rescan() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            AppAssertionMonitor.watchedBundleIDs.contains($0.bundleIdentifier ?? "")
        }
        let names = Dictionary(apps.map { ($0.processIdentifier, $0.localizedName ?? "app") }, uniquingKeysWith: { a, _ in a })
        let holding = AppAssertions.holdingPIDs(AppAssertionMonitor.assertionTypesByPID(), watched: Set(names.keys))
        guard holding != last else { return }
        last = holding
        onChange?(holding, names)
    }

    private static func assertionTypesByPID() -> [Int32: [String]] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [:] }
        var result: [Int32: [String]] = [:]
        for (pid, assertions) in byProcess {
            result[pid.int32Value] = assertions.compactMap { $0[kIOPMAssertionTypeKey] as? String }
        }
        return result
    }
}
