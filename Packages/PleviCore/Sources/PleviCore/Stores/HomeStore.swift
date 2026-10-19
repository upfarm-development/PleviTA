
import Foundation
import Observation

@Observable
@MainActor
public final class HomeStore: VideoMutating {
    public private(set) var continueWatching: LoadState<[Video]> = .idle
    public private(set) var gridItems: [Video] = []
    public private(set) var gridLoadState: LoadState<[Video]> = .idle
    public private(set) var gridPaginate: Paginate?
    public private(set) var isLoadingNextPage = false
    public var gridPageError: TAError?
    public private(set) var pinnedPlaylists: [String: Playlist] = [:]
    public private(set) var pinnedChannels: [String: Channel] = [:]

    private let client: TAClient
    private let appSettings: AppSettings
    private var lastQueryKey: String?
    private var gridGeneration = 0
    private var continueGeneration = 0
    private var pinnedGeneration = 0

    public init(
        client: TAClient,
        appSettings: AppSettings,
        playbackHistory: PlaybackHistory? = nil,
        pinnedItems: PinnedItems? = nil,
        snapshots: HomeSnapshotStore? = nil,
        snapshotScope: String? = nil
    ) {
        self.client = client
        self.appSettings = appSettings
        self.playbackHistory = playbackHistory
        self.pinnedItems = pinnedItems
        self.snapshots = snapshots
        self.snapshotScope = snapshotScope
        VideoRemovalCenter.shared.register(self)
        seedFromSnapshot()
    }

    private let snapshots: HomeSnapshotStore?
    private let snapshotScope: String?

    /// Shows what Home last showed, straight away, so a slow connection opens on content instead of
    /// a spinner. The fetch that follows replaces it; a failed fetch leaves it in place.
    private func seedFromSnapshot() {
        guard let snapshots, let snapshotScope, let snapshot = snapshots.load(scope: snapshotScope) else { return }
        if !snapshot.continueWatching.isEmpty {
            continueWatching = .loaded(ordered(snapshot.continueWatching))
        }
        if snapshot.queryKey == currentQueryKey(), !snapshot.newlyAdded.isEmpty {
            gridItems = snapshot.newlyAdded
            gridLoadState = .loaded(snapshot.newlyAdded)
        }
    }

    /// Loads Home and saves the result as the snapshot before returning, for the background
    /// refresh, which must not report itself done while the write is still pending. `false` when a
    /// fetch failed or this store has nowhere to save.
    public func refreshSnapshotNow() async -> Bool {
        guard let snapshots, let snapshotScope else { return false }
        await loadContinueWatching()
        await reloadGrid(force: true)
        guard case .loaded(let watching) = continueWatching, case .loaded = gridLoadState, gridPageError == nil else { return false }
        let snapshot = HomeSnapshot(continueWatching: watching, newlyAdded: Array(gridItems.prefix(HomeSnapshotStore.gridLimit)), queryKey: currentQueryKey())
        await Task.detached(priority: .utility) { snapshots.save(snapshot, scope: snapshotScope) }.value
        return true
    }

    /// Writes what is on screen after a successful fetch, off the main actor.
    private func persistSnapshot() {
        guard let snapshots, let snapshotScope else { return }
        guard case .loaded(let watching) = continueWatching, case .loaded = gridLoadState else { return }
        let snapshot = HomeSnapshot(continueWatching: watching, newlyAdded: Array(gridItems.prefix(HomeSnapshotStore.gridLimit)), queryKey: currentQueryKey())
        Task.detached(priority: .utility) { snapshots.save(snapshot, scope: snapshotScope) }
    }

    private let playbackHistory: PlaybackHistory?
    private let pinnedItems: PinnedItems?

    /// Leads Continue Watching with what this user actually watched most recently.
    private func ordered(_ videos: [Video]) -> [Video] {
        guard let playbackHistory else { return videos }
        return playbackHistory.ordered(videos, recentlyPlayedFirst: appSettings.recentlyPlayedFirst)
    }

