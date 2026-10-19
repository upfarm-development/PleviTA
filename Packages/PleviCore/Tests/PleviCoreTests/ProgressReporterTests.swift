
import Foundation
import Testing
@testable import PleviCore

extension MockedNetworkTests {

@MainActor
@Suite("ProgressReporter", .serialized)
struct ProgressReporterTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    @Test("skips the first 10 seconds")
    func skipsFirstTenSeconds() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 100)
        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 200, body: Data("{}".utf8)) }

        let reported = await reporter.reportProgress(position: 5, force: true)
        #expect(reported == false)
        #expect(calls.value == 0)
    }

    @Test("skips the final 5% of duration")
    func skipsFinalFivePercent() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 100)
        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 200, body: Data("{}".utf8)) }

        // 96/100 is within the final 5% (>= 95).
        let reported = await reporter.reportProgress(position: 96, force: true)
        #expect(reported == false)
        #expect(calls.value == 0)

        // 90/100 is not.
        let reportedEarlier = await reporter.reportProgress(position: 90, force: true)
        #expect(reportedEarlier == true)
        #expect(calls.value == 1)
    }

    @Test("periodic (non-forced) reports are throttled to every ~10s of playback")
    func throttlesPeriodicReports() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 1000)
        let calls = CountBox(0)
        MockURLProtocol.handler = { request in
            calls.value += 1
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.contains("v1/progress") == true)
            return .init(statusCode: 200, body: Data("{}".utf8))
        }

        #expect(await reporter.reportProgress(position: 15) == true) // first report ever
        #expect(await reporter.reportProgress(position: 18) == false) // < 10s since last
        #expect(await reporter.reportProgress(position: 25) == true) // >= 10s since last (15 -> 25)
        #expect(calls.value == 2)
    }

    @Test("force bypasses the periodic throttle but not the skip window, and de-dupes an identical position")
    func forceBypassesThrottleButNotSkipWindow() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 1000)
        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 200, body: Data("{}".utf8)) }

        #expect(await reporter.reportProgress(position: 15) == true)
        // A pause 1s later: force:true still reports even though <10s elapsed.
        #expect(await reporter.reportProgress(position: 16, force: true) == true)
        #expect(calls.value == 2)
        #expect(await reporter.reportProgress(position: 16, force: true) == false)
        #expect(calls.value == 2)
    }

    @Test("markWatchedOnCompletion posts /api/watched/ once, even if called twice")
    func marksWatchedOnce() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 100)
        let calls = CountBox(0)
        MockURLProtocol.handler = { request in
            calls.value += 1
            #expect(request.url?.absoluteString.contains("/watched/") == true)
            return .init(statusCode: 204)
        }

        await reporter.markWatchedOnCompletion()
        await reporter.markWatchedOnCompletion()
        #expect(calls.value == 1)
    }

    @Test("with no known duration, only the first-10s window applies")
    func noDurationOnlySkipsFirstWindow() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: nil)
        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 200, body: Data("{}".utf8)) }

        #expect(await reporter.reportProgress(position: 9999, force: true) == true)
        #expect(calls.value == 1)
    }


    /// Rewritten from "...and the throttle is not consumed", which pinned an overcorrection.
    @Test("a failed progress POST is recorded in the outbox without breaking the throttle")
    func failedProgressGoesToOutbox() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 1000, outbox: ledger)

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }
        #expect(await reporter.reportProgress(position: 15, force: true) == true)
        #expect(ledger.entry(for: "v1")?.position == 15)

        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 200, body: Data("{}".utf8)) }
        // A second later: suppressed, exactly as it would be after a success. This is the
        // assertion that would fail if the throttle were being reset on failure.
        #expect(await reporter.reportProgress(position: 16) == false)
        #expect(calls.value == 0)

        // Ten seconds on: reported, and the outbox entry clears.
        #expect(await reporter.reportProgress(position: 25) == true)
        #expect(calls.value == 1)
        // The entry survives a success, but stops asking to be sent: it is now the local
        // record of where playback reached, which is what an offline open resumes from.
        #expect(ledger.entry(for: "v1")?.needsFlush == false)
        #expect(ledger.entry(for: "v1")?.position == 25)
    }

    @Test("a successful progress POST still leaves a local position to resume from")
    func successfulProgressLeavesLocalPosition() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 1000, outbox: ledger)

        MockURLProtocol.handler = { _ in .init(statusCode: 200, body: Data("{}".utf8)) }
        #expect(await reporter.reportProgress(position: 42, force: true) == true)

        let entry = ledger.entry(for: "v1")
        #expect(entry?.position == 42)
        #expect(entry?.needsFlush == false, "the server already has it; only the local note remains")
    }

    @Test("a failed watched POST is recorded in the outbox and can still be retried")
    func failedWatchedGoesToOutboxAndRetries() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let ledger = OfflinePlaybackLedger(scope: "server-a", defaults: makeLedgerDefaults())
        let reporter = ProgressReporter(client: client, videoId: "v1", duration: 100, outbox: ledger)

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }
        await reporter.markWatchedOnCompletion()
        #expect(ledger.entry(for: "v1")?.watched == true)

        let calls = CountBox(0)
        MockURLProtocol.handler = { _ in calls.value += 1; return .init(statusCode: 204) }
        await reporter.markWatchedOnCompletion()
        #expect(calls.value == 1, "restoring didMarkWatched on failure must let a later call retry")
        #expect(ledger.entry(for: "v1") == nil)
    }

    private nonisolated func makeLedgerDefaults() -> UserDefaults {
        let suite = "ProgressReporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

}
