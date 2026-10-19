
import Foundation
import Testing
@testable import PleviCore

extension MockedNetworkTests {

@MainActor
@Suite("ChannelVideoGridStore", .serialized)
struct ChannelVideoGridStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func makeVideo(id: String) -> Video {
        Video(youtubeId: id, title: "Video \(id)")
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
        return try! JSONEncoder().encode(Paginated(data: videos, paginate: paginate))
    }

    @Test("the query uses channelVideoSortField/channelVideoSortOrder, not homeSortField/homeSortOrder")
    func usesItsOwnIndependentSortSetting() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channelgrid.\(UUID().uuidString)")!)
        // Deliberately set Home's own sort to the OPPOSITE of the channel grid's.
        settings.homeSortField = .published
        settings.homeSortOrder = .asc
        settings.channelVideoSortField = .downloaded
        settings.channelVideoSortOrder = .desc

        let store = ChannelVideoGridStore(client: client, appSettings: settings, channelId: "chan1", videoType: .videos)

        MockURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("sort=downloaded"))
            #expect(query.contains("order=desc"))
            #expect(query.contains("channel=chan1"))
            let body = self.pageBody([self.makeVideo(id: "v1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.reload(force: true)
        #expect(store.items.map(\.id) == ["v1"])
    }

    @Test("changing channelVideoSortField triggers a re-fetch, and changing homeSortField does not")
    func onlyItsOwnSettingTriggersARefetch() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channelgrid.\(UUID().uuidString)")!)
        let store = ChannelVideoGridStore(client: client, appSettings: settings, channelId: "chan1", videoType: .videos)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            let body = self.pageBody([self.makeVideo(id: "v1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPageIfNeeded()
        #expect(requestCount.value == 1)

        // Flipping Home's own setting must not move this store's query key.
        settings.homeSortField = .published
        settings.homeSortOrder = .desc
        await store.loadFirstPageIfNeeded()
        #expect(requestCount.value == 1)

        // Flipping this channel's own setting must re-fetch.
        settings.channelVideoSortField = .published
        await store.loadFirstPageIfNeeded()
        #expect(requestCount.value == 2)
    }

    @Test("removeVideoLocally drops the id from items")
    func removeVideoLocallyDropsFromItems() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channelgrid.\(UUID().uuidString)")!)
        let store = ChannelVideoGridStore(client: client, appSettings: settings, channelId: "chan1", videoType: .videos)

        MockURLProtocol.handler = { _ in
            let body = self.pageBody([self.makeVideo(id: "v1"), self.makeVideo(id: "v2")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.reload(force: true)
        #expect(store.items.map(\.id) == ["v1", "v2"])

        store.removeVideoLocally(id: "v1")

        #expect(store.items.map(\.id) == ["v2"])
    }

    @Test("allVideos walks every page, independent of whatever the grid itself has loaded")
    func allVideosWalksEveryPage() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channelgrid.\(UUID().uuidString)")!)
        let store = ChannelVideoGridStore(client: client, appSettings: settings, channelId: "chan1", videoType: .videos)

        MockURLProtocol.handler = { request in
            let page = request.url?.absoluteString.contains("page=2") == true ? 2 : 1
            let videos = page == 1 ? [self.makeVideo(id: "v1"), self.makeVideo(id: "v2")] : [self.makeVideo(id: "v3")]
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.pageBody(videos, currentPage: page, lastPage: 2))
        }

        let all = try await store.allVideos()
        #expect(all.map(\.id) == ["v1", "v2", "v3"])
        // Never touched the grid's own paged state — this is an independent walk.
        #expect(store.items.isEmpty)
    }
}

}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
