
import Foundation
import Testing
@testable import PleviCore

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - PlaylistsStore.sorted — pure, no networking, no @MainActor needed
@Suite("PlaylistsStore.sorted")
struct PlaylistsStoreSortedTests {
    private func playlist(id: String, name: String?, channel: String?) -> Playlist {
        Playlist(playlistId: id, playlistName: name, playlistChannel: channel)
    }

    @Test("sorts by name, ascending and descending, case-insensitively")
    func sortsByName() {
        let playlists = [
            playlist(id: "1", name: "banana Uploads", channel: "Z"),
            playlist(id: "2", name: "Apple Uploads", channel: "A"),
            playlist(id: "3", name: "cherry Uploads", channel: "M")
        ]
        let asc = PlaylistsStore.sorted(playlists, field: .name, order: .asc)
        #expect(asc.map(\.id) == ["2", "1", "3"])

        let desc = PlaylistsStore.sorted(playlists, field: .name, order: .desc)
        #expect(desc.map(\.id) == ["3", "1", "2"])
    }

    @Test("sorts by channel, independent of name order")
    func sortsByChannel() {
        let playlists = [
            playlist(id: "1", name: "Z Playlist", channel: "banana"),
            playlist(id: "2", name: "A Playlist", channel: "apple"),
            playlist(id: "3", name: "M Playlist", channel: "cherry")
        ]
        let asc = PlaylistsStore.sorted(playlists, field: .channel, order: .asc)
        #expect(asc.map(\.id) == ["2", "1", "3"])

        let desc = PlaylistsStore.sorted(playlists, field: .channel, order: .desc)
        #expect(desc.map(\.id) == ["3", "1", "2"])
    }

    @Test("a nil name/channel sorts as an empty string, not crashing or reordering unpredictably")
    func nilFieldsSortFirst() {
        let playlists = [
            playlist(id: "1", name: "Named", channel: nil),
            playlist(id: "2", name: nil, channel: nil)
        ]
        let asc = PlaylistsStore.sorted(playlists, field: .name, order: .asc)
        #expect(asc.map(\.id) == ["2", "1"]) // "" sorts before "Named"
    }
}

extension MockedNetworkTests {

@MainActor
@Suite("PlaylistsStore", .serialized)
struct PlaylistsStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func makePlaylist(id: String, type: String = "regular", subscribed: Bool = false) -> Playlist {
        Playlist(playlistId: id, playlistName: "Playlist \(id)", playlistSubscribed: subscribed, playlistType: type)
    }

    private nonisolated func pageBody(_ playlists: [Playlist], currentPage: Int, lastPage: Int) -> Data {
        let paginate = Paginate(
            pageSize: playlists.count,
            pageFrom: 0,
            prevPages: currentPage > 1 ? Array(1..<currentPage) : [],
            currentPage: currentPage,
            maxHits: nil,
            lastPage: lastPage,
            nextPages: currentPage < lastPage ? Array((currentPage + 1)...lastPage) : [],
            totalHits: playlists.count
        )
        let page = Paginated(data: playlists, paginate: paginate)
        return try! JSONEncoder().encode(page)
    }

    @Test("loadFirstPage adds subscribed=true only when the setting is on, and dedupes repeat calls")
    func loadFirstPageHonorsSubscribedOnlyAndDedupes() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "playlists.\(UUID().uuidString)")!)
        let store = PlaylistsStore(client: client, appSettings: settings)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("subscribed=true") != true)
            let body = self.pageBody([self.makePlaylist(id: "p1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadFirstPage()
        #expect(store.items.map(\.id) == ["p1"])
        #expect(requestCount.value == 1)

        // Same settings/filter: no new network call.
        await store.loadFirstPage()
        #expect(requestCount.value == 1)

        // Flip the setting: a new request is made, this time with the filter.
        settings.playlistsSubscribedOnly = true
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("subscribed=true") == true)
            let body = self.pageBody([self.makePlaylist(id: "p2", subscribed: true)], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPage()
        #expect(requestCount.value == 2)
        #expect(store.items.map(\.id) == ["p2"])
    }

    @Test("typeFilter adds a type query item and triggers a re-fetch on change")
    func typeFilterChangesQuery() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "playlists.\(UUID().uuidString)")!)
        let store = PlaylistsStore(client: client, appSettings: settings)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("type=") != true)
            let body = self.pageBody([self.makePlaylist(id: "regular1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPage()
        #expect(requestCount.value == 1)

        store.typeFilter = .custom
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("type=custom") == true)
            let body = self.pageBody([self.makePlaylist(id: "custom1", type: "custom")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPage()
        #expect(requestCount.value == 2)
        #expect(store.items.map(\.id) == ["custom1"])
    }

    @Test("loadNextPageIfNeeded fetches and appends the next page near the end")
    func infiniteScrollAppendsNextPage() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "playlists.\(UUID().uuidString)")!)
        let store = PlaylistsStore(client: client, appSettings: settings)

        let firstPage = [makePlaylist(id: "p1"), makePlaylist(id: "p2")]
        MockURLProtocol.handler = { request in
            let page = (request.url?.query ?? "").contains("page=2") ? 2 : 1
            if page == 1 {
                let body = self.pageBody(firstPage, currentPage: 1, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            } else {
                let body = self.pageBody([self.makePlaylist(id: "p3")], currentPage: 2, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
        }

        await store.loadFirstPage(force: true)
        #expect(store.items.count == 2)

        await store.loadNextPageIfNeeded(currentItem: store.items[1])
        #expect(store.items.count == 3)
        #expect(store.items.last?.id == "p3")
    }

    @Test("resort() re-sorts the already-loaded items with no new network call")
    func resortSortsWithoutRefetching() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "playlists.\(UUID().uuidString)")!)
        let store = PlaylistsStore(client: client, appSettings: settings)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            let body = self.pageBody(
                [self.makePlaylist(id: "banana"), self.makePlaylist(id: "apple"), self.makePlaylist(id: "cherry")],
                currentPage: 1,
                lastPage: 1
            )
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPage()
        // Default sort is by name, ascending — "Playlist apple" < "Playlist banana" < "Playlist cherry" alphabetically.
        #expect(store.items.map(\.id) == ["apple", "banana", "cherry"])
        #expect(requestCount.value == 1)

        settings.playlistsSortOrder = .desc
        store.resort()
        #expect(store.items.map(\.id) == ["cherry", "banana", "apple"])
        // Flipping the order re-sorted in place — no new request fired.
        #expect(requestCount.value == 1)
    }
}

}
