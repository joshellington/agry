import Foundation
import Testing
@testable import AgryCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func decision(holding: Bool, remote: Bool = false) -> Decision {
    let record = StatusRecord(source: .manual, state: .done, stateSince: now)
    let verdict = RecordVerdict(record: record, holdUntil: holding ? now.addingTimeInterval(60) : nil,
                                isRemote: remote, reason: "test")
    return Decision(verdicts: [verdict], isHolding: holding, nextDeadline: nil)
}

private func context(enabled: Bool = true, onAC: Bool = true, battery: Int? = 80, thermal: ThermalLevel = .nominal) -> LidContext {
    LidContext(enabled: enabled, onAC: onAC, batteryPercent: battery, thermal: thermal)
}

@Suite struct LidPolicyTests {
    @Test func armsWhileHoldingOnAC() {
        #expect(LidPolicy.evaluate(decision(holding: true), context()).isArmed)
    }

    @Test func disarmedWhenDisabled() {
        #expect(LidPolicy.evaluate(decision(holding: true), context(enabled: false)) == .disarmed(.off))
    }

    @Test func disarmedWhenNotHolding() {
        #expect(LidPolicy.evaluate(decision(holding: false), context()) == .disarmed(.nothingToHold))
    }

    @Test func disarmedWhenSeriouslyWarm() {
        #expect(LidPolicy.evaluate(decision(holding: true), context(thermal: .serious)) == .disarmed(.tooWarm))
    }

    @Test func fairThermalStillArms() {
        #expect(LidPolicy.evaluate(decision(holding: true), context(thermal: .fair)).isArmed)
    }

    @Test func batteryWithoutRemoteDisarms() {
        #expect(LidPolicy.evaluate(decision(holding: true), context(onAC: false)) == .disarmed(.batteryNotRemote))
    }

    @Test func batteryWithRemoteArms() {
        #expect(LidPolicy.evaluate(decision(holding: true, remote: true), context(onAC: false)).isArmed)
    }

    @Test func lowBatteryDisarmsEvenWhenRemote() {
        #expect(LidPolicy.evaluate(decision(holding: true, remote: true), context(onAC: false, battery: 20)) == .disarmed(.lowBattery))
    }
}

@Suite struct SleepAfterDisarmTests {
    @Test func sleepsWhenClosedWithNoDisplay() {
        #expect(LidPolicy.shouldSleepAfterDisarm(lidClosed: true, clamshellCausesSleep: true, externalDisplay: false))
    }

    @Test func staysAwakeWithLidOpen() {
        #expect(!LidPolicy.shouldSleepAfterDisarm(lidClosed: false, clamshellCausesSleep: false, externalDisplay: false))
    }

    @Test func staysAwakeWhenDocked() {
        #expect(!LidPolicy.shouldSleepAfterDisarm(lidClosed: true, clamshellCausesSleep: false, externalDisplay: true))
    }

    /// A display on another input can drop out for a moment while macOS still
    /// counts it as attached.
    @Test func staysAwakeWhenMacOSStillCountsTheDisplay() {
        #expect(!LidPolicy.shouldSleepAfterDisarm(lidClosed: true, clamshellCausesSleep: false, externalDisplay: false))
    }

    @Test func staysAwakeWhileAnExternalDisplayIsOnline() {
        #expect(!LidPolicy.shouldSleepAfterDisarm(lidClosed: true, clamshellCausesSleep: true, externalDisplay: true))
    }
}

@Suite struct PmsetOutputTests {
    private let header = "System-wide power settings:\n"

    @Test func readsSetFlag() {
        #expect(PmsetOutput.sleepDisabled(from: header + " SleepDisabled\t\t1\nCurrently in use:\n") == true)
    }

    @Test func readsClearedFlag() {
        #expect(PmsetOutput.sleepDisabled(from: header + " SleepDisabled\t\t0\n") == false)
    }

    @Test func missingFlagIsUnknown() {
        #expect(PmsetOutput.sleepDisabled(from: "Currently in use:\n sleep 0\n") == nil)
    }

    @Test func readsSystemSleepTimer() {
        #expect(PmsetOutput.systemSleepMinutes(from: "Currently in use:\n displaysleep 60\n sleep                 1\n") == 1)
    }

    @Test func neverSleepReadsAsZero() {
        let output = "Currently in use:\n sleep                0 (sleep prevented by powerd, Agry)\n disksleep 0\n"
        #expect(PmsetOutput.systemSleepMinutes(from: output) == 0)
    }

    @Test func missingSleepTimerIsUnknown() {
        #expect(PmsetOutput.systemSleepMinutes(from: "Currently in use:\n displaysleep 60\n") == nil)
    }
}
