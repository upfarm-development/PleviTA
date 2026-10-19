
import Foundation
import Observation

@Observable
@MainActor
public final class SearchStore: VideoMutating {
    /// Minimum query length before a request fires at all.
    public static let minimumQueryLength = 2
    public static let debounceNanoseconds: UInt64 = 300_000_000

    public private(set) var loadState: LoadState<SearchResults> = .idle
    /// The exact text a completed/in-flight search was fired for — lets the
    /// view show "No results for <query>" against the query that actually
    /// ran, not whatever is currently in the text field a keystroke later.
    public private(set) var lastSearchedQuery: String = ""

    private let client: TAClient
    private var task: Task<Void, Never>?
    private var generation = 0
    /// The text the currently armed-or-running search is *for*, as opposed to `lastSearchedQuery`, which is the text a search has already been fired for.
    private var pendingQuery: String = ""

    public init(client: TAClient) {
        self.client = client
        VideoRemovalCenter.shared.register(self)
    }

    /// Call on every text-field change. Trims whitespace, debounces, and
    /// enforces the minimum length; safe to call rapidly (each call
    /// supersedes the last).
    public func updateQuery(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= Self.minimumQueryLength else {
            task?.cancel()
            generation += 1
            loadState = .idle
            lastSearchedQuery = ""
            pendingQuery = ""
            return
        }

        guard query != pendingQuery else { return }
        pendingQuery = query

        task?.cancel()
        generation += 1
        let currentGeneration = generation

        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.performSearch(query: query, generation: currentGeneration)
        }
    }

    /// Re-runs the last searched query (Retry button on the error state).
    public func retry() async {
        let query = lastSearchedQuery
        guard query.count >= Self.minimumQueryLength else { return }
        task?.cancel()
        pendingQuery = query
        generation += 1
        await performSearch(query: query, generation: generation)
    }

    private func performSearch(query: String, generation: Int) async {
        guard generation == self.generation else { return }
        loadState = .loading
        lastSearchedQuery = query
        do {
            let results = try await client.search(query: query)
            guard generation == self.generation, !Task.isCancelled else { return }
            // Show what the server said before widening it.
            loadState = .loaded(results)
            await widen(results, query: query, generation: generation)
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            loadState = .failed((error as? TAError) ?? .network(error.localizedDescription))
        }
    }

    /// Runs `SearchAccentProbe`'s extra queries and folds their hits into what is already on screen.
    private func widen(_ primary: SearchResults, query: String, generation: Int) async {
        let probes = SearchAccentProbe.probes(for: query)
        guard !probes.isEmpty else { return }

        let client = self.client
        let widened = await withTaskGroup(of: SearchResults?.self) { group in
            for probe in probes {
                group.addTask {
                    try? await client.search(query: probe)
                }
            }
            var merged = SearchResults()
            for await result in group {
                guard let result else { continue }
                merged = merged.appending(result.filtered(matching: query))
            }
            return merged
        }

        guard generation == self.generation, !Task.isCancelled else { return }
        // Re-read rather than reusing `primary`: `applyLocalPlaybackResult` and friends can
        // have mutated what is on screen while the probes were in flight.
        guard case .loaded(let current) = loadState else { return }
        let combined = current.appending(widened)
        guard combined != current else { return }
        loadState = .loaded(combined)
    }

    public func setWatched(_ video: Video, isWatched: Bool) async {
        do {
            try await client.setWatched(id: video.id, isWatched: isWatched)
            applyWatchedLocally(id: video.id, isWatched: isWatched)
        } catch {
        }
    }

    private func applyWatchedLocally(id: String, isWatched: Bool) {
        guard case .loaded(var results) = loadState else { return }

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

        results.videoResults = results.videoResults?.map(apply)
        results.fulltextResults = results.fulltextResults?.map(apply)
        loadState = .loaded(results)
    }

    public func removeVideoLocally(id: String) {
        guard case .loaded(var results) = loadState else { return }
        results.videoResults = results.videoResults?.filter { $0.id != id }
        results.fulltextResults = results.fulltextResults?.filter { $0.id != id }
        loadState = .loaded(results)
    }
}
