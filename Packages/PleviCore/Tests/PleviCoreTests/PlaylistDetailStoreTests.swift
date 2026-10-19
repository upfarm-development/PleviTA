
import Foundation
import Testing
@testable import PleviCore

// MARK: - PlaylistDetailStore.sortedEntries — pure, no networking, no
// @MainActor needed (same style as ChannelDetailStoreResolveTabsTests /
// PlaylistsStoreSortedTests).
@Suite("PlaylistDetailStore.sortedEntries")
struct PlaylistDetailStoreSortedEntriesTests {
    private func display(youtubeId: String, entryTitle: String?, idx: Int?, published: String? = nil) -> PlaylistEntryDisplay {
        let entry = PlaylistEntry(youtubeId: youtubeId, title: entryTitle, uploader: "Uploader", idx: idx, downloaded: true)
        let video = Video(youtubeId: youtubeId, published: published)
        return PlaylistEntryDisplay(entry: entry, video: video)
    }

    @Test("playlistOrder sorts by entry.idx — today's existing default behavior, unchanged")
    func sortsByPlaylistOrder() {
        let entries = [
            display(youtubeId: "c", entryTitle: "C", idx: 2),
            display(youtubeId: "a", entryTitle: "A", idx: 0),
            display(youtubeId: "b", entryTitle: "B", idx: 1)
        ]
        let asc = PlaylistDetailStore.sortedEntries(entries, field: .playlistOrder, order: .asc)
        #expect(asc.map(\.id) == ["a", "b", "c"])

        let desc = PlaylistDetailStore.sortedEntries(entries, field: .playlistOrder, order: .desc)
        #expect(desc.map(\.id) == ["c", "b", "a"])
    }

    @Test("title sorts alphabetically, case-insensitively, independent of playlist order")
    func sortsByTitle() {
        let entries = [
            display(youtubeId: "1", entryTitle: "banana", idx: 0),
            display(youtubeId: "2", entryTitle: "Apple", idx: 1),
            display(youtubeId: "3", entryTitle: "cherry", idx: 2)
        ]
        let asc = PlaylistDetailStore.sortedEntries(entries, field: .title, order: .asc)
        #expect(asc.map(\.id) == ["2", "1", "3"])

        let desc = PlaylistDetailStore.sortedEntries(entries, field: .title, order: .desc)
        #expect(desc.map(\.id) == ["3", "1", "2"])
    }

    @Test("datePublished sorts by video.published, a raw ISO 8601 string compare")
    func sortsByDatePublished() {
        // The confirmed real format: fixed-width, constant "+00:00" UTC offset.
        let entries = [
            display(youtubeId: "mid", entryTitle: nil, idx: 1, published: "2026-06-15T10:00:00+00:00"),
            display(youtubeId: "earliest", entryTitle: nil, idx: 0, published: "2025-01-01T00:00:00+00:00"),
            display(youtubeId: "latest", entryTitle: nil, idx: 2, published: "2026-08-14T15:58:23+00:00")
        ]
        let asc = PlaylistDetailStore.sortedEntries(entries, field: .datePublished, order: .asc)
        #expect(asc.map(\.id) == ["earliest", "mid", "latest"])

        let desc = PlaylistDetailStore.sortedEntries(entries, field: .datePublished, order: .desc)
        #expect(desc.map(\.id) == ["latest", "mid", "earliest"])
    }

    @Test("a missing idx (playlistOrder) sorts as the lowest value — last ascending, first descending")
    func missingIdxSortsAsLowestValue() {
        let entries = [
            display(youtubeId: "known", entryTitle: "Known", idx: 0),
            display(youtubeId: "unknown", entryTitle: "Unknown", idx: nil)
        ]
        let asc = PlaylistDetailStore.sortedEntries(entries, field: .playlistOrder, order: .asc)
        #expect(asc.map(\.id) == ["known", "unknown"])

        let desc = PlaylistDetailStore.sortedEntries(entries, field: .playlistOrder, order: .desc)
        #expect(desc.map(\.id) == ["unknown", "known"])
    }
}

extension MockedNetworkTests {

@MainActor
@Suite("PlaylistDetailStore", .serialized)
struct PlaylistDetailStoreTests {
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

    private nonisolated func makeVideo(id: String, watched: Bool = false, position: Double? = nil) -> Video {
        Video(youtubeId: id, title: "Video \(id)", player: VideoPlayerState(duration: 120, durationStr: "02:00", watched: watched, position: position, progress: nil))
    }

    private nonisolated func makePlaylist(entries: [(String, Int)]) -> Playlist {
        Playlist(
            playlistId: "pl1",
            playlistName: "Test Playlist",
            playlistEntries: entries.map { PlaylistEntry(youtubeId: $0.0, title: "Title \($0.0)", uploader: "Uploader", idx: $0.1, downloaded: true) }
        )
    }

