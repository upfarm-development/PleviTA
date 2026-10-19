
import Foundation
import Testing
@testable import PleviCore

extension MockedNetworkTests {

@MainActor
@Suite("VideoDetailStore", .serialized)
struct VideoDetailStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func videoJSON(id: String, watched: Bool = false, position: Double? = nil) -> Data {
        let video = Video(
            youtubeId: id,
            title: "Video \(id)",
            player: VideoPlayerState(duration: 120, durationStr: "02:00", watched: watched, position: position, progress: nil)
        )
        return try! JSONEncoder().encode(video)
    }

    @Test("loadVideo populates videoState on success and .failed on error")
    func loadVideoSuccessAndFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1"))
        }
        await store.loadVideo()
        #expect(store.video?.id == "v1")

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }
        await store.loadVideo()
        #expect(store.videoState.error == .notFound)
    }

    @Test("a seeded store opens already loaded, with no loading state to flash through")
    func seededStoreOpensLoaded() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let seed = Video(youtubeId: "v1", title: "From the list")
        let store = VideoDetailStore(client: client, videoId: "v1", seed: seed)
        // The whole point: content before any request is made.
        #expect(store.video?.title == "From the list")
    }

    @Test("a seeded page survives a failed first fetch instead of becoming an error screen")
    func seededStoreKeepsContentOnFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1", seed: Video(youtubeId: "v1", title: "From the list"))

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }
        await store.loadVideo()

        #expect(store.video?.title == "From the list")
        #expect(store.videoState.error == nil, "a flaky refresh must not discard a page that reads fine")
    }

    @Test("an unseeded store still shows the error, because there is nothing to keep")
    func unseededStoreStillFails() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }
        await store.loadVideo()
        #expect(store.videoState.error == .notFound)
    }

    @Test("loadNav populates navState with every VideoNavEntry on success")
    func loadNavSuccess() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        let json = """
        [
          {
            "playlist_meta": {"current_idx": 2, "playlist_id": "p1", "playlist_name": "Playlist One", "playlist_channel": "Channel One"},
            "playlist_previous": {"youtube_id": "prev1", "title": "Previous One", "uploader": "Channel One", "idx": 1, "downloaded": true, "vid_thumb": "/cache/videos/p/prev1.jpg"},
            "playlist_next": {"youtube_id": "next1", "title": "Next One", "uploader": "Channel One", "idx": 3, "downloaded": true, "vid_thumb": "/cache/videos/n/next1.jpg"}
          },
          {
            "playlist_meta": {"current_idx": 0, "playlist_id": "p2", "playlist_name": "Playlist Two", "playlist_channel": "Channel Two"},
            "playlist_previous": null,
            "playlist_next": {"youtube_id": "next2", "title": "Next Two", "uploader": "Channel Two", "idx": 1, "downloaded": true, "vid_thumb": "/cache/videos/n/next2.jpg"}
          }
        ]
        """.data(using: .utf8)!
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: json)
        }
        await store.loadNav(skipWatched: false)
        #expect(store.navState.value?.count == 2)
        #expect(store.navState.value?[0].playlistMeta?.playlistName == "Playlist One")
        #expect(store.navState.value?[0].playlistPrevious?.youtubeId == "prev1")
        #expect(store.navState.value?[0].playlistPrevious?.title == "Previous One")
        #expect(store.navState.value?[0].playlistNext?.youtubeId == "next1")
        // A video belonging to more than one playlist: the second entry's
        // previous neighbour is genuinely null (it's the first entry of that
        // playlist) — decoded as nil, not dropped or coerced.
        #expect(store.navState.value?[1].playlistPrevious == nil)
        #expect(store.navState.value?[1].playlistNext?.youtubeId == "next2")
    }

    @Test("loadNav surfaces a failure via navState.failed, distinct from an empty result")
    func loadNavFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }
        await store.loadNav(skipWatched: false)
        #expect(store.navState.error == .notFound)
    }

    @Test("loadNav's empty array (video in no playlist) loads as .loaded([]), not .failed")
    func loadNavEmpty() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode([VideoNavEntry]()))
        }
        await store.loadNav(skipWatched: false)
        #expect(store.navState.value?.isEmpty == true)
    }

    // MARK: - Skip-watched playlist navigation

    /// A playlist of downloaded entries in `idx` order, the shape
    /// `adjustedEntry` expects `unwatchedNeighbours` to hand it.
    private nonisolated func downloadedEntries(_ ids: [String]) -> [PlaylistEntry] {
        ids.enumerated().map { index, id in
            PlaylistEntry(youtubeId: id, title: "Title \(id)", uploader: "Channel \(id)", idx: index, downloaded: true)
        }
    }

    /// Builds a `Playlist` with sequential `idx` entries — used by the
    /// multi-playlist ordering test, which needs two distinct playlists
    /// rather than the single-playlist shape `downloadedEntries` builds.
    private nonisolated func multiPlaylistFixture(_ id: String, _ ids: [String]) -> Playlist {
        Playlist(playlistId: id, playlistName: id, playlistEntries: ids.enumerated().map { index, youtubeId in
            PlaylistEntry(youtubeId: youtubeId, title: "Title \(youtubeId)", uploader: "Channel", idx: index, downloaded: true)
        })
    }

    /// What the server itself would return for a video sitting at `index`: the immediately adjacent entries, watched or not.
    private nonisolated func serverEntry(in ids: [String], at index: Int) -> VideoNavEntry {
        let entries = downloadedEntries(ids)
        return VideoNavEntry(
            playlistMeta: PlaylistNavMeta(currentIdx: index, playlistId: "p1", playlistName: "Playlist One", playlistChannel: "Channel One"),
            playlistPrevious: index > 0 ? PlaylistNavVideo(youtubeId: entries[index - 1].youtubeId, title: entries[index - 1].title) : nil,
            playlistNext: index < entries.count - 1 ? PlaylistNavVideo(youtubeId: entries[index + 1].youtubeId, title: entries[index + 1].title) : nil
        )
    }

    @Test("next skips past every watched entry to the nearest unwatched one")
    func adjustedEntrySkipsWatchedForward() {
        let ids = ["a", "b", "c", "d", "e"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 2),
            downloaded: downloadedEntries(ids),
            // "b" and "d" are watched, so the server's own neighbours are
            // exactly the two entries that must be stepped over.
            unwatchedIds: ["a", "c", "e"],
            currentVideoId: "c"
        )
        #expect(adjusted.playlistNext?.youtubeId == "e")
        #expect(adjusted.playlistPrevious?.youtubeId == "a")
        // Rebuilt from the playlist entry, not carried over from the server's
        // neighbour object.
        #expect(adjusted.playlistNext?.title == "Title e")
        #expect(adjusted.playlistNext?.uploader == "Channel e")
        #expect(adjusted.playlistNext?.idx == 4)
        // Untouched fields stay untouched.
        #expect(adjusted.playlistMeta?.playlistName == "Playlist One")
    }

    @Test("previous walks backwards past watched entries")
    func adjustedEntrySkipsWatchedBackward() {
        let ids = ["a", "b", "c", "d"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 3),
            downloaded: downloadedEntries(ids),
            // Only the very first entry is unwatched, two steps back.
            unwatchedIds: ["a", "d"],
            currentVideoId: "d"
        )
        #expect(adjusted.playlistPrevious?.youtubeId == "a")
        // Last in the playlist: nothing ahead to jump to.
        #expect(adjusted.playlistNext == nil)
    }

    @Test("a direction with nothing unwatched becomes nil rather than the server's neighbour")
    func adjustedEntryDropsDirectionWithNoUnwatchedCandidate() {
        let ids = ["a", "b", "c"]
        let server = serverEntry(in: ids, at: 1)
        #expect(server.playlistPrevious?.youtubeId == "a")
        #expect(server.playlistNext?.youtubeId == "c")

        let adjusted = VideoDetailStore.adjustedEntry(
            server,
            downloaded: downloadedEntries(ids),
            unwatchedIds: [],
            currentVideoId: "b"
        )
        #expect(adjusted.playlistPrevious == nil)
        #expect(adjusted.playlistNext == nil)
    }

    @Test("the last entry gets no next, and the current video is never offered as its own neighbour")
    func adjustedEntryAtEndOfPlaylist() {
        let ids = ["a", "b", "c"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 2),
            downloaded: downloadedEntries(ids),
            // The video being watched right now is itself still unwatched
            // server-side until it finishes.
            unwatchedIds: ["a", "c"],
            currentVideoId: "c"
        )
        #expect(adjusted.playlistNext == nil)
        #expect(adjusted.playlistPrevious?.youtubeId == "a")
    }

    @Test("a current video missing from the playlist's entries leaves the server entry untouched")
    func adjustedEntryFallsBackWhenCurrentVideoIsMissing() {
        let ids = ["a", "b", "c"]
        let server = serverEntry(in: ids, at: 1)
        let adjusted = VideoDetailStore.adjustedEntry(
            server,
            downloaded: downloadedEntries(ids),
            unwatchedIds: ["a", "c"],
            currentVideoId: "not-in-this-playlist"
        )
        #expect(adjusted == server)
    }

    @Test("an entry with no idx can't be placed in order, so the server entry is left untouched")
    func adjustedEntryFallsBackWhenIdxIsMissing() {
        var entries = downloadedEntries(["a", "c", "d"])
        entries.insert(PlaylistEntry(youtubeId: "b", title: "Title b", uploader: "Channel b", idx: nil, downloaded: true), at: 1)
        let server = serverEntry(in: ["a", "b", "c", "d"], at: 1)

        let adjusted = VideoDetailStore.adjustedEntry(
            server,
            downloaded: entries,
            unwatchedIds: ["a", "b", "c", "d"],
            currentVideoId: "b"
        )
        #expect(adjusted == server)
    }

    @Test("next skips past two consecutive watched entries, not just one")
    func adjustedEntrySkipsMultipleConsecutiveWatchedForward() {
        // Both "d" and "e" — the two entries immediately after "c" — are watched; only "f" beyond them is not.
        let ids = ["a", "b", "c", "d", "e", "f"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 2),
            downloaded: downloadedEntries(ids),
            unwatchedIds: ["a", "c", "f"],
            currentVideoId: "c"
        )
        #expect(adjusted.playlistNext?.youtubeId == "f")
    }

    @Test("previous can resolve while next has no unwatched candidate, independently")
    func adjustedEntryPreviousResolvesWhileNextHasNoUnwatchedCandidate() {
        // Distinct from "the last entry gets no next" above: here "b" is NOT last (there's a "c" and "d" after it), they're just both watched.
        let ids = ["a", "b", "c", "d"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 1),
            downloaded: downloadedEntries(ids),
            unwatchedIds: ["a", "b"],
            currentVideoId: "b"
        )
        #expect(adjusted.playlistPrevious?.youtubeId == "a")
        #expect(adjusted.playlistNext == nil)
    }

    @Test("the current video first in the playlist gets no previous")
    func adjustedEntryCurrentVideoIsFirstInPlaylist() {
        let ids = ["a", "b", "c"]
        let adjusted = VideoDetailStore.adjustedEntry(
            serverEntry(in: ids, at: 0),
            downloaded: downloadedEntries(ids),
            unwatchedIds: ["a", "c"],
            currentVideoId: "a"
        )
        #expect(adjusted.playlistPrevious == nil)
        #expect(adjusted.playlistNext?.youtubeId == "c")
    }

    @Test("loadNav with skipWatched off makes exactly one request and returns the server response verbatim")
    func loadNavWithoutSkippingMakesNoExtraRequests() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "b")

        let requestCount = CountBox(0)
        MockURLProtocol.handler = { _ in
            requestCount.value += 1
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Self.navJSON())
        }

        await store.loadNav(skipWatched: false)
        #expect(requestCount.value == 1)
        #expect(store.navState.value?.first?.playlistPrevious?.youtubeId == "a")
        #expect(store.navState.value?.first?.playlistNext?.youtubeId == "c")
    }

    @Test("loadNav with skipWatched on replaces the server's adjacent neighbours with the nearest unwatched ones")
    func loadNavSkippingWatchedRecomputesNeighbours() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        let playlist = Playlist(
            playlistId: "p1",
            playlistName: "Playlist One",
            playlistEntries: ["a", "b", "c", "d", "e"].enumerated().map { index, id in
                PlaylistEntry(youtubeId: id, title: "Title \(id)", uploader: "Channel One", idx: index, downloaded: true)
            }
        )
        // "b" and "d" — the server's own neighbours — are absent, i.e. watched.
        let unwatched = Paginated(data: [Video(youtubeId: "a"), Video(youtubeId: "c"), Video(youtubeId: "e")])

        let videoListURLs = URLBox()
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = Self.navJSON(currentIdx: 2, previousId: "b", nextId: "d")
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(playlist)
            } else {
                videoListURLs.values.append(url)
                body = try! JSONEncoder().encode(unwatched)
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadNav(skipWatched: true)
        #expect(store.navState.value?.count == 1)
        #expect(store.navState.value?.first?.playlistNext?.youtubeId == "e")
        #expect(store.navState.value?.first?.playlistPrevious?.youtubeId == "a")
        // Scoped to this playlist's unwatched videos, not a blanket list.
        #expect(videoListURLs.values.count == 1)
        #expect(videoListURLs.values.first?.contains("watch=unwatched") == true)
        #expect(videoListURLs.values.first?.contains("playlist=p1") == true)
    }

    @Test("a playlist lookup that fails leaves that entry as the server sent it")
    func loadNavSkippingWatchedFallsBackOnFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "b")

        MockURLProtocol.handler = { request in
            guard request.url?.absoluteString.contains("/nav/") == true else {
                return .init(statusCode: 500)
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Self.navJSON())
        }

        await store.loadNav(skipWatched: true)
        // Still a working section, not an error state and not an empty one.
        #expect(store.navState.error == nil)
        #expect(store.navState.value?.first?.playlistPrevious?.youtubeId == "a")
        #expect(store.navState.value?.first?.playlistNext?.youtubeId == "c")
    }

    @Test("the unwatched-list walk continues past page 1 even when current_page is absent")
    func loadNavSkippingWatchedPaginatesPastFirstPage() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        let playlist = Playlist(
            playlistId: "p1",
            playlistName: "Playlist One",
            playlistEntries: ["a", "b", "c", "d", "e"].enumerated().map { index, id in
                PlaylistEntry(youtubeId: id, title: "Title \(id)", uploader: "Channel One", idx: index, downloaded: true)
            }
        )

        let requestedPages = CountBox(0)
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/nav/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Self.navJSON(currentIdx: 2, previousId: "b", nextId: "d"))
            }
            if url.contains("/playlist/p1/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(playlist))
            }
            requestedPages.value += 1
            let onPageTwo = url.contains("page=2")
            let data = onPageTwo ? [Video(youtubeId: "e")] : [Video(youtubeId: "a")]
            let paginate = onPageTwo
                ? Paginate(currentPage: 2, lastPage: 2, nextPages: [])
                : Paginate(lastPage: 2, nextPages: [2])
            let body = try! JSONEncoder().encode(Paginated(data: data, paginate: paginate))
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadNav(skipWatched: true)
        #expect(store.navState.value?.first?.playlistNext?.youtubeId == "e")
        #expect(requestedPages.value == 2)
    }

    @Test("skipping watched preserves entry order across multiple playlists")
    func loadNavSkippingWatchedPreservesEntryOrderAcrossPlaylists() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        let navJSON = """
        [
          {
            "playlist_meta": {"current_idx": 2, "playlist_id": "p1", "playlist_name": "Playlist One", "playlist_channel": "Channel One"},
            "playlist_previous": {"youtube_id": "b", "title": "Title b", "uploader": "Channel One", "idx": 1, "downloaded": true},
            "playlist_next": {"youtube_id": "d", "title": "Title d", "uploader": "Channel One", "idx": 3, "downloaded": true}
          },
          {
            "playlist_meta": {"current_idx": 1, "playlist_id": "p2", "playlist_name": "Playlist Two", "playlist_channel": "Channel Two"},
            "playlist_previous": {"youtube_id": "x", "title": "Title x", "uploader": "Channel Two", "idx": 0, "downloaded": true},
            "playlist_next": {"youtube_id": "z", "title": "Title z", "uploader": "Channel Two", "idx": 2, "downloaded": true}
          }
        ]
        """.data(using: .utf8)!

        let requestCount = CountBox(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = navJSON
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(self.multiPlaylistFixture("p1", ["a", "b", "c", "d", "e"]))
            } else if url.contains("/playlist/p2/") {
                body = try! JSONEncoder().encode(self.multiPlaylistFixture("p2", ["x", "c", "z"]))
            } else if url.contains("playlist=p1") {
                body = try! JSONEncoder().encode(Paginated(data: [Video(youtubeId: "a"), Video(youtubeId: "c"), Video(youtubeId: "e")]))
            } else {
                body = try! JSONEncoder().encode(Paginated(data: [Video(youtubeId: "x"), Video(youtubeId: "c"), Video(youtubeId: "z")]))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadNav(skipWatched: true)
        // Both playlists resolve, in the same order `/nav/` returned them.
        #expect(store.navState.value?.count == 2)
        #expect(store.navState.value?[0].playlistMeta?.playlistId == "p1")
        #expect(store.navState.value?[0].playlistNext?.youtubeId == "e")
        #expect(store.navState.value?[1].playlistMeta?.playlistId == "p2")
        #expect(store.navState.value?[1].playlistNext?.youtubeId == "z")
        // /nav/ + 2×(/playlist/ + video list) = 5.
        #expect(requestCount.value == 5)
    }

    @Test("skipping watched sorts by idx and drops non-downloaded entries regardless of server order")
    func loadNavSkippingWatchedSortsAndFiltersServerPlaylistEntries() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        // Deliberately out of idx order, and "not-downloaded" mixed in where
        // the real next entry would otherwise sit.
        let playlist = Playlist(
            playlistId: "p1",
            playlistName: "Playlist One",
            playlistEntries: [
                PlaylistEntry(youtubeId: "d", title: "Title d", uploader: "Channel", idx: 3, downloaded: true),
                PlaylistEntry(youtubeId: "a", title: "Title a", uploader: "Channel", idx: 0, downloaded: true),
                PlaylistEntry(youtubeId: "never", title: "Never Downloaded", uploader: "Channel", idx: 2, downloaded: false),
                PlaylistEntry(youtubeId: "c", title: "Title c", uploader: "Channel", idx: 1, downloaded: true)
            ]
        )
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = Self.navJSON(currentIdx: 1, previousId: "a", nextId: "never")
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(playlist)
            } else {
                body = try! JSONEncoder().encode(Paginated(data: [Video(youtubeId: "a"), Video(youtubeId: "c"), Video(youtubeId: "d")]))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadNav(skipWatched: true)
        #expect(store.navState.value?.first?.playlistNext?.youtubeId == "d")
    }

    private nonisolated static func navJSON(currentIdx: Int = 1, previousId: String = "a", nextId: String = "c") -> Data {
        """
        [
          {
            "playlist_meta": {"current_idx": \(currentIdx), "playlist_id": "p1", "playlist_name": "Playlist One", "playlist_channel": "Channel One"},
            "playlist_previous": {"youtube_id": "\(previousId)", "title": "Title \(previousId)", "uploader": "Channel One", "idx": \(currentIdx - 1), "downloaded": true},
            "playlist_next": {"youtube_id": "\(nextId)", "title": "Title \(nextId)", "uploader": "Channel One", "idx": \(currentIdx + 1), "downloaded": true}
          }
        ]
        """.data(using: .utf8)!
    }

    // MARK: - Multi-playlist pager

    /// The last non-empty path component of a mocked request URL.
    private nonisolated func videoId(from url: String) -> String {
        url.split(separator: "/").last.map(String.init) ?? ""
    }

    @Test("pagerWindow takes 1 before and 3 after around the middle of a long playlist")
    func pagerWindowMiddleOfLongPlaylist() {
        #expect(VideoDetailStore.pagerWindow(around: 10, count: 41) == 9..<14)
    }

    @Test("pagerWindow shifts the whole budget after when the current video is first, rather than clamping short")
    func pagerWindowClampsAtStart() {
        #expect(VideoDetailStore.pagerWindow(around: 0, count: 41) == 0..<5)
    }

    @Test("pagerWindow shifts the whole budget before when the current video is last, rather than clamping short")
    func pagerWindowClampsAtEnd() {
        #expect(VideoDetailStore.pagerWindow(around: 40, count: 41) == 36..<41)
    }

    @Test("pagerWindow redistributes a partial shortfall too, not just a total one")
    func pagerWindowRedistributesPartialShortfall() {
        #expect(VideoDetailStore.pagerWindow(around: 0, count: 10, before: 2, after: 2) == 0..<5)
    }

    @Test("pagerWindow returns an empty range for an out-of-bounds index or an empty playlist")
    func pagerWindowHandlesOutOfBoundsAndEmpty() {
        #expect(VideoDetailStore.pagerWindow(around: 5, count: 0) == 0..<0)
        #expect(VideoDetailStore.pagerWindow(around: -1, count: 10) == 0..<0)
        #expect(VideoDetailStore.pagerWindow(around: 10, count: 10) == 0..<0)
    }

    @Test("pagerWindow spans the whole playlist when it's smaller than the window")
    func pagerWindowSpansWholeShortPlaylist() {
        #expect(VideoDetailStore.pagerWindow(around: 1, count: 3) == 0..<3)
    }

    @Test("loadPager assembles a bounded 1-before/3-after window of full Video objects, positioned by rank in the downloaded list")
    func loadPagerAssemblesBoundedWindow() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "d")

        // 7 downloaded entries; the video being viewed ("d") sits at index
        // 3 (0-based), so the window should be indices 2...6 ("c".."g") —
        // 1 before, current, 3 after.
        let playlist = multiPlaylistFixture("p1", ["a", "b", "c", "d", "e", "f", "g"])
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = Self.navJSON(currentIdx: 3, previousId: "c", nextId: "e")
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(playlist)
            } else {
                let id = self.videoId(from: url)
                body = try! JSONEncoder().encode(Video(youtubeId: id, title: "Title \(id)"))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadPager(hideWatched: false)
        #expect(store.pagerState.value?.count == 1)
        let page = try #require(store.pagerState.value?.first)
        #expect(page.playlistId == "p1")
        #expect(page.currentPosition == 4)
        #expect(page.totalCount == 7)
        #expect(page.entries.map(\.video.id) == ["c", "d", "e", "f", "g"])
        #expect(page.entries.map(\.position) == [3, 4, 5, 6, 7])
        #expect(page.entries.first(where: { $0.isCurrent })?.video.id == "d")
    }

    @Test("loadPager with hideWatched drops watched neighbours from the window, pulling further entries in to compensate")
    func loadPagerHideWatchedSkipsWatchedNeighbours() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "d")

        // Same 7-entry playlist/current-video shape as the unfiltered test above, but "c" and "f" — the server's own 1-before/1-after neighbours.
        let playlist = multiPlaylistFixture("p1", ["a", "b", "c", "d", "e", "f", "g"])
        let unwatched = Paginated(data: ["a", "b", "d", "e", "g"].map { Video(youtubeId: $0) })

        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = Self.navJSON(currentIdx: 3, previousId: "c", nextId: "e")
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(playlist)
            } else if url.contains("watch=unwatched") {
                body = try! JSONEncoder().encode(unwatched)
            } else {
                let id = self.videoId(from: url)
                body = try! JSONEncoder().encode(Video(youtubeId: id, title: "Title \(id)"))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadPager(hideWatched: true)
        #expect(store.pagerState.value?.count == 1)
        let page = try #require(store.pagerState.value?.first)
        #expect(page.entries.map(\.video.id) == ["a", "b", "d", "e", "g"])
        #expect(page.entries.map(\.position) == [1, 2, 4, 5, 7])
        #expect(page.currentPosition == 4)
        #expect(page.totalCount == 7)
        #expect(page.entries.first(where: { $0.isCurrent })?.video.id == "d")
    }

    @Test("loadPager with hideWatched still shows the current video even if it's watched")
    func loadPagerHideWatchedKeepsWatchedCurrentVideo() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "d")

        let playlist = multiPlaylistFixture("p1", ["a", "b", "c", "d", "e"])
        let unwatched = Paginated(data: ["a", "b", "c", "e"].map { Video(youtubeId: $0) })

        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let body: Data
            if url.contains("/nav/") {
                body = Self.navJSON(currentIdx: 3, previousId: "c", nextId: "e")
            } else if url.contains("/playlist/p1/") {
                body = try! JSONEncoder().encode(playlist)
            } else if url.contains("watch=unwatched") {
                body = try! JSONEncoder().encode(unwatched)
            } else {
                let id = self.videoId(from: url)
                body = try! JSONEncoder().encode(Video(youtubeId: id, title: "Title \(id)"))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadPager(hideWatched: true)
        let page = try #require(store.pagerState.value?.first)
        #expect(page.entries.map(\.video.id) == ["a", "b", "c", "d", "e"])
        #expect(page.entries.first(where: { $0.isCurrent })?.video.id == "d")
    }

    @Test("loadPager drops a page whose playlist lookup fails, keeping the others")
    func loadPagerDropsPageOnPlaylistFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        let navJSON = """
        [
          {"playlist_meta": {"current_idx": 1, "playlist_id": "p1", "playlist_name": "Broken", "playlist_channel": "Channel"}, "playlist_previous": null, "playlist_next": null},
          {"playlist_meta": {"current_idx": 1, "playlist_id": "p2", "playlist_name": "Playlist Two", "playlist_channel": "Channel"}, "playlist_previous": null, "playlist_next": null}
        ]
        """.data(using: .utf8)!
        let playlistTwo = multiPlaylistFixture("p2", ["x", "c", "z"])

        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/nav/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: navJSON)
            }
            if url.contains("/playlist/p1/") {
                return .init(statusCode: 500)
            }
            if url.contains("/playlist/p2/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(playlistTwo))
            }
            let id = self.videoId(from: url)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(Video(youtubeId: id)))
        }

        await store.loadPager(hideWatched: false)
        #expect(store.pagerState.value?.count == 1)
        #expect(store.pagerState.value?.first?.playlistId == "p2")
    }

    @Test("loadPager drops a page when the current video isn't among the playlist's downloaded entries")
    func loadPagerDropsPageWhenCurrentVideoMissing() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "not-in-playlist")

        let playlist = multiPlaylistFixture("p1", ["a", "b", "c"])
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/nav/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Self.navJSON())
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(playlist))
        }

        await store.loadPager(hideWatched: false)
        // Still a working (if empty) section, not an error state — same
        // "degrade, don't fail the whole thing" rule `loadNav` follows.
        #expect(store.pagerState.value?.isEmpty == true)
        #expect(store.pagerState.error == nil)
    }

    @Test("loadPager preserves nav's own order across multiple playlists")
    func loadPagerPreservesOrderAcrossPlaylists() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "c")

        let navJSON = """
        [
          {"playlist_meta": {"current_idx": 2, "playlist_id": "p1", "playlist_name": "Playlist One", "playlist_channel": "Channel One"}, "playlist_previous": null, "playlist_next": null},
          {"playlist_meta": {"current_idx": 1, "playlist_id": "p2", "playlist_name": "Playlist Two", "playlist_channel": "Channel Two"}, "playlist_previous": null, "playlist_next": null}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/nav/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: navJSON)
            }
            if url.contains("/playlist/p1/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(self.multiPlaylistFixture("p1", ["a", "b", "c", "d", "e"])))
            }
            if url.contains("/playlist/p2/") {
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(self.multiPlaylistFixture("p2", ["x", "c", "z"])))
            }
            let id = self.videoId(from: url)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(Video(youtubeId: id)))
        }

        await store.loadPager(hideWatched: false)
        // Both playlists resolve, in the same order `/nav/` returned them.
        #expect(store.pagerState.value?.count == 2)
        #expect(store.pagerState.value?[0].playlistId == "p1")
        #expect(store.pagerState.value?[1].playlistId == "p2")
    }

    @Test("comments load only once and are threaded from a flat list")
    func commentsLoadOnceAndThread() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        let flatComments: [PleviCore.Comment] = [
            PleviCore.Comment(commentId: "c1", commentText: "root one", commentParent: "root"),
            PleviCore.Comment(commentId: "c2", commentText: "reply to one", commentParent: "c1")
        ]
        let requestCount = CountBox(0)
        MockURLProtocol.handler = { _ in
            requestCount.value += 1
            let body = try! JSONEncoder().encode(flatComments)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadCommentsIfNeeded()
        #expect(requestCount.value == 1)
        #expect(store.commentsState.value?.count == 1) // one root, reply nested underneath
        #expect(store.commentsState.value?.first?.commentReplies?.first?.commentId == "c2")

        // Second call: no new network request (already loaded).
        await store.loadCommentsIfNeeded()
        #expect(requestCount.value == 1)
    }

    @Test("comments empty state is distinguishable from not-yet-loaded")
    func emptyCommentsState() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode([PleviCore.Comment]()))
        }
        await store.loadCommentsIfNeeded()
        #expect(store.commentsState.value?.isEmpty == true)
    }

    @Test("similar videos load independently of comments and only once")
    func similarLoadsOnce() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        let requestCount = CountBox(0)
        MockURLProtocol.handler = { _ in
            requestCount.value += 1
            let similar = [Video(youtubeId: "s1", title: "Similar")]
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(similar))
        }

        await store.loadSimilarIfNeeded()
        #expect(store.similarState.value?.map(\.id) == ["s1"])
        #expect(requestCount.value == 1)

        await store.loadSimilarIfNeeded()
        #expect(requestCount.value == 1)
    }

    @Test("setWatched updates local video state and clears position when marking watched")
    func setWatchedUpdatesLocally() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/watched/") == true {
                return .init(statusCode: 204)
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1", watched: false, position: 42))
        }

        await store.loadVideo()
        #expect(store.video?.player?.position == 42)

        let succeeded = await store.setWatched(true)
        #expect(succeeded)
        #expect(store.video?.player?.watched == true)
        #expect(store.video?.player?.position == nil)
    }

    @Test("removeVideoLocally drops the id from similarState and leaves videoState untouched")
    func removeVideoLocallyDropsFromSimilarOnly() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/similar/") {
                let similar = [Video(youtubeId: "s1", title: "Similar"), Video(youtubeId: "s2", title: "Similar 2")]
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! JSONEncoder().encode(similar))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1", watched: false, position: 42))
        }
        await store.loadVideo()
        await store.loadSimilarIfNeeded()
        #expect(store.similarState.value?.map(\.id) == ["s1", "s2"])

        store.removeVideoLocally(id: "s1")

        #expect(store.similarState.value?.map(\.id) == ["s2"])
        // This screen's own video is untouched — only Similar Videos rows are ever
        // something other than the video the screen is about.
        #expect(store.video?.id == "v1")
        #expect(store.video?.player?.position == 42)

        // Removing this screen's own id from Similar Videos too (a video can appear as its
        // own "similar" result in principle) must not touch `videoState` either.
        store.removeVideoLocally(id: "v1")
        #expect(store.video?.id == "v1")
    }

    @Test("applyLocalPlaybackResult updates position immediately, with no network request of its own")
    func applyLocalPlaybackResultUpdatesPositionLocally() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1", watched: false, position: 5))
        }
        await store.loadVideo()
        #expect(store.video?.player?.position == 5)

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }
        store.applyLocalPlaybackResult(position: 60, watched: false)

        #expect(store.video?.player?.position == 60)
        #expect(store.video?.player?.watched == false)
        // `videoJSON` gives this video a 120s duration — 60/120 = 50%.
        #expect(store.video?.player?.progress == 50)
    }

    @Test("applyLocalPlaybackResult never lowers the watched flag, and never clears a position on a no-op close")
    func applyLocalPlaybackResultDoesNotClobberWatchedState() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1", watched: true, position: 30))
        }
        await store.loadVideo()
        #expect(store.video?.player?.watched == true)

        // Any further request would fail, so nothing below can be papered over by a re-fetch
        // — which is the point: `refreshVideo()` swallows its own errors.
        MockURLProtocol.handler = { _ in .init(statusCode: 500) }

        // Replaying a watched video and closing part-way reports `watched: false`. That is
        // not evidence the video is unwatched, and nothing POSTs `is_watched=false` behind
        // it, so the flag must stay up while the position still updates.
        store.applyLocalPlaybackResult(position: 45, watched: false)
        #expect(store.video?.player?.watched == true)
        #expect(store.video?.player?.position == 45)

        // Opening a file this platform cannot decode never builds an engine, so the caller
        // reports position 0. Clearing a real saved position on the strength of that would
        // be the same class of bug.
        store.applyLocalPlaybackResult(position: 0, watched: false)
        #expect(store.video?.player?.position == 45)
        #expect(store.video?.player?.watched == true)
    }

    @Test("applyLocalPlaybackResult clears position/progress once playback reached .ended")
    func applyLocalPlaybackResultClearsPositionWhenWatched() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = VideoDetailStore(client: client, videoId: "v1")

        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.videoJSON(id: "v1", watched: false, position: 5))
        }
        await store.loadVideo()

        store.applyLocalPlaybackResult(position: 119, watched: true)

        #expect(store.video?.player?.watched == true)
        #expect(store.video?.player?.position == nil)
        #expect(store.video?.player?.progress == nil)
    }
}

}

/// Records the URLs a `MockURLProtocol` handler saw, for assertions that
/// belong in the test body rather than inside the handler closure (which
/// runs off the test's own task). Same serialization argument as `CountBox`.
final class URLBox: @unchecked Sendable {
    var values: [String] = []
}

/// A mutable reference cell so `MockURLProtocol`'s `@Sendable` handler closures can count requests.
final class CountBox: @unchecked Sendable {
    var value: Int
    init(_ value: Int) { self.value = value }
}
