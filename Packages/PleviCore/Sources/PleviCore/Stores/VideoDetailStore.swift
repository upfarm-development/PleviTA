
import Foundation
import Observation

@Observable
@MainActor
public final class VideoDetailStore: VideoMutating {
    public let videoId: String
    public private(set) var videoState: LoadState<Video> = .idle
    /// Whether the server has ever answered for this video. Distinguishes a seeded page,
    /// which is a plausible guess worth keeping through a failure, from one the server has
    /// confirmed, where a later failure is information. See `loadVideo`.
    private var hasLoadedFromServer = false
    /// Threaded via `CommentTree.build(from:)` (Comment.swift) before being
    /// stored — the view renders `commentsState`'s roots directly.
    public private(set) var commentsState: LoadState<[Comment]> = .idle
    public private(set) var similarState: LoadState<[Video]> = .idle
    public private(set) var navState: LoadState<[VideoNavEntry]> = .idle
    public private(set) var pagerState: LoadState<[PlaylistPagerPage]> = .idle

    private let client: TAClient
    private var didLoadComments = false
    private var didLoadSimilar = false

    /// `seed` opens the screen already drawn, from the copy the list the user tapped was
    /// already showing (`VideoCache`). `loadVideo` still refetches and replaces it — the
    /// seed is a head start, never the answer.
    public init(client: TAClient, videoId: String, seed: Video? = nil) {
        self.client = client
        self.videoId = videoId
        if let seed { videoState = .loaded(seed) }
        VideoRemovalCenter.shared.register(self)
    }

    public var video: Video? { videoState.value }

    public func loadVideo() async {
        // Only announce loading when there is nothing to show. With a seed, this is a
        // refresh behind content that is already on screen, and dropping to `.loading`
        // would reintroduce the blank page the seed exists to remove.
        if videoState.value == nil { videoState = .loading }
        do {
            let video = try await client.video(id: videoId)
            videoState = .loaded(video)
            hasLoadedFromServer = true
        } catch {
            // Protect a *seeded* page only.
            if hasLoadedFromServer || videoState.value == nil {
                videoState = .failed(Self.taError(error))
            }
        }
    }

    /// Re-fetches the video document without touching comments/similar or resetting their "already loaded" flags.
    public func refreshVideo() async {
        guard let video = try? await client.video(id: videoId) else { return }
        videoState = .loaded(video)
    }

    public func loadNav(skipWatched: Bool) async {
        navState = .loading
        do {
            let entries = try await client.nav(videoId: videoId)
            navState = .loaded(skipWatched ? await Self.skippingWatched(entries, client: client, currentVideoId: videoId) : entries)
        } catch {
            navState = .failed(Self.taError(error))
        }
    }

    /// One playlist's lookup per entry, concurrently — a video in several
    /// playlists shouldn't pay for them serially.
    private nonisolated static func skippingWatched(
        _ entries: [VideoNavEntry],
        client: TAClient,
        currentVideoId: String
    ) async -> [VideoNavEntry] {
        await withTaskGroup(of: (Int, VideoNavEntry).self) { group in
            for (offset, entry) in entries.enumerated() {
                group.addTask {
                    (offset, await unwatchedNeighbours(for: entry, client: client, currentVideoId: currentVideoId))
                }
            }
            var adjusted = entries
            for await (offset, entry) in group { adjusted[offset] = entry }
            return adjusted
        }
    }

    /// Recomputes one entry's Previous/Next from the playlist document plus that playlist's unwatched videos.
    private nonisolated static func unwatchedNeighbours(
        for entry: VideoNavEntry,
        client: TAClient,
        currentVideoId: String
    ) async -> VideoNavEntry {
        guard let playlistId = entry.playlistMeta?.playlistId else { return entry }
        do {
            let playlist = try await client.playlist(id: playlistId)
            let downloaded = (playlist.playlistEntries ?? [])
                .filter { $0.downloaded == true }
                .sorted { ($0.idx ?? Int.max) < ($1.idx ?? Int.max) }
            let unwatchedIds = try await unwatchedVideoIds(inPlaylist: playlistId, client: client)
            return adjustedEntry(entry, downloaded: downloaded, unwatchedIds: unwatchedIds, currentVideoId: currentVideoId)
        } catch {
            return entry
        }
    }

