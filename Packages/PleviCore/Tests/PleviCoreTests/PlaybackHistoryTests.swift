
import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("PlaybackHistory")
struct PlaybackHistoryTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "PlaybackHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("records what was played and returns it newest first")
    func recordsNewestFirst() {
        let history = PlaybackHistory(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        history.record("older", at: Date(timeIntervalSince1970: 100))
        history.record("newest", at: Date(timeIntervalSince1970: 300))
        history.record("middle", at: Date(timeIntervalSince1970: 200))

        #expect(history.mostRecent(limit: 3) == ["newest", "middle", "older"])
    }

    @Test("survives a fresh instance — the storage key must not be seeded per process")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = PlaybackHistory(scope: "server-a", defaults: defaults, cloud: nil)
        first.record("kept", at: Date(timeIntervalSince1970: 500))

        let second = PlaybackHistory(scope: "server-a", defaults: defaults, cloud: nil)
        #expect(second.mostRecent(limit: 5) == ["kept"])
    }

    @Test("two servers keep separate histories — video ids are YouTube ids and collide")
    func scopesAreSeparate() {
        let defaults = makeDefaults()
        let serverA = PlaybackHistory(scope: "https://a.example", defaults: defaults, cloud: nil)
        let serverB = PlaybackHistory(scope: "https://b.example", defaults: defaults, cloud: nil)

        serverA.record("shared-video-id", at: Date(timeIntervalSince1970: 100))

        #expect(serverA.mostRecent(limit: 5) == ["shared-video-id"])
        #expect(serverB.mostRecent(limit: 5).isEmpty)
    }

    @Test("forget drops a video that is no longer in progress")
    func forgetRemoves() {
        let history = PlaybackHistory(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        history.record("watched-later", at: Date(timeIntervalSince1970: 100))
        history.forget("watched-later")

        #expect(history.mostRecent(limit: 5).isEmpty)
    }

    @Test("clear empties the history, for signing out")
    func clearEmpties() {
        let defaults = makeDefaults()
        let history = PlaybackHistory(scope: "server-a", defaults: defaults, cloud: nil)
        history.record("a", at: Date(timeIntervalSince1970: 100))
        history.clear()

        #expect(history.mostRecent(limit: 5).isEmpty)
        let reopened = PlaybackHistory(scope: "server-a", defaults: defaults, cloud: nil)
        #expect(reopened.mostRecent(limit: 5).isEmpty)
    }

    @Test("keeps only the most recent entries once the cap is reached")
    func capsAtCapacity() {
        let history = PlaybackHistory(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        for index in 0..<60 {
            history.record("video\(index)", at: Date(timeIntervalSince1970: Double(index)))
        }

        #expect(history.playedAt.count == 50)
        // The ten oldest are the ones dropped.
        #expect(history.playedAt["video0"] == nil)
        #expect(history.playedAt["video59"] != nil)
    }

    // MARK: - The merge rule, which is what sync correctness rests on

    @Test("a newer timestamp from another device wins")
    func newerRemoteWins() {
        let defaults = makeDefaults()
        let history = PlaybackHistory(scope: "server-a", defaults: defaults, cloud: nil)
        history.record("episode", at: Date(timeIntervalSince1970: 100))

        history.mergeForTesting(["episode": 500])

        #expect(history.playedAt["episode"] == 500)
    }

    @Test("an older timestamp from another device does NOT clobber a newer local one")
    func olderRemoteLoses() {
        let history = PlaybackHistory(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        history.record("episode", at: Date(timeIntervalSince1970: 900))

        history.mergeForTesting(["episode": 100])

        // Whole-dictionary last-writer-wins would have thrown away the newer local play here —
        // watching something on the Apple TV erasing what the phone did this morning.
        #expect(history.playedAt["episode"] == 900)
    }

    @Test("entries only the other device knows about are adopted, not dropped")
    func remoteOnlyEntriesSurvive() {
        let history = PlaybackHistory(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        history.record("from-phone", at: Date(timeIntervalSince1970: 100))

        history.mergeForTesting(["from-apple-tv": 200])

        #expect(history.mostRecent(limit: 5) == ["from-apple-tv", "from-phone"])
    }
}