    @Test("loadEntries orders by idx (not server order) and attaches matching videos")
    func loadEntriesOrdersByIdxAndAttachesVideos() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        // Entries deliberately out of idx order to prove client-side re-sorting.
        let playlist = makePlaylist(entries: [("v3", 2), ("v1", 0), ("v2", 1)])
        let videos = [makeVideo(id: "v2"), makeVideo(id: "v1", watched: true), makeVideo(id: "v3")]

        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }

        await store.load()
        #expect(store.playlist?.playlistId == "pl1")
        #expect(store.entries.map(\.id) == ["v1", "v2", "v3"])
        #expect(store.entries.first?.video?.player?.watched == true)
    }

    @Test("loadEntries paginates through every /api/video/ page")
    func loadEntriesFetchesEveryPage() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        let playlist = makePlaylist(entries: [("v1", 0), ("v2", 1)])
        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            let isPage2 = (request.url?.query ?? "").contains("page=2")
            if isPage2 {
                return self.jsonResponse(Paginated(data: [self.makeVideo(id: "v2")], paginate: Paginate(currentPage: 2, lastPage: 2)))
            }
            return self.jsonResponse(Paginated(data: [self.makeVideo(id: "v1")], paginate: Paginate(currentPage: 1, lastPage: 2)))
        }

        await store.load()
        #expect(store.entries.compactMap(\.video).map(\.id) == ["v1", "v2"])
    }

    @Test("downloadedEntries filters out entries with no matching video")
    func downloadedEntriesFiltersOutNeverDownloaded() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        // "v2" is a real YouTube playlist entry Tube Archivist never
        // downloaded — /api/video/?playlist=pl1 has nothing to return for
        // it, exactly like the mock server's own zzNeverDL0*mock entries.
        let playlist = makePlaylist(entries: [("v1", 0), ("v2", 1), ("v3", 2)])
        let videos = [makeVideo(id: "v1"), makeVideo(id: "v3")]
        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }
        await store.load()

        // The raw, unfiltered `entries` still carries all three (idx order
        // preserved) — only the view-facing `downloadedEntries` hides the
        // undownloaded one.
        #expect(store.entries.map(\.id) == ["v1", "v2", "v3"])
        #expect(store.entries.first(where: { $0.id == "v2" })?.isDownloaded == false)
        #expect(store.downloadedEntries.map(\.id) == ["v1", "v3"])
        #expect(store.downloadedEntries.allSatisfy { $0.isDownloaded })
    }

    @Test("hideWatched filters watched entries out of a playlist's own list")
    func hideWatchedFiltersPlaylistEntries() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        let playlist = makePlaylist(entries: [("v1", 0), ("v2", 1), ("v3", 2)])
        let videos = [
            makeVideo(id: "v1", watched: true),
            makeVideo(id: "v2", watched: false),
            makeVideo(id: "v3", watched: true)
        ]
        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }
        await store.load()

        let all = store.downloadedEntries(sortedBy: .playlistOrder, order: .asc, hideWatched: false)
        #expect(all.map(\.id) == ["v1", "v2", "v3"])

        let unwatchedOnly = store.downloadedEntries(sortedBy: .playlistOrder, order: .asc, hideWatched: true)
        #expect(unwatchedOnly.map(\.id) == ["v2"])
    }

    @Test("hideWatched leaves a fully-watched playlist with an empty visible list")
    func hideWatchedCanEmptyThePlaylist() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        let playlist = makePlaylist(entries: [("v1", 0), ("v2", 1)])
        let videos = [makeVideo(id: "v1", watched: true), makeVideo(id: "v2", watched: true)]
        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }
        await store.load()

        let visible = store.downloadedEntries(sortedBy: .playlistOrder, order: .asc, hideWatched: true)
        #expect(visible.isEmpty)
    }

    @Test("removeVideoLocally clears the entry's video rather than removing the entry itself")
    func removeVideoLocallyClearsVideoNotEntry() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = PlaylistDetailStore(client: client, playlistId: "pl1")

        let playlist = makePlaylist(entries: [("v1", 0), ("v2", 1)])
        let videos = [makeVideo(id: "v1"), makeVideo(id: "v2")]
        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/playlist/pl1/") {
                return self.jsonResponse(playlist)
            }
            return self.jsonResponse(Paginated(data: videos, paginate: Paginate(currentPage: 1, lastPage: 1)))
        }
        await store.load()
        #expect(store.entries.count == 2)
        #expect(store.downloadedEntries.count == 2)

        store.removeVideoLocally(id: "v1")

        // The entry stays (the playlist still names this video) — proving the `.video = nil`
        // mechanism rather than an array removal, which is what makes `downloadedEntries`
        // (filtered on `isDownloaded`, i.e. `video != nil`) correctly stop showing it.
        #expect(store.entries.count == 2)
        #expect(store.downloadedEntries.count == 1)
        #expect(store.downloadedEntries.map(\.id) == ["v2"])
    }
}

}
