
import Foundation
import Testing
@testable import PleviCore

/// A mutable reference cell so `MockURLProtocol`'s `@Sendable` handler closures can count/inspect requests.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

extension MockedNetworkTests {

@MainActor
@Suite("HomeStore", .serialized)
struct HomeStoreTests {
    // `nonisolated`: constructed and read from inside `MockURLProtocol`'s `@Sendable` handler closure, which runs off the main actor.
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func isLoading<T>(_ state: LoadState<T>) -> Bool {
        if case .loading = state { return true }
        return false
    }

    private nonisolated func makeVideo(id: String, watched: Bool = false, position: Double? = nil) -> Video {
        Video(
            youtubeId: id,
            title: "Video \(id)",
            player: VideoPlayerState(duration: 120, durationStr: "02:00", watched: watched, position: position, progress: position.map { _ in 40 })
        )
    }

    private nonisolated func pageBody(_ videos: [Video], currentPage: Int, lastPage: Int) -> Data {
        let paginate = Paginate(
            pageSize: videos.count,
            pageFrom: 0,
            prevPages: currentPage > 1 ? Array(1..<currentPage) : [],
            currentPage: currentPage,
            maxHits: nil,
            lastPage: lastPage,
            nextPages: currentPage < lastPage ? Array((currentPage + 1)...lastPage) : [],
            totalHits: videos.count
        )
        let page = Paginated(data: videos, paginate: paginate)
        return try! JSONEncoder().encode(page)
    }

    @Test("reloadGrid maps AppSettings into the query and is a no-op when nothing changed")
    func reloadGridUsesSettingsAndDedupes() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        settings.homeSortField = .published
        settings.homeSortOrder = .asc
        settings.hideWatched = true
        let store = HomeStore(client: client, appSettings: settings)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            let query = request.url?.query ?? ""
            #expect(query.contains("sort=published"))
            #expect(query.contains("order=asc"))
            #expect(query.contains("watch=unwatched"))
            let body = self.pageBody([self.makeVideo(id: "v1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.reloadGrid()
        #expect(store.gridItems.map(\.id) == ["v1"])
        #expect(requestCount.value == 1)

        // Same settings again: no new network call.
        await store.reloadGrid()
        #expect(requestCount.value == 1)

        // force: true always re-fetches even if the query didn't change.
        await store.reloadGrid(force: true)
        #expect(requestCount.value == 2)
    }

    @Test("loadNextPageIfNeeded fetches and appends the next page near the end")
    func infiniteScrollAppendsNextPage() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let store = HomeStore(client: client, appSettings: settings)

        let firstPage = (1...10).map { makeVideo(id: "v\($0)") }
        MockURLProtocol.handler = { request in
            let page = (request.url?.query ?? "").contains("page=2") ? 2 : 1
            if page == 1 {
                let body = self.pageBody(firstPage, currentPage: 1, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            } else {
                let body = self.pageBody([self.makeVideo(id: "v11")], currentPage: 2, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
        }

        await store.reloadGrid(force: true)
        #expect(store.gridItems.count == 10)

        // Not near the end yet: no next page fetched.
        await store.loadNextPageIfNeeded(currentItem: store.gridItems[0])
        #expect(store.gridItems.count == 10)

        // Within the prefetch threshold of the end: fetches page 2.
        await store.loadNextPageIfNeeded(currentItem: store.gridItems[9])
        #expect(store.gridItems.count == 11)
        #expect(store.gridItems.last?.id == "v11")
    }

    @Test("setWatched updates local state and removes the video from the grid when hideWatched is on")
    func setWatchedAppliesLocallyAndFiltersWhenHidden() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        settings.hideWatched = true
        let store = HomeStore(client: client, appSettings: settings)

        let videos = [makeVideo(id: "a"), makeVideo(id: "b")]
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/watched") == true || request.url?.absoluteString.contains("/watched/") == true {
                #expect(request.httpMethod == "POST")
                return .init(statusCode: 204)
            }
            let body = self.pageBody(videos, currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.reloadGrid(force: true)
        #expect(store.gridItems.count == 2)

        await store.setWatched(videos[0], isWatched: true)

        // hideWatched is on: the now-watched video drops out of the grid.
        #expect(store.gridItems.map(\.id) == ["b"])
    }

    @Test("setWatched removes a video from continue-watching once marked watched")
    func setWatchedClearsContinueWatching() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let store = HomeStore(client: client, appSettings: settings)

        let inProgress = makeVideo(id: "cw1", watched: false, position: 30)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/watched/") == true {
                return .init(statusCode: 204)
            }
            if (request.url?.query ?? "").contains("watch=continue") {
                let body = self.pageBody([inProgress], currentPage: 1, lastPage: 1)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
            let body = self.pageBody([], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadContinueWatching()
        #expect(store.continueWatching.value?.count == 1)

        await store.setWatched(inProgress, isWatched: true)
        #expect(store.continueWatching.value?.isEmpty == true)
    }

    @Test("continue watching leads with what this user played most recently")
    func continueWatchingLeadsWithRecentlyPlayed() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let history = PlaybackHistory(
            scope: "test",
            defaults: UserDefaults(suiteName: "history.\(UUID().uuidString)")!,
            cloud: nil
        )
        let store = HomeStore(client: client, appSettings: settings, playbackHistory: history)

        // The server's own order is arbitrary — `watch=continue` attaches no sort clause at all,
        // so this is exactly the "whatever Lucene felt like" order the feature exists to replace.
        let serverOrder = [
            makeVideo(id: "first-from-server", watched: false, position: 10),
            makeVideo(id: "watched-on-apple-tv", watched: false, position: 20),
            makeVideo(id: "watched-here-earlier", watched: false, position: 30)
        ]
        let body = pageBody(serverOrder, currentPage: 1, lastPage: 1)
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        history.record("watched-here-earlier", at: Date(timeIntervalSince1970: 100))
        history.record("watched-on-apple-tv", at: Date(timeIntervalSince1970: 500))

        await store.loadContinueWatching()

        // Both known videos lead, newest first; the one nothing has played keeps its place below
        // rather than being given an invented position.
        #expect(store.continueWatching.value?.map(\.id) == [
            "watched-on-apple-tv",
            "watched-here-earlier",
            "first-from-server"
        ])
    }

