// Full login/session-restore/sign-out flows are exercised live against the mock server in the simulator.

import Foundation
import Testing
@testable import PleviCore

@Suite("AuthStore.normalizedURL")
struct AuthStoreTests {
    @Test("defaults to http:// when no scheme is given", arguments: [
        "127.0.0.1:8081",
        "192.168.1.50",
        "tubearchivist.local"
    ])
    func defaultsToHTTP(input: String) {
        let url = AuthStore.normalizedURL(from: input)
        #expect(url?.scheme == "http")
        #expect(url?.host != nil)
    }

    @Test("preserves an explicit https scheme")
    func preservesHTTPS() {
        let url = AuthStore.normalizedURL(from: "https://ta.example.com")
        #expect(url?.scheme == "https")
        #expect(url?.host == "ta.example.com")
    }

    @Test("trims trailing slashes")
    func trimsTrailingSlashes() {
        let url = AuthStore.normalizedURL(from: "http://127.0.0.1:8081///")
        #expect(url?.absoluteString == "http://127.0.0.1:8081")
    }

    @Test("trims surrounding whitespace")
    func trimsWhitespace() {
        let url = AuthStore.normalizedURL(from: "  http://127.0.0.1:8081  ")
        #expect(url?.absoluteString == "http://127.0.0.1:8081")
    }

    @Test("rejects empty input")
    func rejectsEmpty() {
        #expect(AuthStore.normalizedURL(from: "") == nil)
        #expect(AuthStore.normalizedURL(from: "   ") == nil)
    }
}

/// A mutable reference cell so `MockURLProtocol`'s `@Sendable` handler closures can count requests.
private final class RetryAttemptBox: @unchecked Sendable {
    var count = 0
}

extension MockedNetworkTests {

@MainActor
@Suite("AuthStore login retry", .serialized)
struct AuthStoreLoginRetryTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    /// A fresh, isolated `UserDefaults` suite per test, same pattern as `AppSettingsTests.makeDefaults`.
    private func makeSettings() -> AppSettings {
        let suiteName = "com.plevi.ta.tests.authstoreretry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func makeAuthStore(retryDelayNanoseconds: UInt64 = 1_000_000) -> AuthStore {
        AuthStore(
            appSettings: makeSettings(),
            credentialStore: InMemoryCredentialStore(),
            urlSession: MockURLProtocol.makeSession(),
            transientRetryDelayNanoseconds: retryDelayNanoseconds
        )
    }

