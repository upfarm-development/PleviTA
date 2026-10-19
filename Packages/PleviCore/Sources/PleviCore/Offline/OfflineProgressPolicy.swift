
import Foundation

public enum OfflineProgressPolicy {
    public enum Decision: Sendable, Equatable {
        /// POST this entry's watched flag (if set) or position to the server.
        case flush
        /// The server already has this video marked watched — flushing a leftover position
        /// would only ever be stale next to that, so drop the entry without POSTing anything.
        case dropServerAlreadyWatched
        /// Old enough that acting on it is more likely to be wrong than useful.
        case dropTooOld
    }

    /// How long a failed report stays worth retrying. A month is generous next to how long this
    /// app expects a device to stay offline, while still bounding the ledger against an entry
    /// nobody ever brings back online to flush.
    public static let maxAge: TimeInterval = 60 * 60 * 24 * 30

    public static func decide(entry: OfflineLedgerEntry, serverWatched: Bool?, now: Date) -> Decision {
        if serverWatched == true, !entry.watched {
            return .dropServerAlreadyWatched
        }
        if now.timeIntervalSince1970 - entry.stampedAt > maxAge {
            return .dropTooOld
        }
        return .flush
    }
}
