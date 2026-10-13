import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// One IOPM "prevent idle system sleep" assertion. The display may still sleep.
@MainActor
final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private(set) var isHeld = false
    private var reason = ""

    func set(held: Bool, reason: String) {
        if held {
            // Re-create when the reason changes so `pmset -g assertions` stays accurate.
            if isHeld && reason == self.reason { return }
            release()
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "agry: \(reason)" as CFString,
                &newID)
            if result == kIOReturnSuccess {
                id = newID
                isHeld = true
                self.reason = reason
            }
        } else {
            release()
        }
    }

    private func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        isHeld = false
        reason = ""
    }
}

/// Reports whether the Mac is on AC power, and when that changes.
@MainActor
final class PowerMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var onAC = PowerMonitor.readOnAC()
    private var source: CFRunLoopSource?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ info in
            guard let info else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func refresh() {
        let now = PowerMonitor.readOnAC()
        guard now != onAC else { return }
        onAC = now
        onChange?(now)
    }

    static func readOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return true }
        return (type as String) == kIOPMACPowerKey
    }
}

func isProcessAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}