    /// Stubs for every request `finishLogin` can issue *after* the login/token-validation call itself succeeds.
    private nonisolated func handleAncillaryLoginPaths(_ request: URLRequest) -> MockURLProtocol.StubResponse? {
        switch request.url?.path {
        case "/api/appsettings/token":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("token.json"))
        case "/api/ping":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("ping.json"))
        case "/api/user/me":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        case "/api/user/account":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("account.json"))
        default:
            return nil
        }
    }

    @Test("a LAN address keeps retrying well past the first retry, for the permission prompt")
    func lanAddressRetriesLongEnoughForThePermissionPrompt() async throws {
        let serverURL = URL(string: "http://192.168.99.99:8000")!
        let attempts = RetryAttemptBox()

        MockURLProtocol.handler = { [self] request in
            if let ancillary = handleAncillaryLoginPaths(request) { return ancillary }
            guard request.url?.path == "/api/user/login" else {
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
            attempts.count += 1
            if attempts.count <= 4 {
                return .init(statusCode: 0, error: URLError(.notConnectedToInternet))
            }
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }

        let authStore = makeAuthStore()
        await authStore.loginWithPassword(serverURLText: serverURL.absoluteString, username: "admin", password: "pw")

        #expect(attempts.count == 5)
        #expect(authStore.errorMessage == nil)
        if case .loggedIn = authStore.state {} else {
            Issue.record("Expected .loggedIn, got \(authStore.state)")
        }
    }

    @Test("a remote address still fails fast, with one retry only")
    func remoteAddressStillFailsFast() async throws {
        // The other half of the same decision: the permission prompt only
        // applies to the local network, so a public address that is simply
        // down must not make the user wait out fifteen seconds of spinner.
        let serverURL = URL(string: "https://ta.example.com")!
        let attempts = RetryAttemptBox()

        MockURLProtocol.handler = { [self] request in
            if let ancillary = handleAncillaryLoginPaths(request) { return ancillary }
            attempts.count += 1
            return .init(statusCode: 0, error: URLError(.notConnectedToInternet))
        }

        let authStore = makeAuthStore()
        await authStore.loginWithPassword(serverURLText: serverURL.absoluteString, username: "admin", password: "pw")

        #expect(attempts.count == 2)
        #expect(authStore.errorMessage != nil)
    }

    @Test("loginWithPassword: a transient network failure on the first attempt is retried once and succeeds silently")
    func retriesOnceThenSucceeds() async throws {
        let serverURL = makeServerURL()
        let loginAttempts = RetryAttemptBox()

        MockURLProtocol.handler = { [self] request in
            if let ancillary = handleAncillaryLoginPaths(request) { return ancillary }
            guard request.url?.path == "/api/user/login" else {
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
            loginAttempts.count += 1
            if loginAttempts.count == 1 {
                return .init(statusCode: 0, error: URLError(.notConnectedToInternet))
            }
            return .init(
                statusCode: 204,
                headers: ["Set-Cookie": "sessionid=abc123; Path=/; HttpOnly, csrftoken=xyz789; Path=/"]
            )
        }

        let authStore = makeAuthStore()
        await authStore.loginWithPassword(serverURLText: serverURL.absoluteString, username: "admin", password: "secret")

        #expect(authStore.errorMessage == nil)
        #expect(loginAttempts.count == 2)
        guard case .loggedIn = authStore.state else {
            Issue.record("Expected .loggedIn, got \(authStore.state)")
            return
        }
    }

    @Test("loginWithPassword: a genuinely wrong password is NOT retried and surfaces immediately")
    func wrongPasswordIsNotRetried() async throws {
        let serverURL = makeServerURL()
        let loginAttempts = RetryAttemptBox()

        MockURLProtocol.handler = { request in
            guard request.url?.path == "/api/user/login" else {
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
            loginAttempts.count += 1
            // Matches the mock server's own real `_handle_login` response
            // for a bad credential (Fixtures/mock_server.py).
            return .init(statusCode: 400, body: Data(#"{"detail": "Wrong username or password."}"#.utf8))
        }

        let authStore = makeAuthStore()
        await authStore.loginWithPassword(serverURLText: serverURL.absoluteString, username: "admin", password: "wrong")

        #expect(authStore.errorMessage != nil)
        // Exactly one attempt: a non-.network failure must never retry, and
        // must never pay the retry delay either.
        #expect(loginAttempts.count == 1)
    }

    @Test("loginWithPassword: surfaces the error as usual when the retry also fails")
    func retryFailureSurfacesTheError() async throws {
        let serverURL = makeServerURL()
        let loginAttempts = RetryAttemptBox()

        MockURLProtocol.handler = { request in
            guard request.url?.path == "/api/user/login" else {
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
            loginAttempts.count += 1
            return .init(statusCode: 0, error: URLError(.notConnectedToInternet))
        }

        let authStore = makeAuthStore()
        await authStore.loginWithPassword(serverURLText: serverURL.absoluteString, username: "admin", password: "secret")

        #expect(authStore.errorMessage != nil)
        #expect(loginAttempts.count == 2)
        // `loginWithPassword`'s failure path only ever sets `errorMessage`.
        if case .loggedIn = authStore.state {
            Issue.record("Expected login to have failed, but reached .loggedIn")
        }
    }

    @Test("loginWithToken: a transient network failure on the first attempt is retried once and succeeds silently")
    func tokenLoginRetriesOnceThenSucceeds() async throws {
        let serverURL = makeServerURL()
        let pingAttempts = RetryAttemptBox()

        MockURLProtocol.handler = { [self] request in
            if request.url?.path == "/api/ping" {
                pingAttempts.count += 1
                if pingAttempts.count == 1 {
                    return .init(statusCode: 0, error: URLError(.notConnectedToInternet))
                }
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("ping.json"))
            }
            if let ancillary = handleAncillaryLoginPaths(request) { return ancillary }
            Issue.record("Unexpected path \(request.url?.path ?? "nil")")
            return .init(statusCode: 500)
        }

        let authStore = makeAuthStore()
        await authStore.loginWithToken(serverURLText: serverURL.absoluteString, token: "sometoken")

        #expect(authStore.errorMessage == nil)
        #expect(pingAttempts.count == 2)
        guard case .loggedIn = authStore.state else {
            Issue.record("Expected .loggedIn, got \(authStore.state)")
            return
        }
    }
}

}
