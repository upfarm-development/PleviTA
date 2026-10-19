import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineProgressPolicy")
struct OfflineProgressPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("an ordinary fresh position entry is flushed")
    func freshPositionFlushes() {
        let entry = OfflineLedgerEntry(position: 42, watched: false, stampedAt: now.timeIntervalSince1970 - 10)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: false, now: now) == .flush)
    }

    @Test("a watched entry always flushes regardless of what the server currently says")
    func watchedEntryAlwaysFlushes() {
        let entry = OfflineLedgerEntry(position: nil, watched: true, stampedAt: now.timeIntervalSince1970 - 10)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: true, now: now) == .flush)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: false, now: now) == .flush)
    }

    @Test("a server that already shows watched drops a leftover position entry")
    func serverWatchedDropsPositionEntry() {
        let entry = OfflineLedgerEntry(position: 42, watched: false, stampedAt: now.timeIntervalSince1970 - 10)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: true, now: now) == .dropServerAlreadyWatched)
    }

    @Test("an entry older than the age cutoff is dropped")
    func tooOldEntryIsDropped() {
        let entry = OfflineLedgerEntry(position: 42, watched: false, stampedAt: now.timeIntervalSince1970 - OfflineProgressPolicy.maxAge - 1)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: false, now: now) == .dropTooOld)
    }

    @Test("an entry right at the cutoff still flushes")
    func rightAtCutoffStillFlushes() {
        let entry = OfflineLedgerEntry(position: 42, watched: false, stampedAt: now.timeIntervalSince1970 - OfflineProgressPolicy.maxAge)
        #expect(OfflineProgressPolicy.decide(entry: entry, serverWatched: false, now: now) == .flush)
    }
}