    /// Paginated defensively exactly the way `PlaylistDetailStore.
    /// loadEntries` walks the same endpoint, page cap included.
    private nonisolated static func unwatchedVideoIds(inPlaylist playlistId: String, client: TAClient) async throws -> Set<String> {
        var ids: Set<String> = []
        var page = 1
        while true {
            let result = try await client.videos(VideoListQuery(page: page, watch: .unwatched, playlist: playlistId))
            for video in result.data { ids.insert(video.id) }
            // Driven by our own counter, not `paginate.currentPage`.
            guard let paginate = result.paginate, paginate.hasNextPage else { break }
            page += 1
            if page > 200 { break }
        }
        return ids
    }

    /// Every video in a playlist, walked page by page.
    private nonisolated static func allVideos(inPlaylist playlistId: String, client: TAClient) async throws -> [Video] {
        var all: [Video] = []
        var page = 1
        while true {
            let result = try await client.videos(VideoListQuery(page: page, playlist: playlistId))
            all.append(contentsOf: result.data)
            guard let paginate = result.paginate, paginate.hasNextPage else { break }
            page += 1
            if page > 200 { break }
        }
        return all
    }

    /// Orders a playlist's downloaded entries the way the Playlists screen's own sort control would.
    nonisolated static func sortedPagerEntries(
        _ entries: [PlaylistEntry],
        field: PlaylistEntrySortField,
        order: HomeSortOrder,
        publishedById: [String: String]
    ) -> [PlaylistEntry] {
        entries.sorted { a, b in
            let result: ComparisonResult
            switch field {
            case .playlistOrder:
                let idxA = a.idx ?? Int.max
                let idxB = b.idx ?? Int.max
                result = idxA == idxB ? .orderedSame : (idxA < idxB ? .orderedAscending : .orderedDescending)
            case .title:
                result = (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "")
            case .datePublished:
                result = (publishedById[a.youtubeId] ?? "").compare(publishedById[b.youtubeId] ?? "")
            }
            if result == .orderedSame {
                // Playlist order as the tiebreak, never the video id.
                return (a.idx ?? Int.max) < (b.idx ?? Int.max)
            }
            return order == .asc ? result == .orderedAscending : result == .orderedDescending
        }
    }

    /// Pure, `nonisolated`, unit-testable without a store instance or any networking (same shape as `PlaylistDetailStore.sortedEntries`).
    nonisolated static func adjustedEntry(
        _ entry: VideoNavEntry,
        downloaded: [PlaylistEntry],
        unwatchedIds: Set<String>,
        currentVideoId: String
    ) -> VideoNavEntry {
        guard downloaded.allSatisfy({ $0.idx != nil }) else { return entry }
        guard let current = downloaded.firstIndex(where: { $0.youtubeId == currentVideoId }) else { return entry }
        var adjusted = entry
        adjusted.playlistPrevious = downloaded[..<current]
            .last { unwatchedIds.contains($0.youtubeId) }
            .map(navVideo)
        adjusted.playlistNext = downloaded[(current + 1)...]
            .first { unwatchedIds.contains($0.youtubeId) }
            .map(navVideo)
        return adjusted
    }

    /// `vid_thumb` has no counterpart in `playlist_entries`, and nothing in
    /// "In This Playlist" renders one.
    private nonisolated static func navVideo(_ entry: PlaylistEntry) -> PlaylistNavVideo {
        PlaylistNavVideo(
            youtubeId: entry.youtubeId,
            title: entry.title,
            uploader: entry.uploader,
            idx: entry.idx,
            downloaded: entry.downloaded
        )
    }

    // MARK: - Multi-playlist pager

    /// Data assembly for the multi-playlist swipeable pager.
    public func loadPager(
        hideWatched: Bool,
        sortField: PlaylistEntrySortField = .playlistOrder,
        sortOrder: HomeSortOrder = .asc
    ) async {
        pagerState = .loading
        do {
            let entries = try await client.nav(videoId: videoId)
            let pages = await Self.pagerPages(
                from: entries,
                client: client,
                currentVideoId: videoId,
                hideWatched: hideWatched,
                sortField: sortField,
                sortOrder: sortOrder
            )
            pagerState = .loaded(pages)
        } catch {
            pagerState = .failed(Self.taError(error))
        }
    }

