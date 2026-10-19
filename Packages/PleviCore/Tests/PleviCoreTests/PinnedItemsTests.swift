
import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("PinnedItems")
struct PinnedItemsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "PinnedItemsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makePlaylist(id: String, name: String = "A Playlist") -> Playlist {
        Playlist(playlistId: id, playlistName: name, playlistChannel: "Some Channel")
    }

    private func makeChannel(id: String, name: String = "A Channel") -> Channel {
        Channel(channelId: id, channelName: name)
    }

    @Test("pin makes it pinned and first; unpin removes it")
    func pinAndUnpin() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "p1"))

        #expect(items.isPinned(.playlist, id: "p1"))
        #expect(items.items.map(\.id) == ["playlist:p1"])

        items.unpin(.playlist, id: "p1")
        #expect(!items.isPinned(.playlist, id: "p1"))
        #expect(items.items.isEmpty)
    }

    @Test("pinning the same target twice leaves one entry, moved to the front")
    func pinTwiceDeduplicatesAndReorders() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "p1"))
        items.pin(makeChannel(id: "c1"))
        items.pin(makePlaylist(id: "p1"))

        #expect(items.items.count == 2)
        #expect(items.items.first?.id == "playlist:p1")
    }

    @Test("a playlist and a channel with the same id string don't collide")
    func kindKeepsIdsDistinct() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "shared-id"))
        items.pin(makeChannel(id: "shared-id"))

        #expect(items.isPinned(.playlist, id: "shared-id"))
        #expect(items.isPinned(.channel, id: "shared-id"))
        #expect(items.items.count == 2)

        items.unpin(.playlist, id: "shared-id")
        #expect(!items.isPinned(.playlist, id: "shared-id"))
        #expect(items.isPinned(.channel, id: "shared-id"))
    }

    @Test("survives a fresh instance reading the same defaults")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = PinnedItems(scope: "server-a", defaults: defaults, cloud: nil)
        first.pin(makePlaylist(id: "kept"))

        let second = PinnedItems(scope: "server-a", defaults: defaults, cloud: nil)
        #expect(second.isPinned(.playlist, id: "kept"))
    }

    @Test("adopt(scope:) to a different server shows a disjoint set")
    func adoptScopesSeparately() {
        let defaults = makeDefaults()
        let items = PinnedItems(scope: "https://a.example", defaults: defaults, cloud: nil)
        items.pin(makePlaylist(id: "p1"))

        items.adopt(scope: "https://b.example")
        #expect(items.items.isEmpty)

        items.adopt(scope: "https://a.example")
        #expect(items.isPinned(.playlist, id: "p1"))
    }

    // MARK: - Merge

    @Test("a local unpin beats an older incoming pin, but a newer incoming re-pin wins")
    func mergeOrdersByLastEvent() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "p1"))
        items.unpin(.playlist, id: "p1") // unpinnedAt ~= now

        // An incoming pin timestamped well before the local unpin must not resurrect it.
        items.mergeForTesting([
            "playlist:p1": PinnedItem(kind: .playlist, targetId: "p1", title: "P1", pinnedAt: 5, unpinnedAt: nil)
        ])
        #expect(!items.isPinned(.playlist, id: "p1"))

        // An incoming re-pin timestamped after the local unpin does win.
        let future = Date().addingTimeInterval(1000).timeIntervalSince1970
        items.mergeForTesting([
            "playlist:p1": PinnedItem(kind: .playlist, targetId: "p1", title: "P1", pinnedAt: future, unpinnedAt: nil)
        ])
        #expect(items.isPinned(.playlist, id: "p1"))

        // An incoming tombstone newer than that re-pin wins in turn.
        let evenLater = future + 1000
        items.mergeForTesting([
            "playlist:p1": PinnedItem(kind: .playlist, targetId: "p1", title: "P1", pinnedAt: future, unpinnedAt: evenLater)
        ])
        #expect(!items.isPinned(.playlist, id: "p1"))
    }

    @Test("entries only the other device knows about are adopted, not dropped")
    func remoteOnlyEntriesSurvive() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "from-phone"))

        items.mergeForTesting([
            "channel:from-apple-tv": PinnedItem(kind: .channel, targetId: "from-apple-tv", title: "TV", pinnedAt: 200)
        ])

        #expect(items.isPinned(.playlist, id: "from-phone"))
        #expect(items.isPinned(.channel, id: "from-apple-tv"))
    }

    @Test("tombstones older than 30 days are trimmed; live pins never are")
    func trimsOldTombstonesOnly() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        let old = Date().addingTimeInterval(-31 * 24 * 60 * 60).timeIntervalSince1970

        items.mergeForTesting([
            "playlist:ancient-tombstone": PinnedItem(kind: .playlist, targetId: "ancient-tombstone", pinnedAt: old - 100, unpinnedAt: old),
            "channel:ancient-live-pin": PinnedItem(kind: .channel, targetId: "ancient-live-pin", pinnedAt: old - 100, unpinnedAt: nil)
        ])

        #expect(items.allEntriesForTesting["playlist:ancient-tombstone"] == nil)
        #expect(items.isPinned(.channel, id: "ancient-live-pin"))
    }

    @Test("isFull at the cap, and pin does nothing past it")
    func capsAtThirtyPins() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        for index in 0..<30 {
            items.pin(makePlaylist(id: "p\(index)"))
        }

        #expect(items.isFull)
        #expect(items.items.count == 30)

        items.pin(makePlaylist(id: "one-too-many"))
        #expect(items.items.count == 30)
        #expect(!items.isPinned(.playlist, id: "one-too-many"))

        // Re-pinning something already live is still allowed at the cap — it doesn't grow
        // `items`, just moves the existing entry to the front.
        items.pin(makePlaylist(id: "p0"))
        #expect(items.items.count == 30)
        #expect(items.items.first?.id == "playlist:p0")
    }

    @Test("refreshSnapshot for an unpinned target does not resurrect it")
    func refreshSnapshotNeverResurrects() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "p1"))
        items.unpin(.playlist, id: "p1")

        items.refreshSnapshot(makePlaylist(id: "p1", name: "Renamed"))
        #expect(!items.isPinned(.playlist, id: "p1"))
    }

    @Test("refreshSnapshot updates the title of a still-pinned target")
    func refreshSnapshotUpdatesLivePin() {
        let items = PinnedItems(scope: "server-a", defaults: makeDefaults(), cloud: nil)
        items.pin(makePlaylist(id: "p1", name: "Old Name"))

        items.refreshSnapshot(makePlaylist(id: "p1", name: "New Name"))
        #expect(items.items.first?.title == "New Name")
    }
}
