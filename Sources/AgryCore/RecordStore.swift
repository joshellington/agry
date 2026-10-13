import Foundation

/// The latest record per source. Tracks when each record entered its state.
public struct RecordStore: Sendable {
    public private(set) var records: [RecordSource: StatusRecord] = [:]

    public init() {}

    /// Inserts or replaces a record. Keeps `stateSince` when the state is unchanged.
    public mutating func apply(_ incoming: StatusRecord) {
        var record = incoming
        if let existing = records[incoming.source], existing.state == incoming.state {
            record.stateSince = existing.stateSince
            record.isDismissed = existing.isDismissed
        }
        records[incoming.source] = record
    }

    /// Stops these records holding until each next changes state.
    public mutating func dismiss(_ sources: [RecordSource]) {
        for source in sources { records[source]?.isDismissed = true }
    }

    public mutating func remove(_ source: RecordSource) {
        records[source] = nil
    }

    public mutating func removeAll(where shouldRemove: (RecordSource) -> Bool) {
        records = records.filter { !shouldRemove($0.key) }
    }

    /// Removes every record from one Rex block.
    public mutating func removeBlock(_ blockID: String) {
        removeAll { source in
            if case .rex(let id, _) = source { return id == blockID }
            return false
        }
    }

    /// Removes a Rex record and its children (OSC 7501 `clear` semantics).
    public mutating func removeRexRecord(blockID: String, recordID: String) {
        removeAll { source in
            guard case .rex(let id, let rid) = source, id == blockID else { return false }
            return recordID.isEmpty || rid == recordID || rid.hasPrefix(recordID + "/")
        }
    }

    /// Records for evaluation. A Claude session-file record is dropped when a
    /// Rex record already reports for the same process, so OSC 7501 wins.
    public func merged() -> [StatusRecord] {
        let rexOwners = Set(records.values.compactMap { record -> Int32? in
            if case .rex = record.source { return record.ownerPID }
            return nil
        })
        return records.values
            .filter { record in
                if case .claudeSession(let pid) = record.source { return !rexOwners.contains(pid) }
                return true
            }
            .sorted { $0.stateSince < $1.stateSince }
    }
}
