import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("OfflinePlaybackLedger")
struct OfflinePlaybackLedgerTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "OfflinePlaybackLedgerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("a failed progress report is recorded and can be cleared")
    func recordsAndClearsFailedProgress() {
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))

        let entry = ledger.entry(for: "v1")
        #expect(entry?.position == 42)
        #expect(entry?.watched == false)

        ledger.clear(videoId: "v1")
        #expect(ledger.entry(for: "v1") == nil)
    }

    @Test("a failed watched report always wins and clears any pending position")
    func failedWatchedWinsOverPosition() {
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))
        ledger.recordFailedWatched(videoId: "v1", at: Date(timeIntervalSince1970: 200))

        let entry = ledger.entry(for: "v1")
        #expect(entry?.watched == true)
        #expect(entry?.position == nil)
    }

    @Test("never un-watch: a later failed position report cannot overwrite an already-watched entry")
    func neverUnwatchesAnAlreadyWatchedEntry() {
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeDefaults())
        ledger.recordFailedWatched(videoId: "v1", at: Date(timeIntervalSince1970: 100))
        ledger.recordFailedProgress(videoId: "v1", position: 5, at: Date(timeIntervalSince1970: 200))

        let entry = ledger.entry(for: "v1")
        #expect(entry?.watched == true, "a stale position report must never downgrade a watched entry")
        #expect(entry?.position == nil)
    }

    @Test("survives a fresh instance against the same defaults and scope")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = OfflinePlaybackLedger(scope: "server-a", defaults: defaults)
        first.recordFailedProgress(videoId: "v1", position: 10, at: Date(timeIntervalSince1970: 100))

        let second = OfflinePlaybackLedger(scope: "server-a", defaults: defaults)
        #expect(second.entry(for: "v1")?.position == 10)
    }

    @Test("two different servers never share a ledger")
    func scopedPerServer() {
        let defaults = makeDefaults()
        let a = OfflinePlaybackLedger(scope: "https://a.example", defaults: defaults)
        a.recordFailedProgress(videoId: "v1", position: 10, at: Date())

        let b = OfflinePlaybackLedger(scope: "https://b.example", defaults: defaults)
        #expect(b.entry(for: "v1") == nil)
    }

    @Test("adopting a new scope switches which entries are visible")
    func adoptSwitchesScope() {
        let defaults = makeDefaults()
        let ledger = OfflinePlaybackLedger(scope: "https://a.example", defaults: defaults)
        ledger.recordFailedProgress(videoId: "v1", position: 10, at: Date())

        ledger.adopt(scope: "https://b.example")
        #expect(ledger.entry(for: "v1") == nil)

        ledger.adopt(scope: "https://a.example")
        #expect(ledger.entry(for: "v1")?.position == 10)
    }

    private func savedVideo(duration: Double?) throws -> Video {
        let player = duration.map { "\"player\":{\"duration\":\($0)}" } ?? "\"title\":\"x\""
        return try JSONDecoder().decode(Video.self, from: Data("{\"youtube_id\":\"v1\",\(player)}".utf8))
    }

    @Test("a saved video gets its progress percentage from the ledger position")
    func ledgerPositionBecomesProgress() throws {
        let entry = OfflineLedgerEntry(position: 50, watched: false, stampedAt: 1)
        let video = try savedVideo(duration: 200).applyingOfflineLedger(entry)
        #expect(video.player?.position == 50)
        #expect(video.player?.progress == 25)
    }

    @Test("a watched ledger entry marks the video watched and draws no progress")
    func ledgerWatchedHasNoProgress() throws {
        let entry = OfflineLedgerEntry(position: nil, watched: true, stampedAt: 1)
        let video = try savedVideo(duration: 200).applyingOfflineLedger(entry)
        #expect(video.player?.watched == true)
        #expect(video.player?.progress == nil)
    }

    @Test("without a ledger entry, or without a duration, the video is left alone")
    func ledgerOverlayIsConservative() throws {
        let original = try savedVideo(duration: 200)
        #expect(original.applyingOfflineLedger(nil) == original)
        let entry = OfflineLedgerEntry(position: 50, watched: false, stampedAt: 1)
        let noDuration = try savedVideo(duration: nil).applyingOfflineLedger(entry)
        #expect(noDuration.player?.progress == nil)
    }

    @Test("the server's state is remembered, but never over something the server is still owed")
    func serverStateRespectsPendingFlush() {
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeDefaults())
        ledger.noteServerState(videoId: "v1", position: 30, watched: false)
        #expect(ledger.entry(for: "v1")?.position == 30)
        #expect(ledger.entry(for: "v1")?.needsFlush == false)

        ledger.noteServerState(videoId: "v1", position: nil, watched: true)
        #expect(ledger.entry(for: "v1")?.watched == true)

        ledger.noteServerState(videoId: "v1", position: nil, watched: false)
        #expect(ledger.entry(for: "v1") == nil)

        ledger.recordFailedProgress(videoId: "v2", position: 99)
        ledger.noteServerState(videoId: "v2", position: 5, watched: false)
        #expect(ledger.entry(for: "v2")?.position == 99)
    }
}
