import Foundation
import Testing
@testable import AgryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func rex(_ block: String, id: String = "", _ state: ProgramState, at offset: TimeInterval = 0, pid: Int32? = nil) -> StatusRecord {
    StatusRecord(source: .rex(blockID: block, recordID: id), state: state, ownerPID: pid, stateSince: t0.addingTimeInterval(offset))
}

@Suite struct RecordStoreTests {
    @Test func sameStateKeepsOriginalSince() {
        var store = RecordStore()
        store.apply(rex("b", .done, at: 0))
        store.apply(rex("b", .done, at: 60))
        #expect(store.records[.rex(blockID: "b", recordID: "")]?.stateSince == t0)
    }

    @Test func stateChangeResetsSince() {
        var store = RecordStore()
        store.apply(rex("b", .working, at: 0))
        store.apply(rex("b", .done, at: 60))
        #expect(store.records[.rex(blockID: "b", recordID: "")]?.stateSince == t0.addingTimeInterval(60))
    }

    @Test func removeBlockDropsAllItsRecords() {
        var store = RecordStore()
        store.apply(rex("b", id: "", .working))
        store.apply(rex("b", id: "child", .working))
        store.apply(rex("other", .working))
        store.removeBlock("b")
        #expect(store.records.count == 1)
    }

    @Test func removeRexRecordDropsChildren() {
        var store = RecordStore()
        store.apply(rex("b", id: "deploy", .working))
        store.apply(rex("b", id: "deploy/us", .working))
        store.apply(rex("b", id: "deployer", .working))
        store.removeRexRecord(blockID: "b", recordID: "deploy")
        #expect(store.records.keys.map { $0 } == [.rex(blockID: "b", recordID: "deployer")])
    }

    @Test func emptyRecordIDClearsBlock() {
        var store = RecordStore()
        store.apply(rex("b", id: "x", .working))
        store.removeRexRecord(blockID: "b", recordID: "")
        #expect(store.records.isEmpty)
    }

    @Test func rexRecordShadowsClaudeSessionForSamePID() {
        var store = RecordStore()
        store.apply(rex("b", .working, pid: 42))
        store.apply(StatusRecord(source: .claudeSession(pid: 42), state: .working, stateSince: t0))
        store.apply(StatusRecord(source: .claudeSession(pid: 7), state: .working, stateSince: t0))
        let sources = Set(store.merged().map(\.source))
        #expect(sources == [.rex(blockID: "b", recordID: ""), .claudeSession(pid: 7)])
    }
}