    /// One playlist lookup + bounded video fetch per `/nav/` entry, concurrently.
    private nonisolated static func pagerPages(
        from entries: [VideoNavEntry],
        client: TAClient,
        currentVideoId: String,
        hideWatched: Bool,
        sortField: PlaylistEntrySortField,
        sortOrder: HomeSortOrder
    ) async -> [PlaylistPagerPage] {
        await withTaskGroup(of: (Int, PlaylistPagerPage?).self) { group in
            for (offset, entry) in entries.enumerated() {
                group.addTask {
                    (offset, await pagerPage(
                        for: entry,
                        client: client,
                        currentVideoId: currentVideoId,
                        hideWatched: hideWatched,
                        sortField: sortField,
                        sortOrder: sortOrder
                    ))
                }
            }
            var pages = [PlaylistPagerPage?](repeating: nil, count: entries.count)
            for await (offset, page) in group { pages[offset] = page }
            return pages.compactMap { $0 }
        }
    }

    /// One playlist's page, or `nil` when there's nothing usable to show.
    private nonisolated static func pagerPage(
        for entry: VideoNavEntry,
        client: TAClient,
        currentVideoId: String,
        hideWatched: Bool,
        sortField: PlaylistEntrySortField,
        sortOrder: HomeSortOrder
    ) async -> PlaylistPagerPage? {
        guard let playlistId = entry.playlistMeta?.playlistId else { return nil }
        do {
            let playlist = try await client.playlist(id: playlistId)
            var downloaded = (playlist.playlistEntries ?? [])
                .filter { $0.downloaded == true }

            // A `PlaylistEntry` carries only youtubeId/title/uploader/idx/ downloaded — no published date.
            let publishedById: [String: String]
            if sortField == .datePublished {
                let videos = (try? await allVideos(inPlaylist: playlistId, client: client)) ?? []
                publishedById = Dictionary(
                    videos.map { ($0.id, $0.published ?? "") },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                publishedById = [:]
            }

            downloaded = sortedPagerEntries(downloaded, field: sortField, order: sortOrder, publishedById: publishedById)

            let fullList = downloaded
            guard let fullIndex = fullList.firstIndex(where: { $0.youtubeId == currentVideoId }) else { return nil }

            if hideWatched {
                let unwatchedIds = try await unwatchedVideoIds(inPlaylist: playlistId, client: client)
                let filtered = downloaded.filter { unwatchedIds.contains($0.youtubeId) || $0.youtubeId == currentVideoId }
                if let filteredIndex = filtered.firstIndex(where: { $0.youtubeId == currentVideoId }),
                   filteredIndex < filtered.count - 1 {
                    downloaded = filtered
                }
            }

            guard let currentIndex = downloaded.firstIndex(where: { $0.youtubeId == currentVideoId }) else { return nil }

            let window = pagerWindow(around: currentIndex, count: downloaded.count)
            let windowEntries = Array(downloaded[window])
            let videosById = await fetchVideos(for: windowEntries, client: client)
            var pagerEntries: [PlaylistPagerEntry] = []
            for index in window {
                let windowEntry = downloaded[index]
                guard let video = videosById[windowEntry.youtubeId] else { continue }
                // Numbered by where the entry really sits in the playlist, so
                // the numbers down the side match the header's own total.
                let realPosition = (fullList.firstIndex(where: { $0.youtubeId == windowEntry.youtubeId }) ?? index) + 1
                pagerEntries.append(PlaylistPagerEntry(video: video, position: realPosition, isCurrent: index == currentIndex))
            }

            return PlaylistPagerPage(
                playlistId: playlistId,
                playlistName: entry.playlistMeta?.playlistName,
                currentPosition: fullIndex + 1,
                totalCount: fullList.count,
                entries: pagerEntries
            )
        } catch {
            return nil
        }
    }

    /// Fetches one full `Video` per windowed entry, concurrently, silently dropping any single fetch that fails.
    private nonisolated static func fetchVideos(for entries: [PlaylistEntry], client: TAClient) async -> [String: Video] {
        await withTaskGroup(of: (String, Video?).self) { group in
            for entry in entries {
                group.addTask { (entry.youtubeId, try? await client.video(id: entry.youtubeId)) }
            }
            var videosById: [String: Video] = [:]
            for await (youtubeId, video) in group {
                if let video { videosById[youtubeId] = video }
            }
            return videosById
        }
    }

    nonisolated static func pagerWindow(around currentIndex: Int, count: Int, before: Int = 1, after: Int = 3) -> Range<Int> {
        guard count > 0, currentIndex >= 0, currentIndex < count else { return 0..<0 }
        let availableBefore = currentIndex
        let availableAfter = count - 1 - currentIndex

        let takenBefore = min(before, availableBefore)
        let takenAfter = min(after, availableAfter)

        // Redistribute whatever one side couldn't supply to the other, up
        // to what that other side actually has left.
        let shortfallBefore = before - takenBefore
        let shortfallAfter = after - takenAfter
        let extraAfter = min(shortfallBefore, availableAfter - takenAfter)
        let extraBefore = min(shortfallAfter, availableBefore - takenBefore)

        let lower = currentIndex - (takenBefore + extraBefore)
        let upper = currentIndex + (takenAfter + extraAfter)
        return lower..<(upper + 1)
    }

    public func loadCommentsIfNeeded() async {
        guard !didLoadComments else { return }
        didLoadComments = true
        commentsState = .loading
        do {
            let comments = try await client.comments(videoId: videoId)
            commentsState = .loaded(CommentTree.build(from: comments))
        } catch {
            didLoadComments = false
            commentsState = .failed(Self.taError(error))
        }
    }

    public func retryComments() async {
        didLoadComments = false
        await loadCommentsIfNeeded()
    }

    public func loadSimilarIfNeeded() async {
        guard !didLoadSimilar else { return }
        didLoadSimilar = true
        similarState = .loading
        do {
            let similar = try await client.similarVideos(videoId: videoId)
            similarState = .loaded(similar)
        } catch {
            didLoadSimilar = false
            similarState = .failed(Self.taError(error))
        }
    }

    public func retrySimilar() async {
        didLoadSimilar = false
        await loadSimilarIfNeeded()
    }

    public func applyLocalPlaybackResult(position: Double, watched: Bool) {
        guard let video = videoState.value else { return }
        var updated = video
        var player = updated.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
        if watched {
            player.watched = true
            player.position = nil
            player.progress = nil
        } else if position > 0 {
            // Deliberately NOT `player.watched = false`.
            player.position = position
            if let duration = player.duration, duration > 0 {
                player.progress = min(max(position / duration * 100, 0), 100)
            } else {
                // The position moved but a percentage cannot be derived from it. Leaving
                // the old one would draw a bar that disagrees with the position it sits
                // under — `VideoRow` and `InlinePlayerSection` both read `progress` direct.
                player.progress = nil
            }
        }
        // `position <= 0` and not watched: nothing played.
        updated.player = player
        videoState = .loaded(updated)
    }

    @discardableResult
    public func setWatched(_ isWatched: Bool) async -> Bool {
        guard let video = videoState.value else { return false }
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            var updated = video
            var player = updated.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = isWatched
            if isWatched {
                player.position = nil
                player.progress = nil
            }
            updated.player = player
            videoState = .loaded(updated)
            return true
        } catch {
            return false
        }
    }

    /// The protocol's video-argument form.
    public func setWatched(_ video: Video, isWatched: Bool) async {
        if video.id == videoId { _ = await setWatched(isWatched); return }
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            applySimilarWatchedLocally(id: video.id, isWatched: isWatched)
        } catch {
            // Same stance as `PlaylistDetailStore.setWatched`: a secondary row's failed
            // toggle is not worth invalidating this screen.
        }
    }

    public func removeVideoLocally(id: String) {
        if case .loaded(let videos) = similarState {
            similarState = .loaded(videos.filter { $0.id != id })
        }
    }

    /// Mirrors `HomeStore`'s own local-apply helper, including its clear-position-when-
    /// watched rule.
    private func applySimilarWatchedLocally(id: String, isWatched: Bool) {
        guard case .loaded(let videos) = similarState else { return }
        similarState = .loaded(videos.map { video in
            guard video.id == id else { return video }
            var updated = video
            var player = updated.player ?? VideoPlayerState(
                duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = isWatched
            if isWatched { player.position = nil; player.progress = nil }
            updated.player = player
            return updated
        })
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
