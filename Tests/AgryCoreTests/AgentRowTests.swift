import Foundation
import Testing
@testable import AgryCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func verdict(_ source: RecordSource, _ state: ProgramState, pid: Int32? = 1, title: String? = nil,
                     hold: TimeInterval? = 60, remote: Bool = false) -> RecordVerdict {
    let record = StatusRecord(source: source, state: state, app: "claude-code", title: title, ownerPID: pid, stateSince: now)
    return RecordVerdict(record: record, holdUntil: hold.map { now.addingTimeInterval($0) }, isRemote: remote, reason: state.rawValue)
}

private func session(pid: Int32, cwd: String) -> ClaudeSession {
    ClaudeSession(pid: pid, sessionID: nil, cwd: cwd, name: nil, state: .working, rawStatus: "busy", isRemote: true)
}

private func rows(_ verdicts: [RecordVerdict], sessions: [ClaudeSession] = []) -> [AgentRow] {
    AgentRow.build(Decision(verdicts: verdicts, isHolding: true, nextDeadline: nil), sessions: sessions)
}

@Suite struct AgentRowTests {
    @Test func childRecordsFoldIntoTheirBlock() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: ""), .working),
            verdict(.rex(blockID: "b", recordID: "a1"), .working, title: "Playback engine"),
        ])
        #expect(result.count == 1)
        #expect(result[0].childTitles == ["Playback engine"])
    }

    @Test func rowUsesRootRecordState() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: "a1"), .working, title: "child"),
            verdict(.rex(blockID: "b", recordID: ""), .blocked),
        ])
        #expect(result[0].state == .blocked)
    }

    @Test func holdIsLatestAcrossChildren() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: ""), .done, hold: 60),
            verdict(.rex(blockID: "b", recordID: "a1"), .working, hold: 600),
        ])
        #expect(result[0].holdUntil == now.addingTimeInterval(600))
    }

    @Test func claudeSessionNamesRowAfterProject() {
        let result = rows([verdict(.rex(blockID: "b", recordID: ""), .working, pid: 42)],
                          sessions: [session(pid: 42, cwd: "/Users/dev/Projects/raydio")])
        #expect(result[0].name == "raydio")
    }

    @Test func holdingRowsSortFirst() {
        let result = rows([
            verdict(.rex(blockID: "a", recordID: ""), .idle, hold: nil),
            verdict(.rex(blockID: "z", recordID: ""), .working),
        ])
        #expect(result.map(\.id) == ["rex:z", "rex:a"])
    }

    @Test func remoteOnlyCountsWhileHolding() {
        let result = rows([verdict(.rex(blockID: "b", recordID: ""), .done, hold: nil, remote: true)])
        #expect(result[0].isRemote == false)
    }
}

@Suite struct AgentRowDetailTests {
    @Test func rowCarriesAllSourcesForDismissal() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: ""), .working),
            verdict(.rex(blockID: "b", recordID: "a1"), .working, title: "child"),
        ])
        #expect(Set(result[0].sources) == [.rex(blockID: "b", recordID: ""), .rex(blockID: "b", recordID: "a1")])
    }

    @Test func childKeepsItsOwnState() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: ""), .working),
            verdict(.rex(blockID: "b", recordID: "a1"), .blocked, title: "child"),
        ])
        #expect(result[0].children.first?.state == .blocked)
    }

    @Test func rexOriginKeepsBlockID() {
        #expect(rows([verdict(.rex(blockID: "b", recordID: ""), .working)])[0].origin == .rex(blockID: "b"))
    }

    @Test func blockedRowWithWorkingChildHoldsForWork() {
        let result = rows([
            verdict(.rex(blockID: "b", recordID: ""), .blocked),
            verdict(.rex(blockID: "b", recordID: "a1"), .working, title: "child"),
        ])
        #expect(result[0].isHoldingForWork)
    }

    @Test func doneRowDoesNotHoldForWork() {
        #expect(!rows([verdict(.rex(blockID: "b", recordID: ""), .done)])[0].isHoldingForWork)
    }

    @Test func remoteControlFlagComesFromSession() {
        let result = rows([verdict(.rex(blockID: "b", recordID: ""), .working, pid: 42)],
                          sessions: [session(pid: 42, cwd: "/p/raydio")])
        #expect(result[0].remoteControlEnabled)
    }
}
