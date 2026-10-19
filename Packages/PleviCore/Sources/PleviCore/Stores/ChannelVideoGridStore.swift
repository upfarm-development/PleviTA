
import Foundation
import Observation

@Observable
@MainActor
public final class ChannelVideoGridStore: VideoMutating {
    public private(set) var items: [Video] = []
    public private(set) var loadState: LoadState<[Video]> = .idle
    public private(set) var paginate: Paginate?
    public private(set) var isLoadingNextPage = false
    public var pageError: TAError?

    private let client: TAClient
    private let appSettings: AppSettings
    private let channelId: String
    private let videoType: VideoListQuery.VideoType?
    private var lastQueryKey: String?
    private var generation = 0

    public init(client: TAClient, appSettings: AppSettings, channelId: String, videoType: VideoListQuery.VideoType?) {
        self.client = client
        self.appSettings = appSettings
        self.channelId = channelId
        self.videoType = videoType
        VideoRemovalCenter.shared.register(self)
    }

    /// Loads the first page if this is the first call, or if the
    /// settings-derived query changed since the last successful load. Safe
    /// to call every time the owning tab appears.
    public func loadFirstPageIfNeeded() async {
        await reload(force: false)
    }

    public func reload(force: Bool) async {
        let key = currentQueryKey()
        guard force || key != lastQueryKey else { return }
        lastQueryKey = key

        generation += 1
        let currentGeneration = generation
        loadState = .loading
        pageError = nil

        do {
            let page = try await client.videos(makeQuery(page: 1))
            guard currentGeneration == generation else { return }
            items = page.data
            paginate = page.paginate
            loadState = .loaded(page.data)
        } catch {
            guard currentGeneration == generation else { return }
            if items.isEmpty {
                loadState = .failed(Self.taError(error))
            } else {
                loadState = .loaded(items)
                pageError = Self.taError(error)
            }
        }
    }

    public func loadNextPageIfNeeded(currentItem: Video) async {
        guard !isLoadingNextPage, let paginate, paginate.hasNextPage else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let prefetchThreshold = 4
        guard index >= items.count - prefetchThreshold else { return }

        let nextPage = (paginate.currentPage ?? 1) + 1
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let currentGeneration = generation
        do {
            let page = try await client.videos(makeQuery(page: nextPage))
            guard currentGeneration == generation else { return }
            items.append(contentsOf: page.data)
            self.paginate = page.paginate
        } catch {
            guard currentGeneration == generation else { return }
            pageError = Self.taError(error)
        }
    }

    /// `POST /api/watched/` for a single card's context-menu action (same
    /// pattern as `HomeStore.setWatched`).
    public func setWatched(_ video: Video, isWatched: Bool) async {
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            applyWatchedLocally(id: video.id, isWatched: isWatched)
        } catch {
            pageError = Self.taError(error)
        }
    }

    public func apply(updated video: Video) {
        guard let index = items.firstIndex(where: { $0.id == video.id }) else { return }
        items[index] = video
    }

    public func removeVideoLocally(id: String) { items.removeAll { $0.id == id } }

    /// Applies a bulk "mark all watched" to every already-loaded item without a round trip per video.
    public func markAllLoadedWatchedLocally() {
        for video in items {
            applyWatchedLocally(id: video.id, isWatched: true)
        }
    }

    private func applyWatchedLocally(id: String, isWatched: Bool) {
        func apply(_ video: Video) -> Video {
            guard video.id == id else { return video }
            var updated = video
            var player = updated.player ?? VideoPlayerState(duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil)
            player.watched = isWatched
            if isWatched {
                player.position = nil
                player.progress = nil
            }
            updated.player = player
            return updated
        }
        items = items.map(apply)
        if appSettings.hideWatched(in: .channelVideos), isWatched {
            items.removeAll { $0.id == id }
        }
    }

    public func allVideos() async throws -> [Video] {
        var all: [Video] = []
        var page = 1
        while true {
            let result = try await client.videos(makeQuery(page: page))
            all.append(contentsOf: result.data)
            guard let paginate = result.paginate, paginate.hasNextPage else { break }
            page += 1
            if page > 200 { break }
        }
        return all
    }

    private func currentQueryKey() -> String {
        "\(appSettings.channelVideoSortField.rawValue)|\(appSettings.channelVideoSortOrder.rawValue)|\(appSettings.hideWatched(in: .channelVideos))"
    }

    private func makeQuery(page: Int) -> VideoListQuery {
        VideoListQuery(
            page: page,
            watch: appSettings.hideWatched(in: .channelVideos) ? .unwatched : nil,
            sort: VideoListQuery.SortField(rawValue: appSettings.channelVideoSortField.rawValue),
            order: VideoListQuery.SortOrder(rawValue: appSettings.channelVideoSortOrder.rawValue),
            type: videoType,
            channel: channelId
        )
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