    /// Loads both the continue-watching row and the first grid page. Safe to
    /// call every time `HomeView` appears — `reloadGrid` is a no-op unless
    /// this is the first load or the settings-derived query changed.
    public func loadInitial() async {
        async let continueWatchingLoad: Void = loadContinueWatching()
        async let gridLoad: Void = reloadGrid()
        async let pinnedLoad: Void = loadPinned()
        _ = await (continueWatchingLoad, gridLoad, pinnedLoad)
    }

    /// Refreshes the rendered data (title/thumbnail/entry count) for every current pin.
    public func loadPinned() async {
        guard let pinnedItems else { return }
        pinnedGeneration += 1
        let generation = pinnedGeneration
        let pins = pinnedItems.items
        let client = self.client

        let results = await withTaskGroup(of: PinnedFetchResult.self) { group in
            for pin in pins {
                group.addTask { await Self.fetchPin(pin, client: client) }
            }
            var collected: [PinnedFetchResult] = []
            for await result in group { collected.append(result) }
            return collected
        }

        guard generation == pinnedGeneration else { return }
        for result in results {
            switch result {
            case .playlist(let playlist):
                pinnedPlaylists[playlist.id] = playlist
                pinnedItems.refreshSnapshot(playlist)
            case .channel(let channel):
                pinnedChannels[channel.id] = channel
                pinnedItems.refreshSnapshot(channel)
            case .notFound(let kind, let id):
                // D6: unpin only on a confirmed 404 — a network error must never take a pin
                // away, it just leaves the last-known snapshot on screen.
                pinnedItems.unpin(kind, id: id)
                switch kind {
                case .playlist: pinnedPlaylists.removeValue(forKey: id)
                case .channel: pinnedChannels.removeValue(forKey: id)
                }
            case .unchanged:
                break
            }
        }
    }

    private enum PinnedFetchResult: Sendable {
        case playlist(Playlist)
        case channel(Channel)
        case notFound(PinnedItem.Kind, String)
        case unchanged
    }

    private nonisolated static func fetchPin(_ pin: PinnedItem, client: TAClient) async -> PinnedFetchResult {
        do {
            switch pin.kind {
            case .playlist:
                return .playlist(try await client.playlist(id: pin.targetId))
            case .channel:
                return .channel(try await client.channel(id: pin.targetId))
            }
        } catch {
            if (error as? TAError) == .notFound {
                return .notFound(pin.kind, pin.targetId)
            }
            return .unchanged
        }
    }

    /// Pull-to-refresh (iOS): re-fetches both rows regardless of whether the
    /// query changed.
    public func refresh() async {
        lastQueryKey = nil
        await loadInitial()
    }

    /// Re-sorts the Continue Watching row already on screen against the current play history.
    /// The history can change under a loaded Home, when another device's plays arrive from
    /// iCloud, and the order was only ever applied when the row was fetched.
    public func reapplyHistoryOrdering() {
        guard case .loaded(let items) = continueWatching else { return }
        let reordered = ordered(items)
        guard reordered.map(\.id) != items.map(\.id) else { return }
        continueWatching = .loaded(reordered)
    }

    public func loadContinueWatching() async {
        continueGeneration += 1
        let generation = continueGeneration
        let priorItems: [Video]? = {
            if case .loaded(let items) = continueWatching { return items }
            return nil
        }()
        if priorItems == nil {
            continueWatching = .loading
        }
        do {
            let page = try await client.videos(VideoListQuery(watch: .continue))
            guard generation == continueGeneration else { return }
            continueWatching = .loaded(ordered(page.data))
            persistSnapshot()
        } catch {
            guard generation == continueGeneration else { return }
            if let priorItems {
                continueWatching = .loaded(priorItems)
            } else {
                continueWatching = .failed(Self.taError(error))
            }
        }
    }

