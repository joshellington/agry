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
        #expect(!LidPolicy.evaluate(decision(holding: true), context(enabled: false)).isArmed)
    }

    @Test func disarmedWhenNotHolding() {
        #expect(!LidPolicy.evaluate(decision(holding: false), context()).isArmed)
    }

    @Test func disarmedWhenSeriouslyWarm() {
        #expect(!LidPolicy.evaluate(decision(holding: true), context(thermal: .serious)).isArmed)
    }

    @Test func fairThermalStillArms() {
        #expect(LidPolicy.evaluate(decision(holding: true), context(thermal: .fair)).isArmed)
    }

    @Test func batteryWithoutRemoteDisarms() {
        #expect(!LidPolicy.evaluate(decision(holding: true), context(onAC: false)).isArmed)
    }

    @Test func batteryWithRemoteArms() {
        #expect(LidPolicy.evaluate(decision(holding: true, remote: true), context(onAC: false)).isArmed)
    }

    @Test func lowBatteryDisarmsEvenWhenRemote() {
        #expect(!LidPolicy.evaluate(decision(holding: true, remote: true), context(onAC: false, battery: 20)).isArmed)
    }
}
