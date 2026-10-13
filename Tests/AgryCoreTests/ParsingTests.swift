import Foundation
import Testing
@testable import AgryCore

// Lines captured from `rex events --json` (Rex 0.0.1791811459).
private enum Fixture {
    static let sessionCreated = #"{"type":"session_created","payload":{"session":{"session_id":"session:S","label":"agry-probe"}}}"#
    static let sessionDestroyed = #"{"type":"session_destroyed","payload":{"session_id":"session:S"}}"#
    static let rootWorking = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_event","payload":{"block_id":"block:B","creator_name":"com.superlogical.terminal","name":"program_status_changed","payload":{"id":"","record":{"state":"working","app":"probe","effective_app":"probe","msg":"hi","updated_at":"2026-10-13T13:05:09.415987-06:00","owner":{"pid":96193,"name":"bash"}},"reason":"report"}}}}}"#
    static let childBlocked = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_event","payload":{"block_id":"block:B","creator_name":"com.superlogical.terminal","name":"program_status_changed","payload":{"id":"sub","record":{"id":"sub","state":"blocked","kind":"question","app":"probe","effective_app":"probe","updated_at":"2026-10-13T13:05:10.427416-06:00","owner":{"pid":96193,"name":"bash"}},"reason":"report"}}}}}"#
    static let removed = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_event","payload":{"block_id":"block:B","creator_name":"com.superlogical.terminal","name":"program_status_removed","payload":{"ids":["sub"],"reason":"clear"}}}}}"#
    static let blockClosed = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_closed","payload":{"block_id":"block:B"}}}}"#
    static let processChanged = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_event","payload":{"block_id":"block:B","creator_name":"com.superlogical.terminal","name":"process_changed","payload":{"generation":2}}}}}"#
    static let clientConnected = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"client_connected","payload":{"client_id":"client:C","principal":{"kind":"peer","transport":"unix","uid":501,"pid":73837},"connected_at":"2026-10-13T13:05:07.368773-06:00"}}}}"#
    static let unknownState = #"{"type":"session_event","payload":{"session_id":"session:S","event":{"type":"block_event","payload":{"block_id":"block:B","creator_name":"com.superlogical.terminal","name":"program_status_changed","payload":{"id":"","record":{"state":"sleeping"},"reason":"report"}}}}}"#
    static let snapshot = #"{"records":[{"app":"claude-code","effective_app":"claude-code","msg":"Query","owner":{"name":"2.1.296","pid":87514},"state":"working","updated_at":"2026-10-13T12:56:12.278194-06:00"}]}"#
    static let sessions = #"{"sessions":[{"session_id":"session:A","label":"raydio-fixes"},{"session_id":"session:B","label":"stay-awake"}]}"#
    static let blocks = #"{"blocks":[{"block_id":"block:T","label":"shell","creator_name":"com.superlogical.terminal","placement":"placed"},{"block_id":"block:X","creator_name":"com.example.web","placement":"placed"}]}"#
    static let claudeBusyRemote = #"{"pid":87514,"sessionId":"df28","cwd":"/Users/dev/Projects/agry","kind":"interactive","name":"agry-8f","status":"busy","bridgeSessionId":"session_01Qig"}"#
    static let claudeIdleLocal = #"{"pid":74251,"status":"idle"}"#
    static let claudeOddStatus = #"{"pid":1,"status":"compacting","bridgeSessionId":""}"#
}

@Suite struct RexParserTests {
    @Test func sessionCreated() {
        #expect(RexParser.event(fromLine: Fixture.sessionCreated) == .sessionCreated(sessionID: "session:S"))
    }

    @Test func ready() {
        #expect(RexParser.event(fromLine: #"{"type":"agry_ready"}"#) == .ready)
    }

    @Test func sessionDestroyed() {
        #expect(RexParser.event(fromLine: Fixture.sessionDestroyed) == .sessionDestroyed(sessionID: "session:S"))
    }