    /// Re-runs the grid's first page against the current `AppSettings`-
    /// derived query. Skips the network call when nothing that affects the
    /// query changed since the last successful load, unless `force`.
    public func reloadGrid(force: Bool = false) async {
        let key = currentQueryKey()
        guard force || key != lastQueryKey else { return }
        lastQueryKey = key

        gridGeneration += 1
        let generation = gridGeneration
        gridLoadState = .loading
        gridPageError = nil

        do {
            let page = try await client.videos(makeQuery(page: 1))
            guard generation == gridGeneration else { return }
            gridItems = page.data
            gridPaginate = page.paginate
            gridLoadState = .loaded(page.data)
            persistSnapshot()
        } catch {
            guard generation == gridGeneration else { return }
            if gridItems.isEmpty {
                gridLoadState = .failed(Self.taError(error))
            } else {
                gridLoadState = .loaded(gridItems)
                gridPageError = Self.taError(error)
            }
        }
    }

    /// Call from each grid item's `.task`/`.onAppear`; fetches the next page once `currentItem` is within the last few loaded items and a next page exists.
    public func loadNextPageIfNeeded(currentItem: Video) async {
        guard !isLoadingNextPage, let paginate = gridPaginate, paginate.hasNextPage else { return }
        guard let index = gridItems.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let prefetchThreshold = 4
        guard index >= gridItems.count - prefetchThreshold else { return }

        let nextPage = (paginate.currentPage ?? 1) + 1
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let generation = gridGeneration
        do {
            let page = try await client.videos(makeQuery(page: nextPage))
            guard generation == gridGeneration else { return }
            gridItems.append(contentsOf: page.data)
            gridPaginate = page.paginate
        } catch {
            guard generation == gridGeneration else { return }
            gridPageError = Self.taError(error)
        }
    }

    public func setWatched(_ video: Video, isWatched: Bool) async {
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            applyWatchedLocally(id: video.id, isWatched: isWatched)
        } catch {
            gridPageError = Self.taError(error)
        }
    }

    private func applyWatchedLocally(id: String, isWatched: Bool) {
        func apply(_ video: Video) -> Video {
            guard video.id == id else { return video }
            var updated = video
            var player = updated.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = isWatched
            if isWatched {
                // Marking a video fully watched clears in-progress state —
                // matches the mock server and the most plausible real
                // behavior (a finished video is no longer "in progress").
                player.position = nil
                player.progress = nil
            }
            updated.player = player
            return updated
        }

        gridItems = gridItems.map(apply)
        if case .loaded(let items) = continueWatching {
            let updated = items.map(apply)
            // A video just marked watched no longer belongs in "continue
            // watching" (its progress was just cleared above).
            continueWatching = .loaded(ordered(isWatched ? updated.filter { $0.id != id } : updated))
            // Marked watched means it has left the continue set on the server too
            // (`WatchState.change_vid_state` deletes the progress key), so it should stop
            // leading this row as well.
            if isWatched { playbackHistory?.forget(id) }
        }
        if appSettings.hideWatched(in: .home), isWatched {
            gridItems.removeAll { $0.id == id }
        }
    }

    public func removeVideoLocally(id: String) {
        gridItems.removeAll { $0.id == id }
        if case .loaded(let items) = continueWatching {
            continueWatching = .loaded(items.filter { $0.id != id })
        }
        // Unconditionally, unlike `applyWatchedLocally` — which only forgets inside its own `.loaded` branch.
        playbackHistory?.forget(id)
    }

    private func currentQueryKey() -> String {
        "\(appSettings.homeSortField.rawValue)|\(appSettings.homeSortOrder.rawValue)|\(appSettings.hideWatched(in: .home))|\(appSettings.videoTypeFilter?.rawValue ?? "all")"
    }

    private func makeQuery(page: Int) -> VideoListQuery {
        VideoListQuery(
            page: page,
            watch: appSettings.hideWatched(in: .home) ? .unwatched : nil,
            sort: VideoListQuery.SortField(rawValue: appSettings.homeSortField.rawValue),
            order: VideoListQuery.SortOrder(rawValue: appSettings.homeSortOrder.rawValue),
            type: appSettings.videoTypeFilter.flatMap { VideoListQuery.VideoType(rawValue: $0.rawValue) }
        )
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
