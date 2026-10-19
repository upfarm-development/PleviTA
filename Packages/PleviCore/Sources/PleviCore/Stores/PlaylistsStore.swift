
import Foundation
import Observation

@Observable
@MainActor
public final class PlaylistsStore {
    public private(set) var items: [Playlist] = []
    public private(set) var loadState: LoadState<[Playlist]> = .idle
    public private(set) var paginate: Paginate?
    public private(set) var isLoadingNextPage = false
    public var pageError: TAError?

    public var typeFilter: Endpoint.PlaylistType?

    private let client: TAClient
    private let appSettings: AppSettings
    private var lastQueryKey: String?
    private var generation = 0

    public init(client: TAClient, appSettings: AppSettings) {
        self.client = client
        self.appSettings = appSettings
    }

    /// Re-runs the first page against the current settings/type-filter
    /// derived query. Skips the network call when nothing that affects the
    /// query changed since the last successful load, unless `force`.
    public func loadFirstPage(force: Bool = false) async {
        let key = currentQueryKey()
        guard force || key != lastQueryKey else { return }
        lastQueryKey = key

        generation += 1
        let currentGeneration = generation
        loadState = .loading
        pageError = nil

        do {
            let page = try await client.playlists(page: 1, subscribedOnly: appSettings.playlistsSubscribedOnly, type: typeFilter)
            guard currentGeneration == generation else { return }
            items = Self.sorted(page.data, field: appSettings.playlistsSortField, order: appSettings.playlistsSortOrder)
            paginate = page.paginate
            loadState = .loaded(items)
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

    /// Pull-to-refresh (iOS): re-fetches regardless of whether the query changed.
    public func refresh() async {
        lastQueryKey = nil
        await loadFirstPage(force: true)
    }

    /// Call from each grid card's `.task`/`.onAppear`; fetches the next page once `currentItem` is within the last few loaded items and a next page exists.
    public func loadNextPageIfNeeded(currentItem: Playlist) async {
        guard !isLoadingNextPage, let paginate, paginate.hasNextPage else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let prefetchThreshold = 4
        guard index >= items.count - prefetchThreshold else { return }

        let nextPage = (paginate.currentPage ?? 1) + 1
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let currentGeneration = generation
        do {
            let page = try await client.playlists(page: nextPage, subscribedOnly: appSettings.playlistsSubscribedOnly, type: typeFilter)
            guard currentGeneration == generation else { return }
            // Re-sorting the whole (now-larger) array after every append — rather than only sorting each page in isolation.
            items = Self.sorted(items + page.data, field: appSettings.playlistsSortField, order: appSettings.playlistsSortOrder)
            self.paginate = page.paginate
        } catch {
            guard currentGeneration == generation else { return }
            pageError = Self.taError(error)
        }
    }

    /// Re-sorts the already-loaded `items` in place using the current `AppSettings.playlistsSortField`/`playlistsSortOrder`.
    public func resort() {
        items = Self.sorted(items, field: appSettings.playlistsSortField, order: appSettings.playlistsSortOrder)
    }

    private func currentQueryKey() -> String {
        "\(appSettings.playlistsSubscribedOnly)|\(typeFilter?.rawValue ?? "all")"
    }

    nonisolated static func sorted(_ playlists: [Playlist], field: PlaylistsSortField, order: HomeSortOrder) -> [Playlist] {
        playlists.sorted { a, b in
            let result: ComparisonResult
            switch field {
            case .name:
                result = (a.playlistName ?? "").localizedCaseInsensitiveCompare(b.playlistName ?? "")
            case .channel:
                result = (a.playlistChannel ?? "").localizedCaseInsensitiveCompare(b.playlistChannel ?? "")
            }
            return order == .asc ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
