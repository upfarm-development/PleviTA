
import Foundation
import Observation

@Observable
@MainActor
public final class ChannelsStore {
    public private(set) var items: [Channel] = []
    public private(set) var loadState: LoadState<[Channel]> = .idle
    public private(set) var paginate: Paginate?
    public private(set) var isLoadingNextPage = false
    public var pageError: TAError?

    private let client: TAClient
    private let appSettings: AppSettings
    private var lastQueryKey: String?
    private var generation = 0

    public init(client: TAClient, appSettings: AppSettings) {
        self.client = client
        self.appSettings = appSettings
    }

    /// Re-runs the first page against the current `AppSettings`-derived
    /// query. Skips the network call when nothing that affects the query
    /// changed since the last successful load, unless `force`.
    public func loadFirstPage(force: Bool = false) async {
        let key = currentQueryKey()
        guard force || key != lastQueryKey else { return }
        lastQueryKey = key

        generation += 1
        let currentGeneration = generation
        loadState = .loading
        pageError = nil

        do {
            let page = try await client.channels(page: 1, subscribedOnly: appSettings.channelsSubscribedOnly)
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

    /// Pull-to-refresh (iOS): re-fetches regardless of whether the query changed.
    public func refresh() async {
        lastQueryKey = nil
        await loadFirstPage(force: true)
    }

    /// Call from each row's `.task`/`.onAppear`; fetches the next page once `currentItem` is within the last few loaded items and a next page exists.
    public func loadNextPageIfNeeded(currentItem: Channel) async {
        guard !isLoadingNextPage, let paginate, paginate.hasNextPage else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let prefetchThreshold = 4
        guard index >= items.count - prefetchThreshold else { return }

        let nextPage = (paginate.currentPage ?? 1) + 1
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let currentGeneration = generation
        do {
            let page = try await client.channels(page: nextPage, subscribedOnly: appSettings.channelsSubscribedOnly)
            guard currentGeneration == generation else { return }
            items.append(contentsOf: page.data)
            self.paginate = page.paginate
        } catch {
            guard currentGeneration == generation else { return }
            pageError = Self.taError(error)
        }
    }

    private func currentQueryKey() -> String {
        "\(appSettings.channelsSubscribedOnly)"
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
