
import Foundation
import Observation

/// One playlist row: the server's own entry metadata (title/uploader/idx/ downloaded) plus the matching `Video` document when one exists.
public struct PlaylistEntryDisplay: Identifiable, Sendable {
    public var entry: PlaylistEntry
    public var video: Video?

    public var id: String { entry.id }
    public var isDownloaded: Bool { video != nil }

    public init(entry: PlaylistEntry, video: Video?) {
        self.entry = entry
        self.video = video
    }
}

@Observable
@MainActor
public final class PlaylistDetailStore: VideoMutating {
    public let playlistId: String

    public private(set) var playlistState: LoadState<Playlist> = .idle
    public private(set) var entriesState: LoadState<[PlaylistEntryDisplay]> = .idle

    /// Same `isMarking.../...Error` + `@discardableResult` shape as `ChannelDetailStore.markAllWatched`.
    public var isMarkingAllWatched = false
    public var markAllWatchedError: TAError?

    private let client: TAClient

    public init(client: TAClient, playlistId: String) {
        self.client = client
        self.playlistId = playlistId
        VideoRemovalCenter.shared.register(self)
    }

    public var playlist: Playlist? { playlistState.value }
    public var entries: [PlaylistEntryDisplay] { entriesState.value ?? [] }
    /// The subset of `entries` that have a matching downloaded video.
    public var downloadedEntries: [PlaylistEntryDisplay] { entries.filter(\.isDownloaded) }

    /// `downloadedEntries`, sorted per `PlaylistDetailView`'s sort control (`AppSettings.playlistDetailSortField`/`playlistDetailSortOrder`).
    public func downloadedEntries(
        sortedBy field: PlaylistEntrySortField,
        order: HomeSortOrder,
        hideWatched: Bool = false
    ) -> [PlaylistEntryDisplay] {
        let base = hideWatched
            ? downloadedEntries.filter { $0.video?.player?.watched != true }
            : downloadedEntries
        return Self.sortedEntries(base, field: field, order: order)
    }

    /// Pure, `nonisolated`, unit-testable without a store instance or any networking (same shape as `ChannelDetailStore.resolveTabs`).
    nonisolated static func sortedEntries(_ entries: [PlaylistEntryDisplay], field: PlaylistEntrySortField, order: HomeSortOrder) -> [PlaylistEntryDisplay] {
        entries.sorted { a, b in
            let result: ComparisonResult
            switch field {
            case .playlistOrder:
                let idxA = a.entry.idx ?? Int.max
                let idxB = b.entry.idx ?? Int.max
                result = idxA == idxB ? .orderedSame : (idxA < idxB ? .orderedAscending : .orderedDescending)
            case .title:
                let titleA = a.entry.title ?? a.video?.title ?? ""
                let titleB = b.entry.title ?? b.video?.title ?? ""
                result = titleA.localizedCaseInsensitiveCompare(titleB)
            case .datePublished:
                result = (a.video?.published ?? "").compare(b.video?.published ?? "")
            }
            return order == .asc ? result == .orderedAscending : result == .orderedDescending
        }
    }

    public func load() async {
        await loadPlaylist()
        await loadEntries()
    }

    public func loadPlaylist() async {
        playlistState = .loading
        do {
            let playlist = try await client.playlist(id: playlistId)
            playlistState = .loaded(playlist)
        } catch {
            playlistState = .failed(Self.taError(error))
        }
    }

    public func retryPlaylist() async {
        await loadPlaylist()
    }

    /// Cross-references the playlist's own entries against every page of
    /// `GET /api/video/?playlist=<id>` (defensively paginated like any other
    /// list endpoint) to attach watched state/thumbnail/duration per entry.
    public func loadEntries() async {
        guard let rawEntries = playlistState.value?.playlistEntries else {
            entriesState = .loaded([])
            return
        }
        entriesState = .loading
        do {
            var videoById: [String: Video] = [:]
            var page = 1
            while true {
                let result = try await client.videos(VideoListQuery(page: page, playlist: playlistId))
                for video in result.data { videoById[video.id] = video }
                guard let paginate = result.paginate, paginate.hasNextPage else { break }
                page += 1
                // Defensive cap — a real playlist should never need this
                // many pages; guards against an infinite loop if a server's
                // `hasNextPage` is ever inconsistent.
                if page > 200 { break }
            }

            let ordered = rawEntries.sorted { ($0.idx ?? Int.max) < ($1.idx ?? Int.max) }
            let display = ordered.map { PlaylistEntryDisplay(entry: $0, video: videoById[$0.youtubeId]) }
            entriesState = .loaded(display)
        } catch {
            entriesState = .failed(Self.taError(error))
        }
    }

    public func retryEntries() async {
        await loadEntries()
    }

    /// A single row's watched-toggle context-menu action (mirrors
    /// `ChannelVideoGridStore.setWatched`) — applies the result locally
    /// rather than re-fetching the whole entries list.
    public func setWatched(_ video: Video, isWatched: Bool) async {
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            applyWatchedLocally(id: video.id, isWatched: isWatched)
        } catch {
            // A single row's failed toggle isn't worth invalidating the whole page.
        }
    }

    @discardableResult
    public func markAllWatched() async -> Bool {
        isMarkingAllWatched = true
        markAllWatchedError = nil
        defer { isMarkingAllWatched = false }
        do {
            try await client.setWatched(id: playlistId, isWatched: true)
            markAllLoadedWatchedLocally()
            return true
        } catch {
            markAllWatchedError = Self.taError(error)
            return false
        }
    }

    private func markAllLoadedWatchedLocally() {
        guard var current = entriesState.value else { return }
        for index in current.indices {
            guard var video = current[index].video else { continue }
            var player = video.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = true
            player.position = nil
            player.progress = nil
            video.player = player
            current[index].video = video
        }
        entriesState = .loaded(current)
    }

    private func applyWatchedLocally(id: String, isWatched: Bool) {
        guard var current = entriesState.value else { return }
        for index in current.indices {
            guard var video = current[index].video, video.id == id else { continue }
            var player = video.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = isWatched
            if isWatched {
                player.position = nil
                player.progress = nil
            }
            video.player = player
            current[index].video = video
        }
        entriesState = .loaded(current)
    }

    /// `PlaylistEntryDisplay.isDownloaded` is `video != nil`, and `downloadedEntries` filters on it.
    public func apply(updated video: Video) {
        guard case .loaded(var entries) = entriesState else { return }
        guard let index = entries.firstIndex(where: { $0.video?.id == video.id }) else { return }
        entries[index].video = video
        entriesState = .loaded(entries)
    }

    public func removeVideoLocally(id: String) {
        guard var current = entriesState.value else { return }
        for index in current.indices where current[index].video?.id == id {
            current[index].video = nil
        }
        entriesState = .loaded(current)
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
