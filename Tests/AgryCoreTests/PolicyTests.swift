import Foundation
import Testing
@testable import AgryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private let minute: TimeInterval = 60

private func record(
    _ state: ProgramState,
    since: TimeInterval = 0,
    pid: Int32? = 100,
    source: RecordSource = .rex(blockID: "b1", recordID: "")
) -> StatusRecord {
    StatusRecord(source: source, state: state, app: "claude-code", ownerPID: pid, stateSince: t0.addingTimeInterval(since))
}

private func evaluate(
    _ records: [StatusRecord],
    at offset: TimeInterval,
    onAC: Bool = true,
    remotePIDs: Set<Int32> = [],
    lastInput: TimeInterval? = -60,
    alive: Bool = true
) -> Decision {
    Policy(isAlive: { _ in alive }).evaluate(PolicyInput(
        records: records, onAC: onAC, remotePIDs: remotePIDs,
        lastLocalInput: lastInput.map { t0.addingTimeInterval($0) },
        now: t0.addingTimeInterval(offset)))
}

@Suite struct PolicyTests {
    @Test func noRecordsDoesNotHold() {
        let decision = evaluate([], at: 0)
        #expect(!decision.isHolding)
        #expect(decision.nextDeadline == nil)
    }

    @Test func workingHolds() {
        #expect(evaluate([record(.working)], at: 3 * 3600).isHolding)
    }

    @Test func workingReleasesAfterCapOnAC() {
        #expect(!evaluate([record(.working)], at: 4 * 3600 + 1).isHolding)
    }

    @Test func workingCapIsShorterOnBattery() {
        #expect(!evaluate([record(.working)], at: 3600 + 1, onAC: false).isHolding)
    }

    @Test func idleDoesNotHold() {
        #expect(!evaluate([record(.idle)], at: 1).isHolding)
    }

    @Test func doneHoldsForFinishedLinger() {
        #expect(evaluate([record(.done)], at: 4 * minute).isHolding)
    }

    @Test func doneReleasesAfterFinishedLinger() {
        #expect(!evaluate([record(.done)], at: 5 * minute + 1).isHolding)
    }

    @Test func errorUsesFinishedLingerOnBattery() {
        #expect(!evaluate([record(.error)], at: 2 * minute + 1, onAC: false).isHolding)
    }

    @Test func blockedHoldsLongerThanDone() {
        #expect(evaluate([record(.blocked)], at: 29 * minute).isHolding)
    }

    @Test func blockedReleasesOnBatterySooner() {
        #expect(!evaluate([record(.blocked)], at: 10 * minute + 1, onAC: false).isHolding)
    }

    @Test func remoteExtendsDone() {
        #expect(evaluate([record(.done)], at: 59 * minute, remotePIDs: [100]).isHolding)
    }

    @Test func remoteExtendsIdle() {
        #expect(evaluate([record(.idle)], at: 59 * minute, remotePIDs: [100]).isHolding)
    }

    @Test func remoteExtensionEnds() {
        #expect(!evaluate([record(.idle)], at: 60 * minute + 1, remotePIDs: [100]).isHolding)
    }

    @Test func remoteMatchesClaudeSessionSource() {
        let r = record(.idle, pid: nil, source: .claudeSession(pid: 100))
        #expect(evaluate([r], at: 10 * minute, remotePIDs: [100]).isHolding)
    }

    @Test func localInputAfterStateCancelsRemoteExtension() {
        #expect(!evaluate([record(.done)], at: 30 * minute, remotePIDs: [100], lastInput: 10).isHolding)
    }

    @Test func unknownLastInputIsNotRemote() {
        #expect(!evaluate([record(.done)], at: 30 * minute, remotePIDs: [100], lastInput: nil).isHolding)
    }

    @Test func remoteNeedsRemoteControlEnabled() {
        #expect(!evaluate([record(.done)], at: 30 * minute, remotePIDs: [7]).isHolding)
    }

    @Test func remoteIsReportedOnVerdict() {
        #expect(evaluate([record(.blocked)], at: 1, remotePIDs: [100]).verdicts.first?.isRemote == true)
    }

    @Test func deadOwnerReleasesEvenWhenWorking() {
        #expect(!evaluate([record(.working)], at: 1, alive: false).isHolding)
    }

    @Test func manualHoldUsesExpiry() {
        var r = record(.working, pid: nil, source: .manual)
        r.expiresAt = t0.addingTimeInterval(15 * minute)
        #expect(evaluate([r], at: 14 * minute).isHolding)
        #expect(!evaluate([r], at: 15 * minute).isHolding)
    }

    @Test func nextDeadlineIsEarliestActiveHold() {
        let done = record(.done, source: .rex(blockID: "b1", recordID: ""))
        let blocked = record(.blocked, source: .rex(blockID: "b2", recordID: ""))
        let decision = evaluate([done, blocked], at: 1)
        #expect(decision.nextDeadline == t0.addingTimeInterval(5 * minute))
    }

    @Test func nextDeadlineSkipsExpiredHolds() {
        let done = record(.done, source: .rex(blockID: "b1", recordID: ""))
        let blocked = record(.blocked, source: .rex(blockID: "b2", recordID: ""))
        let decision = evaluate([done, blocked], at: 6 * minute)
        #expect(decision.nextDeadline == t0.addingTimeInterval(30 * minute))
    }
}
