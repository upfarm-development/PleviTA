
import Foundation
import Testing
@testable import PleviCore

@Suite("ChannelDetailStore.resolveTabs")
struct ChannelDetailStoreResolveTabsTests {
    @Test("falls back to Videos-only when every nav field is nil (can't parse confidently)")
    func allNilFallsBackToVideos() {
        let nav = ChannelNav(hasVideos: nil, hasStreams: nil, hasShorts: nil, hasPlaylists: nil)
        #expect(ChannelDetailStore.resolveTabs(from: nav) == [.videos])
    }

    @Test("Videos is always included, streams/shorts/playlists only when explicitly true")
    func explicitTrueFieldsAreIncluded() {
        let nav = ChannelNav(hasVideos: true, hasStreams: true, hasShorts: false, hasPlaylists: nil)
        #expect(ChannelDetailStore.resolveTabs(from: nav) == [.videos, .streams])
    }

    @Test("only the video tabs are sortable, so tvOS hides its sort control on Playlists")
    func onlyVideoTabsAreSortable() {
        // `channelVideoSortField`/`channelVideoSortOrder` order a video grid. The
        // Playlists tab lists playlists, which that sort does not touch, so a control
        // offered there would silently do nothing.
        #expect(ChannelSubTab.videos.isVideoGrid)
        #expect(ChannelSubTab.streams.isVideoGrid)
        #expect(ChannelSubTab.shorts.isVideoGrid)
        #expect(!ChannelSubTab.playlists.isVideoGrid)
    }

    @Test("every field true includes all four tabs in a stable order")
    func allTrueIncludesEveryTab() {
        let nav = ChannelNav(hasVideos: true, hasStreams: true, hasShorts: true, hasPlaylists: true)
        #expect(ChannelDetailStore.resolveTabs(from: nav) == [.videos, .streams, .shorts, .playlists])
    }

    @Test("hasVideos explicitly false still keeps the Videos tab")
    func videosTabAlwaysPresentEvenIfFlagIsFalse() {
        let nav = ChannelNav(hasVideos: false, hasStreams: nil, hasShorts: nil, hasPlaylists: nil)
        #expect(ChannelDetailStore.resolveTabs(from: nav) == [.videos])
    }
}

extension MockedNetworkTests {

@MainActor
@Suite("ChannelDetailStore", .serialized)
struct ChannelDetailStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func jsonResponse(_ object: some Encodable) -> MockURLProtocol.StubResponse {
        .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(object))
    }

    private nonisolated func makeVideo(id: String, watched: Bool = false) -> Video {
        Video(youtubeId: id, title: "Video \(id)", player: VideoPlayerState(duration: 120, durationStr: "02:00", watched: watched, position: nil, progress: nil))
    }

    @Test("loadHeader populates channel/aggs/nav and derives availableTabs")
    func loadHeaderPopulatesEverything() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channeldetail.\(UUID().uuidString)")!)
        let store = ChannelDetailStore(client: client, appSettings: settings, channelId: "chan1")

        MockURLProtocol.handler = { request in
            // `URL.path` drops a trailing slash; check `.absoluteString` instead so "/aggs/" and "/nav/" aren't mistaken for the plain channel-detail path.
            let path = request.url?.absoluteString ?? ""
            if path.contains("/aggs/") {
                return self.jsonResponse(ChannelAggs(totalItems: 5, totalSize: 1000, totalDuration: 600))
            } else if path.contains("/nav/") {
                return self.jsonResponse(ChannelNav(hasVideos: true, hasStreams: true, hasShorts: nil, hasPlaylists: nil))
            } else if path.contains("/chan1/") {
                return self.jsonResponse(Channel(channelId: "chan1", channelName: "Chan One"))
            }
            return .init(statusCode: 404)
        }

        await store.loadHeader()
        #expect(store.channel?.channelName == "Chan One")
        #expect(store.aggsState.value?.totalItems == 5)
        #expect(store.navState.value?.hasStreams == true)
        #expect(store.availableTabs == [.videos, .streams])
    }

    @Test("markAllWatched POSTs the channel id and applies watched locally to already-loaded grid items")
    func markAllWatchedAppliesLocally() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channeldetail.\(UUID().uuidString)")!)
        let store = ChannelDetailStore(client: client, appSettings: settings, channelId: "chan1")

        let videos = [makeVideo(id: "v1"), makeVideo(id: "v2")]
        MockURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                return .init(statusCode: 204)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }

        await store.videosGrid.loadFirstPageIfNeeded()
        #expect(store.videosGrid.items.map(\.id) == ["v1", "v2"])
        #expect(store.videosGrid.items.allSatisfy { $0.player?.watched == false })

        let succeeded = await store.markAllWatched()
        #expect(succeeded)
        #expect(store.videosGrid.items.allSatisfy { $0.player?.watched == true })
        #expect(store.markAllWatchedError == nil)
    }
}

}
