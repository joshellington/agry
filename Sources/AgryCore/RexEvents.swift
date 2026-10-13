import Foundation

/// A program status record as Rex reports it (`msg` and `title` arrive decoded).
public struct RexStatus: Equatable, Sendable {
    public var recordID: String
    public var state: ProgramState
    public var app: String?
    public var kind: String?
    public var message: String?
    public var ownerPID: Int32?
    /// Rex's last-report time. Lets a snapshot taken at launch keep the age of
    /// an old `done` record instead of restarting its linger.
    public var updatedAt: Date?

    public func record(blockID: String, observedAt now: Date) -> StatusRecord {
        StatusRecord(
            source: .rex(blockID: blockID, recordID: recordID),
            state: state, app: app, kind: kind, message: message,
            ownerPID: ownerPID, stateSince: min(updatedAt ?? now, now))
    }
}

/// The subset of Rex events agry acts on.
public enum RexEvent: Equatable, Sendable {
    /// agry's watch script finished its startup snapshot.
    case ready
    case sessionCreated(sessionID: String)
    case sessionDestroyed(sessionID: String)
    case statusChanged(sessionID: String, blockID: String, status: RexStatus)
    case statusRemoved(sessionID: String, blockID: String, recordIDs: [String])
    case blockClosed(sessionID: String, blockID: String)
}

public enum RexParser {
    /// Parses one line of `rex events --json`. Returns nil for events agry ignores.
    public static func event(fromLine line: some StringProtocol) -> RexEvent? {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        if envelope.type == "agry_ready" { return .ready }
        guard let payload = envelope.payload else { return nil }

        switch envelope.type {
        case "session_created":
            return payload.session.map { .sessionCreated(sessionID: $0.session_id) }
        case "session_destroyed":
            return payload.session_id.map { .sessionDestroyed(sessionID: $0) }
        case "session_event":
            guard let sessionID = payload.session_id, let event = payload.event else { return nil }
            return sessionEvent(event, sessionID: sessionID)
        default:
            return nil
        }
    }

    /// Parses the result of `rex block call program_status`.
    public static func snapshot(fromJSON data: Data) -> [RexStatus] {
        guard let result = try? JSONDecoder().decode(SnapshotResult.self, from: data) else { return [] }
        return result.records.compactMap { $0.status(recordID: nil) }
    }

    /// Parses `rex ls --json` into session ids.
    public static func sessionIDs(fromJSON data: Data) -> [String] {
        guard let result = try? JSONDecoder().decode(SessionList.self, from: data) else { return [] }
        return result.sessions.map(\.session_id)
    }

    /// Parses `rex block ls --json` into terminal block ids.
    public static func terminalBlockIDs(fromJSON data: Data) -> [String] {
        guard let result = try? JSONDecoder().decode(BlockList.self, from: data) else { return [] }
        return result.blocks.filter { $0.creator_name == terminalCreator }.map(\.block_id)
    }

    public static let terminalCreator = "com.superlogical.terminal"

    /// Rex timestamps: RFC 3339 with microseconds and a numeric offset.
    static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: .iso8601))
    }

    private static func sessionEvent(_ event: SessionEvent, sessionID: String) -> RexEvent? {
        guard let payload = event.payload, let blockID = payload.block_id else { return nil }
        switch event.type {
        case "block_closed":
            return .blockClosed(sessionID: sessionID, blockID: blockID)
        case "block_event":
            guard payload.creator_name == terminalCreator, let inner = payload.payload else { return nil }
            switch payload.name {
            case "program_status_changed":
                guard let status = inner.record?.status(recordID: inner.id) else { return nil }
                return .statusChanged(sessionID: sessionID, blockID: blockID, status: status)
            case "program_status_removed":
                return .statusRemoved(sessionID: sessionID, blockID: blockID, recordIDs: inner.ids ?? [])
            default:
                return nil
            }
        default:
            return nil
        }
    }

    // MARK: Wire format

    private struct Envelope: Decodable {
        var type: String
        var payload: Payload?
    }

    private struct Payload: Decodable {
        var session_id: String?
        var session: SessionRef?
        var event: SessionEvent?
    }

    private struct SessionRef: Decodable {
        var session_id: String
    }

    private struct SessionEvent: Decodable {
        var type: String
        var payload: BlockEventPayload?
    }

    private struct BlockEventPayload: Decodable {
        var block_id: String?
        var creator_name: String?
        var name: String?
        var payload: StatusPayload?
    }

    private struct StatusPayload: Decodable {
        var id: String?
        var record: WireRecord?
        var ids: [String]?
    }

    private struct WireRecord: Decodable {
        var id: String?
        var state: String
        var app: String?
        var effective_app: String?
        var kind: String?
        var msg: String?
        var owner: Owner?
        var updated_at: String?

        struct Owner: Decodable {
            var pid: Int32
        }

        func status(recordID: String?) -> RexStatus? {
            guard let state = ProgramState(rawValue: state) else { return nil }
            return RexStatus(
                recordID: recordID ?? id ?? "",
                state: state,
                app: effective_app ?? app,
                kind: kind,
                message: msg,
                ownerPID: owner?.pid,
                updatedAt: updated_at.flatMap(RexParser.parseDate))
        }
    }

    private struct SnapshotResult: Decodable {
        var records: [WireRecord]
    }

    private struct SessionList: Decodable {
        var sessions: [SessionRef]
    }

    private struct BlockList: Decodable {
        var blocks: [Block]

        struct Block: Decodable {
            var block_id: String
            var creator_name: String
        }
    }
}
