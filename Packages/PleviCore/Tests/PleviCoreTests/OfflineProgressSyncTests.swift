import Foundation
import Testing
@testable import PleviCore

extension MockedNetworkTests {

@MainActor
@Suite("OfflineProgressSync", .serialized)
struct OfflineProgressSyncTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private func makeLedgerDefaults() -> UserDefaults {
        let suite = "OfflineProgressSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private nonisolated static func videoJSON(id: String, watched: Bool?) -> Data {
        let watchedField = watched.map { "\($0)" } ?? "null"
        return Data("""
        {"youtube_id": "\(id)", "title": "t", "player": {"duration": 100, "watched": \(watchedField)}}
        """.utf8)
    }

    @Test("a pending position is POSTed and cleared once delivered")
    func flushesPendingPosition() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))

        let progressPosts = CountBox(0)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/video/v1/") == true, request.httpMethod == "GET" {
                return .init(statusCode: 200, body: Self.videoJSON(id: "v1", watched: false))
            }
            if request.url?.absoluteString.contains("/progress/") == true {
                progressPosts.value += 1
                return .init(statusCode: 200, body: Data("{}".utf8))
            }
            return .init(statusCode: 404)
        }

        await OfflineProgressSync.flush(ledger: ledger, client: client, now: Date(timeIntervalSince1970: 200))
        #expect(progressPosts.value == 1)
        #expect(ledger.entry(for: "v1") == nil)
    }

    @Test("a server-side watched flag drops the entry without posting a stale position")
    func dropsWhenServerAlreadyWatched() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))

        let progressPosts = CountBox(0)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/video/v1/") == true, request.httpMethod == "GET" {
                return .init(statusCode: 200, body: Self.videoJSON(id: "v1", watched: true))
            }
            if request.url?.absoluteString.contains("/progress/") == true {
                progressPosts.value += 1
            }
            return .init(statusCode: 200, body: Data("{}".utf8))
        }

        await OfflineProgressSync.flush(ledger: ledger, client: client, now: Date(timeIntervalSince1970: 200))
        #expect(progressPosts.value == 0)
        #expect(ledger.entry(for: "v1") == nil)
    }

    @Test("a 404 drops the entry — the video is gone")
    func dropsOn404() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }

        await OfflineProgressSync.flush(ledger: ledger, client: client, now: Date(timeIntervalSince1970: 200))
        #expect(ledger.entry(for: "v1") == nil)
    }

    @Test("a watched entry POSTs setWatched, not setProgress")
    func flushesWatchedEntry() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedWatched(videoId: "v1", at: Date(timeIntervalSince1970: 100))

        let watchedPosts = CountBox(0)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/video/v1/") == true, request.httpMethod == "GET" {
                return .init(statusCode: 200, body: Self.videoJSON(id: "v1", watched: false))
            }
            if request.url?.absoluteString.contains("/watched/") == true {
                watchedPosts.value += 1
            }
            return .init(statusCode: 204)
        }

        await OfflineProgressSync.flush(ledger: ledger, client: client, now: Date(timeIntervalSince1970: 200))
        #expect(watchedPosts.value == 1)
        #expect(ledger.entry(for: "v1") == nil)
    }

    @Test("a POST failure leaves the entry queued for the next flush")
    func leavesEntryQueuedOnFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 100))

        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/video/v1/") == true, request.httpMethod == "GET" {
                return .init(statusCode: 200, body: Self.videoJSON(id: "v1", watched: false))
            }
            return .init(statusCode: 500)
        }

        await OfflineProgressSync.flush(ledger: ledger, client: client, now: Date(timeIntervalSince1970: 200))
        #expect(ledger.entry(for: "v1")?.position == 42)
    }

    @Test("a too-old entry is dropped without ever POSTing")
    func dropsTooOldEntry() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        ledger.recordFailedProgress(videoId: "v1", position: 42, at: Date(timeIntervalSince1970: 0))

        let otherPosts = CountBox(0)
        MockURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("/video/v1/") == true, request.httpMethod == "GET" {
                return .init(statusCode: 200, body: Self.videoJSON(id: "v1", watched: false))
            }
            otherPosts.value += 1
            return .init(statusCode: 200, body: Data("{}".utf8))
        }

        let farFuture = Date(timeIntervalSince1970: 0).addingTimeInterval(OfflineProgressPolicy.maxAge + 1000)
        await OfflineProgressSync.flush(ledger: ledger, client: client, now: farFuture)
        #expect(otherPosts.value == 0)
        #expect(ledger.entry(for: "v1") == nil)
    }
}

}
