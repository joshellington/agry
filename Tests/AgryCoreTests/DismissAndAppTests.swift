import Foundation
import Testing
@testable import AgryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Suite struct DismissTests {
    private func store(_ state: ProgramState, at offset: TimeInterval = 0) -> StatusRecord {
        StatusRecord(source: .rex(blockID: "b", recordID: ""), state: state, stateSince: t0.addingTimeInterval(offset))
    }

    @Test func dismissedRecordDoesNotHold() {
        var records = RecordStore()
        records.apply(store(.done))
        records.dismiss([.rex(blockID: "b", recordID: "")])
        let decision = Policy(isAlive: { _ in true }).evaluate(PolicyInput(records: records.merged(), onAC: true, now: t0))
        #expect(!decision.isHolding)
    }

    @Test func dismissalSurvivesSameStateReports() {
        var records = RecordStore()
        records.apply(store(.done))
        records.dismiss([.rex(blockID: "b", recordID: "")])
        records.apply(store(.done, at: 30))
        #expect(records.records[.rex(blockID: "b", recordID: "")]?.isDismissed == true)
    }

    @Test func stateChangeClearsDismissal() {
        var records = RecordStore()
        records.apply(store(.done))
        records.dismiss([.rex(blockID: "b", recordID: "")])
        records.apply(store(.working, at: 30))
        #expect(records.records[.rex(blockID: "b", recordID: "")]?.isDismissed == false)
    }
}

@Suite struct AppAssertionTests {
    @Test func watchedPIDWithHoldingTypeIsHolding() {
        #expect(AppAssertions.holdingPIDs([7: ["NoIdleSleepAssertion"]], watched: [7]) == [7])
    }

    @Test func unwatchedPIDIsIgnored() {
        #expect(AppAssertions.holdingPIDs([7: ["NoIdleSleepAssertion"]], watched: [8]).isEmpty)
    }

    @Test func nonSleepAssertionIsIgnored() {
        #expect(AppAssertions.holdingPIDs([7: ["PreventUserIdleDisplaySleep"]], watched: [7]).isEmpty)
    }

    @Test func droppedAssertionBecomesDone() {
        let records = AppAssertions.records(holding: [], previouslySeen: [7], names: [7: "Claude"], now: t0)
        #expect(records.map(\.state) == [.done])
    }

    @Test func heldAssertionIsWorking() {
        let records = AppAssertions.records(holding: [7], previouslySeen: [], names: [7: "Claude"], now: t0)
        #expect(records.first?.state == .working && records.first?.title == "Claude")
    }
}
