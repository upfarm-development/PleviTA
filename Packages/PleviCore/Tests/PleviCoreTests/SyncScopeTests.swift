import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("SyncScope")
struct SyncScopeTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "syncscope.\(UUID().uuidString)")! }

    @Test("the local address wins, then the remote, then the sign-in address")
    func order() {
        let local = URL(string: "http://192.168.1.5:8000")!
        let remote = URL(string: "https://ta.example.com")!
        let login = URL(string: "https://login.example.com")!
        #expect(ServerScope.syncScope(local: local, remote: remote, login: login) == local.absoluteString)
        #expect(ServerScope.syncScope(local: nil, remote: remote, login: login) == remote.absoluteString)
        #expect(ServerScope.syncScope(local: nil, remote: nil, login: login) == login.absoluteString)
        #expect(ServerScope.syncScope(local: nil, remote: nil, login: nil) == nil)
    }

    @Test("two devices that signed in differently but share a local address end up with one history")
    func devicesConverge() {
        let phoneDefaults = defaults(), tvDefaults = defaults()
        let phone = PlaybackHistory(scope: "", defaults: phoneDefaults, cloud: nil)
        let tv = PlaybackHistory(scope: "", defaults: tvDefaults, cloud: nil)
        // Before: each filed under its own sign-in address.
        phone.adopt(scope: "https://remote.example.com")
        phone.record("fromPhone", at: Date(timeIntervalSince1970: 100))
        tv.adopt(scope: "http://192.168.1.5:8000")
        tv.record("fromTV", at: Date(timeIntervalSince1970: 200))

        // After: both file under the shared key, carrying the old one over.
        let shared = "http://192.168.1.5:8000"
        phone.adopt(scope: shared, legacyScope: "https://remote.example.com")
        tv.adopt(scope: shared, legacyScope: "http://192.168.1.5:8000")
        #expect(phone.playedAt["fromPhone"] != nil)
        #expect(tv.playedAt["fromTV"] != nil)
    }

    @Test("history carried over from the old key is written to the new one")
    func legacyHistoryIsPersisted() {
        let store = defaults()
        let first = PlaybackHistory(scope: "old", defaults: store, cloud: nil)
        first.record("v1", at: Date(timeIntervalSince1970: 100))

        let second = PlaybackHistory(scope: "", defaults: store, cloud: nil)
        second.adopt(scope: "new", legacyScope: "old")
        #expect(second.playedAt["v1"] == 100)

        let reopened = PlaybackHistory(scope: "new", defaults: store, cloud: nil)
        #expect(reopened.playedAt["v1"] == 100)
    }

    @Test("pins carried over from the old key survive and are kept under the new one")
    func legacyPinsAreCarriedOver() {
        let store = defaults()
        let first = PinnedItems(scope: "old", defaults: store, cloud: nil)
        first.pin(Playlist(playlistId: "p1", playlistName: "Mine"))

        let second = PinnedItems(scope: "", defaults: store, cloud: nil)
        second.adopt(scope: "new", legacyScope: "old")
        #expect(second.isPinned(.playlist, id: "p1"))

        let reopened = PinnedItems(scope: "new", defaults: store, cloud: nil)
        #expect(reopened.isPinned(.playlist, id: "p1"))
    }
}
