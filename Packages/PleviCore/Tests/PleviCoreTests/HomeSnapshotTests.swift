import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("HomeSnapshot")
struct HomeSnapshotTests {
    private func video(_ id: String) throws -> Video {
        try JSONDecoder().decode(Video.self, from: Data("{\"youtube_id\":\"\(id)\",\"title\":\"Title \(id)\"}".utf8))
    }

    private func temporaryStore() -> HomeSnapshotStore {
        HomeSnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("home-snapshots-\(UUID().uuidString)"))
    }

    private func makeHomeStore(snapshots: HomeSnapshotStore, scope: String) -> HomeStore {
        let client = TAClient(serverURL: URL(string: "https://example.test")!, credentialStore: InMemoryCredentialStore())
        let settings = AppSettings(defaults: UserDefaults(suiteName: "homesnapshot.\(UUID().uuidString)")!)
        return HomeStore(client: client, appSettings: settings, snapshots: snapshots, snapshotScope: scope)
    }

    @Test("a snapshot survives a save and a load, per server")
    func roundTripPerServer() throws {
        let store = temporaryStore()
        let snapshot = HomeSnapshot(continueWatching: [try video("a")], newlyAdded: [try video("b"), try video("c")], queryKey: "k")
        store.save(snapshot, scope: "https://one.test")

        let loaded = store.load(scope: "https://one.test")
        #expect(loaded?.continueWatching.map(\.id) == ["a"])
        #expect(loaded?.newlyAdded.map(\.id) == ["b", "c"])
        #expect(store.load(scope: "https://two.test") == nil)
    }

    @Test("only the first page of the grid is kept")
    func gridIsTrimmed() throws {
        let store = temporaryStore()
        let many = try (0..<(HomeSnapshotStore.gridLimit + 10)).map { try video("v\($0)") }
        store.save(HomeSnapshot(continueWatching: [], newlyAdded: many, queryKey: "k"), scope: "s")
        #expect(store.load(scope: "s")?.newlyAdded.count == HomeSnapshotStore.gridLimit)
    }

    @Test("a new Home store shows the snapshot before any fetch")
    func homeStoreSeedsFromSnapshot() throws {
        let snapshots = temporaryStore()
        snapshots.save(HomeSnapshot(continueWatching: [try video("cw")], newlyAdded: [try video("n1")], queryKey: "some-other-query"), scope: "s")

        let seeded = makeHomeStore(snapshots: snapshots, scope: "s")
        guard case .loaded(let watching) = seeded.continueWatching else {
            Issue.record("Continue Watching was not seeded")
            return
        }
        #expect(watching.map(\.id) == ["cw"])
        // Saved under a different query than this store's settings produce, so the grid is not shown.
        #expect(seeded.gridItems.isEmpty)
    }

    @Test("without a snapshot the store starts empty, as before")
    func noSnapshotStartsEmpty() {
        let store = makeHomeStore(snapshots: temporaryStore(), scope: "nothing-saved")
        #expect(store.gridItems.isEmpty)
        if case .idle = store.continueWatching {} else { Issue.record("expected .idle") }
    }

    @Test("a play arriving after Home loaded moves that video to the front of Continue Watching")
    func historyChangeReordersLoadedRow() throws {
        let snapshots = temporaryStore()
        snapshots.save(HomeSnapshot(continueWatching: [try video("a"), try video("b"), try video("c")], newlyAdded: [], queryKey: "k"), scope: "s")
        let history = PlaybackHistory(scope: "s", defaults: UserDefaults(suiteName: "homehist.\(UUID().uuidString)")!, cloud: nil)
        let client = TAClient(serverURL: URL(string: "https://example.test")!, credentialStore: InMemoryCredentialStore())
        let settings = AppSettings(defaults: UserDefaults(suiteName: "homehist.\(UUID().uuidString)")!)
        let store = HomeStore(client: client, appSettings: settings, playbackHistory: history, snapshots: snapshots, snapshotScope: "s")

        history.record("c")
        store.reapplyHistoryOrdering()

        guard case .loaded(let items) = store.continueWatching else {
            Issue.record("row not loaded")
            return
        }
        #expect(items.map(\.id) == ["c", "a", "b"])
    }
}
