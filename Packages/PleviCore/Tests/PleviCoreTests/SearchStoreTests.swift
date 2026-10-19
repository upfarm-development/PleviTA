
import Foundation
import Testing
@testable import PleviCore

/// A mutable reference cell so `MockURLProtocol`'s `@Sendable` handler closures can count/record requests.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

extension MockedNetworkTests {

@MainActor
@Suite("SearchStore", .serialized)
struct SearchStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    /// Comfortably longer than `SearchStore.debounceNanoseconds` (300 ms) so
    /// the debounced request has definitely fired and completed by the time
    /// a test asserts on it.
    private nonisolated func awaitDebounce() async throws {
        try await Task.sleep(nanoseconds: SearchStore.debounceNanoseconds + 400_000_000)
    }

    private nonisolated func responseBody(_ results: SearchResults) -> Data {
        struct Wrapper: Encodable { let results: SearchResults }
        return try! JSONEncoder().encode(Wrapper(results: results))
    }

    /// A `SearchAccentProbe` widening request — the user's own text plus one trailing character ("gamma g", "gamma ğ").
    private nonisolated func isWideningProbe(_ request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value
        else { return false }
        let words = value.split(separator: " ")
        return words.count > 1 && words.last?.count == 1
    }

    private nonisolated func emptyResponse() -> MockURLProtocol.StubResponse {
        .init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: responseBody(SearchResults(videoResults: [], channelResults: [], playlistResults: []))
        )
    }

    @Test("fewer than 2 characters never fires a request and stays idle")
    func belowMinimumLengthStaysIdle() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }

        store.updateQuery("")
        store.updateQuery("a")
        try await awaitDebounce()

        if case .idle = store.loadState {} else {
            Issue.record("expected .idle, got \(store.loadState)")
        }
        #expect(requestCount.value == 0)
    }

    @Test("2+ characters debounces then fires exactly one request with the trimmed query")
    func debouncesAndFiresOneRequest() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)
        let lastURL = Box<String?>(nil)
        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            lastURL.value = request.url?.absoluteString
            return .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(videoResults: [], channelResults: [], playlistResults: []))
            )
        }

        // Rapid-fire keystrokes building up "gamma " (with trailing whitespace to also exercise trimming).
        store.updateQuery("g")
        store.updateQuery("ga")
        store.updateQuery("gam")
        store.updateQuery("gamm")
        store.updateQuery("gamma ")
        try await awaitDebounce()

        #expect(requestCount.value == 1)
        #expect(lastURL.value?.contains("query=gamma") == true)
        if case .loaded = store.loadState {} else {
            Issue.record("expected .loaded, got \(store.loadState)")
        }
    }

    @Test("a matching query groups videos, channels, and playlists")
    func loadedResultsExposeAllThreeGroups() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let channel = Channel(channelId: "channel_gamma03", channelName: "Gamma Grill")
        let video = Video(youtubeId: "video003mock", title: "Gamma Grill: Deep Dive #3")
        let playlist = Playlist(playlistId: "playlist_gamma_recipes", playlistName: "Gamma Grill — Recipes")
        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(videoResults: [video], channelResults: [channel], playlistResults: [playlist]))
            )
        }

        store.updateQuery("gamma")
        try await awaitDebounce()

        guard case .loaded(let results) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(results.videoResults?.map(\.id) == ["video003mock"])
        #expect(results.channelResults?.map(\.id) == ["channel_gamma03"])
        #expect(results.playlistResults?.map(\.id) == ["playlist_gamma_recipes"])
        #expect(results.isEmpty == false)
    }

    @Test("a genuine zero-result query loads an empty SearchResults, not an error")
    func zeroResultQueryLoadsEmpty() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults())
            )
        }

        store.updateQuery("zzzznotfound")
        try await awaitDebounce()

        guard case .loaded(let results) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(results.isEmpty == true)
    }

    @Test("a server error surfaces as .failed, and retry() re-fires the last query")
    func serverErrorFailsAndRetryRefires() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            return .init(statusCode: 500, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }

        store.updateQuery("gamma")
        try await awaitDebounce()

        guard case .failed = store.loadState else {
            Issue.record("expected .failed, got \(store.loadState)")
            return
        }
        #expect(requestCount.value == 1)

        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            return .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(channelResults: [Channel(channelId: "channel_gamma03", channelName: "Gamma Grill")]))
            )
        }
        await store.retry()

        #expect(requestCount.value == 2)
        guard case .loaded(let results) = store.loadState else {
            Issue.record("expected .loaded after retry, got \(store.loadState)")
            return
        }
        #expect(results.channelResults?.map(\.id) == ["channel_gamma03"])
    }

    @Test("clearing the query back below the minimum returns to .idle")
    func clearingQueryReturnsToIdle() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(channelResults: [Channel(channelId: "c1", channelName: "C1")]))
            )
        }

        store.updateQuery("gamma")
        try await awaitDebounce()
        if case .loaded = store.loadState {} else {
            Issue.record("expected .loaded before clearing, got \(store.loadState)")
        }

        store.updateQuery("")
        if case .idle = store.loadState {} else {
            Issue.record("expected .idle immediately after clearing, got \(store.loadState)")
        }
    }

    @Test("re-calling updateQuery with the same text after it already loaded doesn't re-fire a request")
    func reappearingWithSameQuerySkipsRefetch() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            return .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(channelResults: [Channel(channelId: "c1", channelName: "C1")]))
            )
        }

        store.updateQuery("gamma")
        try await awaitDebounce()
        #expect(requestCount.value == 1)

        // `.task(id: queryText)` (SearchView) re-invokes this with the exact same text every time that view reappears.
        store.updateQuery("gamma")
        if case .loaded = store.loadState {} else {
            Issue.record("expected .loaded to stay put immediately, got \(store.loadState)")
        }
        try await awaitDebounce()
        #expect(requestCount.value == 1)
    }

    @Test("setWatched updates the matching video's local player state without a re-search")
    func setWatchedAppliesLocally() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)
        let video = Video(
            youtubeId: "video003mock",
            title: "Gamma Grill: Deep Dive #3",
            player: VideoPlayerState(duration: 200, durationStr: "3:20", watched: false, position: nil, progress: nil)
        )
        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            return .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(videoResults: [video]))
            )
        }

        store.updateQuery("gamma")
        try await awaitDebounce()
        #expect(requestCount.value == 1)

        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.contains("watched") == true)
            return .init(statusCode: 204, body: Data())
        }
        await store.setWatched(video, isWatched: true)

        #expect(requestCount.value == 2)
        guard case .loaded(let results) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(results.videoResults?.first?.player?.watched == true)
    }

    @Test("removeVideoLocally drops the id from both videoResults and fulltextResults")
    func removeVideoLocallyDropsFromBothResultLists() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let video = Video(youtubeId: "video003mock", title: "Gamma Grill: Deep Dive #3")
        let fulltextHit = Video(youtubeId: "video003mock", title: "Gamma Grill: Deep Dive #3")
        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: self.responseBody(SearchResults(videoResults: [video], fulltextResults: [fulltextHit]))
            )
        }

        store.updateQuery("gamma")
        try await awaitDebounce()
        guard case .loaded(let before) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(before.videoResults?.map(\.id) == ["video003mock"])
        #expect(before.fulltextResults?.map(\.id) == ["video003mock"])

        store.removeVideoLocally(id: "video003mock")

        guard case .loaded(let after) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(after.videoResults?.isEmpty == true)
        #expect(after.fulltextResults?.isEmpty == true)
    }

    /// The race this pins: search "ab", type a third character, then backspace back to "ab" inside the 300 ms window.
    @Test("backspacing to an already-searched query inside the debounce window cancels the newer task")
    func backspaceInsideDebounceCancelsSupersededTask() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let store = SearchStore(client: client)
        let queries = Box([String]())

        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value ?? ""
            queries.value.append(query)
            let results = SearchResults(videoResults: [], channelResults: [], playlistResults: [])
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.responseBody(results))
        }

        // Land a completed search for "ab" so `lastSearchedQuery` holds it.
        store.updateQuery("ab")
        try await awaitDebounce()
        #expect(queries.value == ["ab"])

        // Type, then backspace well inside the debounce window.
        store.updateQuery("abc")
        try await Task.sleep(nanoseconds: 50_000_000)
        store.updateQuery("ab")
        try await awaitDebounce()

        // "abc" must never have reached the network, and the visible query must be "ab".
        #expect(!queries.value.contains("abc"))
        #expect(store.lastSearchedQuery == "ab")
    }

    /// The reappearing-view case the guard exists for in the first place, kept honest
    /// alongside the fix above: re-asking for text that is already loaded must not re-fire.
    @Test("re-asking for the query already loaded does not fire a second request")
    func repeatedQueryDoesNotRefire() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)
        let requestCount = Box(0)

        MockURLProtocol.handler = { request in
            guard !self.isWideningProbe(request) else { return self.emptyResponse() }
            requestCount.value += 1
            let results = SearchResults(videoResults: [], channelResults: [], playlistResults: [])
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: self.responseBody(results))
        }

        store.updateQuery("ab")
        try await awaitDebounce()
        #expect(requestCount.value == 1)

        store.updateQuery("ab")
        try await awaitDebounce()
        #expect(requestCount.value == 1)
    }

    /// The wiring, not the policy — `SearchAccentProbeTests` owns the probe shapes.
    @Test("a widening probe's hits are merged in under the server's own results")
    func probeHitsAreMergedIn() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let store = SearchStore(client: client)

        MockURLProtocol.handler = { request in
            let value = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "query" })?.value ?? ""
            if value == "skoda" {
                return .init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: self.responseBody(SearchResults(
                        videoResults: [Video(youtubeId: "v1", title: "Skoda Enyaq Coupe RS range test")]
                    ))
                )
            }
            if value == "skoda š" {
                return .init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: self.responseBody(SearchResults(
                        videoResults: [
                            Video(youtubeId: "v2", title: "Škoda Peaq | 936 km on a Single Charge"),
                            // A fuzzy near-miss of the kind these loose probes really do
                            // return; the sieve must drop it.
                            Video(youtubeId: "v9", title: "Cupra Born 58 Geilo test")
                        ],
                        channelResults: [Channel(channelId: "c1", channelName: "Škoda")]
                    ))
                )
            }
            return self.emptyResponse()
        }

        store.updateQuery("skoda")
        try await awaitDebounce()

        guard case .loaded(let results) = store.loadState else {
            Issue.record("expected .loaded, got \(store.loadState)")
            return
        }
        #expect(results.videoResults?.map(\.id) == ["v1", "v2"])
        #expect(results.channelResults?.map(\.id) == ["c1"])
    }
}

}