    @Test func rootStatusChanged() {
        let expected = RexStatus(recordID: "", state: .working, app: "probe", kind: nil, message: "hi", ownerPID: 96193, updatedAt: Date(timeIntervalSince1970: 1791918309.415987))
        #expect(RexParser.event(fromLine: Fixture.rootWorking) == .statusChanged(sessionID: "session:S", blockID: "block:B", status: expected))
    }

    @Test func childStatusCarriesIDAndKind() {
        guard case .statusChanged(_, _, let status) = RexParser.event(fromLine: Fixture.childBlocked) else {
            Issue.record("expected statusChanged"); return
        }
        #expect(status.recordID == "sub" && status.state == .blocked && status.kind == "question")
    }

    @Test func recordTitle() {
        let json = #"{"records":[{"id":"a47","state":"working","app":"claude-code","title":"Native playback engine"}]}"#
        #expect(RexParser.snapshot(fromJSON: Data(json.utf8)).first?.title == "Native playback engine")
    }

    @Test func statusRemoved() {
        #expect(RexParser.event(fromLine: Fixture.removed) == .statusRemoved(sessionID: "session:S", blockID: "block:B", recordIDs: ["sub"]))
    }

    @Test func blockClosed() {
        #expect(RexParser.event(fromLine: Fixture.blockClosed) == .blockClosed(sessionID: "session:S", blockID: "block:B"))
    }

    @Test(arguments: [Fixture.processChanged, Fixture.clientConnected, Fixture.unknownState, "not json", ""])
    func ignoredLines(_ line: String) {
        #expect(RexParser.event(fromLine: line) == nil)
    }

    @Test func snapshotRecords() {
        let records = RexParser.snapshot(fromJSON: Data(Fixture.snapshot.utf8))
        #expect(records == [RexStatus(recordID: "", state: .working, app: "claude-code", kind: nil, message: "Query", ownerPID: 87514, updatedAt: Date(timeIntervalSince1970: 1791917772.278194))])
    }

    @Test func snapshotRecordKeepsReportedAge() {
        let status = RexParser.snapshot(fromJSON: Data(Fixture.snapshot.utf8))[0]
        let now = Date(timeIntervalSince1970: 1791917772 + 600)
        #expect(status.record(blockID: "b", observedAt: now).stateSince < now.addingTimeInterval(-599))
    }

    @Test func sessionList() {
        #expect(RexParser.sessionIDs(fromJSON: Data(Fixture.sessions.utf8)) == ["session:A", "session:B"])
    }

    @Test func appClient() {
        let json = #"{"clients":[{"client_id":"client:cli","principal":{"pid":5}},{"client_id":"client:app","info":{"kind":"app","name":"Rex Beta"},"principal":{"pid":73837}}]}"#
        let app = RexParser.appClient(fromJSON: Data(json.utf8))
        #expect(app?.clientID == "client:app" && app?.pid == 73837)
    }

    @Test func terminalBlocksOnly() {
        #expect(RexParser.terminalBlockIDs(fromJSON: Data(Fixture.blocks.utf8)) == ["block:T"])
    }
}

@Suite struct ClaudeSessionTests {
    @Test func busyRemoteSession() {
        let session = ClaudeSession.parse(Data(Fixture.claudeBusyRemote.utf8))
        #expect(session?.state == .working)
        #expect(session?.isRemote == true)
    }

    @Test func idleLocalSession() {
        let session = ClaudeSession.parse(Data(Fixture.claudeIdleLocal.utf8))
        #expect(session?.state == .idle)
        #expect(session?.isRemote == false)
    }

    @Test func unknownStatusYieldsNoRecord() {
        let session = ClaudeSession.parse(Data(Fixture.claudeOddStatus.utf8))
        #expect(session?.record(observedAt: Date()) == nil)
        #expect(session?.isRemote == false)
    }

    @Test func garbageIsRejected() {
        #expect(ClaudeSession.parse(Data("{}".utf8)) == nil)
    }
}
