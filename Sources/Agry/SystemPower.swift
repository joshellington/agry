import CoreGraphics
import Foundation
import IOKit
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
        batteryPercent = PowerMonitor.readBatteryPercent()
        guard now != onAC else { return }
        onAC = now
        onChange?(now)
    }

    private(set) var batteryPercent = PowerMonitor.readBatteryPercent()

    static func readBatteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return current * 100 / max
        }
        return nil
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

/// When someone last touched the keyboard, mouse or trackpad. Needs no permission.
func lastLocalInput(now: Date = Date()) -> Date {
    let anyInput = CGEventType(rawValue: ~0)!
    return now.addingTimeInterval(-CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput))
}

/// True when the built-in display's lid is closed.
func isLidClosed() -> Bool { rootDomainFlag("AppleClamshellState") }

/// True when macOS would sleep the Mac for a closed lid right now: not in
/// desktop mode with an external display, and `disablesleep` is not set.
func clamshellCausesSleep() -> Bool { rootDomainFlag("AppleClamshellCausesSleep") }

private func rootDomainFlag(_ key: String) -> Bool {
    let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard rootDomain != 0 else { return false }
    defer { IOObjectRelease(rootDomain) }
    let value = IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    return (value as? Bool) ?? false
}

/// True when a display other than the built-in one is online.
func hasExternalDisplay() -> Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
    return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
}

/// `pmset -g`: the settings in use for the current power source.
func readPmsetSettings() -> String? {
    let pmset = Process()
    let pipe = Pipe()
    pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    pmset.arguments = ["-g"]
    pmset.standardOutput = pipe
    pmset.standardError = FileHandle.nullDevice
    guard (try? pmset.run()) != nil else { return nil }
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    pmset.waitUntilExit()
    return output
}

/// Puts the Mac to sleep now. Needs no admin rights.
func sleepNow() {
    let pmset = Process()
    pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    pmset.arguments = ["sleepnow"]
    pmset.standardOutput = FileHandle.nullDevice
    pmset.standardError = FileHandle.nullDevice
    try? pmset.run()
}