    @Test("with the setting off, the server's own order is left alone")
    func orderingCanBeTurnedOff() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        settings.recentlyPlayedFirst = false
        let history = PlaybackHistory(
            scope: "test",
            defaults: UserDefaults(suiteName: "history.\(UUID().uuidString)")!,
            cloud: nil
        )
        let store = HomeStore(client: client, appSettings: settings, playbackHistory: history)

        let serverOrder = [
            makeVideo(id: "a", watched: false, position: 10),
            makeVideo(id: "b", watched: false, position: 20)
        ]
        let body = pageBody(serverOrder, currentPage: 1, lastPage: 1)
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        history.record("b", at: Date(timeIntervalSince1970: 900))

        await store.loadContinueWatching()

        #expect(store.continueWatching.value?.map(\.id) == ["a", "b"])
    }

    @Test("a video the user hasn't played on any of their devices is never reordered away")
    func unknownVideosKeepServerOrder() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let history = PlaybackHistory(
            scope: "test",
            defaults: UserDefaults(suiteName: "history.\(UUID().uuidString)")!,
            cloud: nil
        )
        let store = HomeStore(client: client, appSettings: settings, playbackHistory: history)

        let serverOrder = [
            makeVideo(id: "web-ui-1", watched: false, position: 10),
            makeVideo(id: "web-ui-2", watched: false, position: 20)
        ]
        let body = pageBody(serverOrder, currentPage: 1, lastPage: 1)
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        // Played on a device this history has never seen — e.g. Tube Archivist's web UI.
        history.record("something-else-entirely", at: Date(timeIntervalSince1970: 900))

        await store.loadContinueWatching()

        #expect(store.continueWatching.value?.map(\.id) == ["web-ui-1", "web-ui-2"])
    }

    @Test("a refresh never blanks an already-populated continue-watching row")
    func refreshKeepsContinueWatchingOnScreen() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let store = HomeStore(client: client, appSettings: settings)

        let inProgress = makeVideo(id: "cw1", watched: false, position: 30)
        let body = pageBody([inProgress], currentPage: 1, lastPage: 1)
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadContinueWatching()
        #expect(store.continueWatching.value?.count == 1)

        let gate = DispatchSemaphore(value: 0)
        MockURLProtocol.handler = { _ in
            gate.wait()
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        let refresh = Task { await store.loadContinueWatching() }
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.continueWatching.value?.count == 1)
        #expect(isLoading(store.continueWatching) == false)

        gate.signal()
        await refresh.value
        #expect(store.continueWatching.value?.count == 1)
    }

    @Test("a first load, with nothing on screen to protect, still reports .loading")
    func firstContinueWatchingLoadShowsLoading() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let store = HomeStore(client: client, appSettings: settings)

        // The other half of the fix: suppressing `.loading` must apply only
        // when there is already content to keep on screen, or Home would
        // show no spinner at all on a cold start.
        let gate = DispatchSemaphore(value: 0)
        let body = pageBody([], currentPage: 1, lastPage: 1)
        MockURLProtocol.handler = { _ in
            gate.wait()
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        let load = Task { await store.loadContinueWatching() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(isLoading(store.continueWatching) == true)

        gate.signal()
        await load.value
    }

    @Test("removeVideoLocally drops the id from the grid, continue watching, and playback history")
    func removeVideoLocallyDropsAllThree() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let playbackHistory = PlaybackHistory(
            scope: "test-\(UUID().uuidString)", defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!, cloud: nil)
        let store = HomeStore(client: client, appSettings: settings, playbackHistory: playbackHistory)

        MockURLProtocol.handler = { request in
            let videos = (request.url?.query ?? "").contains("watch=continue")
                ? [self.makeVideo(id: "v1"), self.makeVideo(id: "v2")]
                : [self.makeVideo(id: "v1"), self.makeVideo(id: "v3")]
            let body = self.pageBody(videos, currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.refresh()
        playbackHistory.record("v1")

        #expect(store.gridItems.map(\.id).contains("v1"))
        #expect(store.continueWatching.value?.map(\.id).contains("v1") == true)
        #expect(playbackHistory.playedAt["v1"] != nil)

        store.removeVideoLocally(id: "v1")

        #expect(!store.gridItems.map(\.id).contains("v1"))
        // That last assertion is the one guarding the iCloud-sync leak.
        #expect(!(store.continueWatching.value?.map(\.id).contains("v1") ?? false))
        #expect(playbackHistory.playedAt["v1"] == nil)
        // An id this store never held is untouched, not an error.
        store.removeVideoLocally(id: "no-such-id")
    }

    // MARK: - Pinned shelf

    private nonisolated func makePinnedItemsDefaults() -> UserDefaults {
        UserDefaults(suiteName: "pinned.\(UUID().uuidString)")!
    }

    @Test("loadPinned fetches fresh data for each pin and refreshes its snapshot")
    func loadPinnedRefreshesSnapshots() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let pinnedItems = PinnedItems(scope: "test", defaults: makePinnedItemsDefaults(), cloud: nil)
        pinnedItems.pin(Playlist(playlistId: "p1", playlistName: "Old Playlist Name"))
        pinnedItems.pin(Channel(channelId: "c1", channelName: "Old Channel Name"))
        let store = HomeStore(client: client, appSettings: settings, pinnedItems: pinnedItems)

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.contains("/playlist/p1") {
                let body = try! JSONEncoder().encode(Playlist(playlistId: "p1", playlistName: "Fresh Playlist Name"))
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
            if path.contains("/channel/c1") {
                let body = try! JSONEncoder().encode(Channel(channelId: "c1", channelName: "Fresh Channel Name"))
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
            return .init(statusCode: 404)
        }

        await store.loadPinned()

        #expect(store.pinnedPlaylists["p1"]?.playlistName == "Fresh Playlist Name")
        #expect(store.pinnedChannels["c1"]?.channelName == "Fresh Channel Name")
        #expect(pinnedItems.items.first { $0.id == "playlist:p1" }?.title == "Fresh Playlist Name")
        #expect(pinnedItems.items.first { $0.id == "channel:c1" }?.title == "Fresh Channel Name")
    }

    @Test("loadPinned unpins a pin whose fetch 404s")
    func loadPinnedUnpinsOnNotFound() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let pinnedItems = PinnedItems(scope: "test", defaults: makePinnedItemsDefaults(), cloud: nil)
        pinnedItems.pin(Playlist(playlistId: "deleted-on-server", playlistName: "Gone"))
        let store = HomeStore(client: client, appSettings: settings, pinnedItems: pinnedItems)

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }

        await store.loadPinned()

        #expect(!pinnedItems.isPinned(.playlist, id: "deleted-on-server"))
        #expect(store.pinnedPlaylists["deleted-on-server"] == nil)
    }

    @Test("loadPinned keeps the pin and its last-known snapshot on a non-404 error")
    func loadPinnedKeepsPinOnNetworkError() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "home.\(UUID().uuidString)")!)
        let pinnedItems = PinnedItems(scope: "test", defaults: makePinnedItemsDefaults(), cloud: nil)
        pinnedItems.pin(Playlist(playlistId: "p1", playlistName: "Last Known Name"))
        let store = HomeStore(client: client, appSettings: settings, pinnedItems: pinnedItems)

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }

        await store.loadPinned()

        #expect(pinnedItems.isPinned(.playlist, id: "p1"))
        #expect(pinnedItems.items.first { $0.id == "playlist:p1" }?.title == "Last Known Name")
        #expect(store.pinnedPlaylists["p1"] == nil)
    }
}

}
