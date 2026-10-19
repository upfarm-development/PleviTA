
import Foundation
import Testing
@testable import PleviCore

/// Umbrella suite for every test that drives the shared, process-global `MockURLProtocol.handler` (Support/MockURLProtocol.swift).
@Suite(.serialized)
enum MockedNetworkTests {}

extension MockedNetworkTests {

@Suite("TAClient", .serialized)
struct TAClientTests {
    /// A distinct host per test avoids cross-test cookie bleed through
    /// `HTTPCookieStorage.shared`.
    private func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private func makeClient(serverURL: URL, credentialStore: CredentialStoring) -> TAClient {
        TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    @Test("ping() decodes a successful response")
    func pingSuccess() async throws {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        MockURLProtocol.handler = { request in
            // `URL.path` strips a single trailing slash (long-standing Foundation behavior).
            #expect(request.url?.absoluteString.hasSuffix("/api/ping/") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Token sometoken")
            let body = try! Fixture.data("ping.json")
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        let ping = try await client.ping()
        #expect(ping.isPong)
    }

    // MARK: - authorizationHeaders

    @Test("a token-mode client behind an SSO gate sends BOTH the token and the gate cookie")
    func authorizationHeadersCarryTokenAndCookie() async {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        let cookie = HTTPCookie(properties: [
            .domain: serverURL.host!,
            .path: "/",
            .name: "gate_session",
            .value: "let-me-in",
        ])!
        // `MockURLProtocol.makeSession()` is configured with `HTTPCookieStorage.shared`, and
        // every test here uses a distinct host, so this reaches the client's own jar without
        // bleeding into another test — the same reason `makeServerURL` exists.
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }

        let headers = await client.authorizationHeaders()
        #expect(headers["Authorization"] == "Token sometoken")
        #expect(headers["Cookie"]?.contains("gate_session=let-me-in") == true)
    }

    @Test("with no cookies for the host, only the token is sent")
    func authorizationHeadersTokenOnlyWithoutCookies() async {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: makeServerURL(), credentialStore: credentialStore)

        let headers = await client.authorizationHeaders()
        #expect(headers["Authorization"] == "Token sometoken")
        #expect(headers["Cookie"] == nil)
    }

    @Test("with no credentials at all, nothing is sent")
    func authorizationHeadersEmptyWithoutCredentials() async {
        let client = makeClient(serverURL: makeServerURL(), credentialStore: InMemoryCredentialStore())
        let headers = await client.authorizationHeaders()
        #expect(headers.isEmpty)
    }

    @Test("401 maps to TAError.unauthorized")
    func unauthorizedMapsToTAError() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL, credentialStore: InMemoryCredentialStore())

        MockURLProtocol.handler = { _ in .init(statusCode: 401, body: Data("{}".utf8)) }

        await #expect(throws: TAError.unauthorized) {
            _ = try await client.ping()
        }
    }

    @Test("404 maps to TAError.notFound")
    func notFoundMapsToTAError() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL, credentialStore: InMemoryCredentialStore())

        MockURLProtocol.handler = { _ in .init(statusCode: 404, body: Data("{}".utf8)) }

        await #expect(throws: TAError.notFound) {
            _ = try await client.ping()
        }
    }

    @Test("login() as an admin: fetches and stores a token, drops the session")
    func loginAdminStoresToken() async throws {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/user/login":
                #expect(request.httpMethod == "POST")
                return .init(
                    statusCode: 204,
                    headers: [
                        "Set-Cookie": "sessionid=abc123; Path=/; HttpOnly, csrftoken=xyz789; Path=/"
                    ]
                )
            case "/api/appsettings/token":
                #expect(request.httpMethod == "GET")
                // No stored token yet — auth must ride on the session cookie.
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=abc123") == true)
                let body = try! Fixture.data("token.json")
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            default:
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
        }

        let outcome = try await client.login(username: "admin", password: "secret")
        #expect(outcome.mode == .token)
        #expect(outcome.token == "synthetic0fixture0token0000000000000000")
        #expect(credentialStore.token() == "synthetic0fixture0token0000000000000000")
        #expect(credentialStore.sessionCredential() == nil)
    }

    @Test("login() as a non-admin: keeps the session credential when the token endpoint 403s")
    func loginNonAdminKeepsSession() async throws {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/user/login":
                return .init(
                    statusCode: 204,
                    headers: ["Set-Cookie": "sessionid=sess456; Path=/; HttpOnly, csrftoken=csrf456; Path=/"]
                )
            case "/api/appsettings/token":
                return .init(statusCode: 403, body: Data("{\"detail\":\"Admin only.\"}".utf8))
            default:
                Issue.record("Unexpected path \(request.url?.path ?? "nil")")
                return .init(statusCode: 500)
            }
        }

        let outcome = try await client.login(username: "viewer", password: "secret")
        #expect(outcome.mode == .session)
        #expect(outcome.token == nil)
        #expect(credentialStore.token() == nil)
        #expect(credentialStore.sessionCredential()?.csrfToken == "csrf456")
        #expect(credentialStore.sessionCredential()?.username == "viewer")
    }

    @Test("validateToken() does not persist anything itself")
    func validateTokenIsSideEffectFree() async throws {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Token pasted-token")
            let body = try! Fixture.data("ping.json")
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        let ping = try await client.validateToken("pasted-token")
        #expect(ping.isPong)
        // The client itself never wrote anything; the caller (AuthStore) does.
        #expect(credentialStore.token() == nil)
    }

    @Test("logout() clears Tube Archivist's session cookies but not a proxy's")
    func logoutClearsCookies() async throws {
        let serverURL = makeServerURL()
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: serverURL, credentialStore: credentialStore)

        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/ping" {
                let body = try! Fixture.data("ping.json")
                return .init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json", "Set-Cookie": "sessionid=logout1; Path=/"],
                    body: body
                )
            }
            // /api/user/logout/, called by client.logout() itself.
            return .init(statusCode: 204)
        }
        _ = try await client.ping()
        #expect(HTTPCookieStorage.shared.cookies(for: serverURL)?.isEmpty == false)

        // An SSO reverse proxy's cookie, on the same host.
        let host = try #require(serverURL.host)
        let gateCookie = try #require(HTTPCookie(properties: [
            .domain: host,
            .path: "/",
            .name: "p_session_token",
            .value: "gate-abc123"
        ]))
        HTTPCookieStorage.shared.setCookie(gateCookie)

        await client.logout()
        let remaining = HTTPCookieStorage.shared.cookies(for: serverURL) ?? []
        #expect(!remaining.contains { $0.name == "sessionid" })
        #expect(remaining.contains { $0.name == "p_session_token" })

        HTTPCookieStorage.shared.deleteCookie(gateCookie)
    }

    // MARK: - HTML bodies that are not a proxy gate

    @Test("an HTML 404 is Not Found, not a proxy gate")
    func htmlNotFoundIsNotAProxyGate() async throws {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: makeServerURL(), credentialStore: credentialStore)

        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 404,
                headers: ["Content-Type": "text/html"],
                body: Data("<html><head><title>404 Not Found</title></head></html>".utf8)
            )
        }

        do {
            try await client.ignoreDownload(id: "abc")
            Issue.record("expected the 404 to throw")
        } catch let error as TAError {
            guard case .notFound = error else {
                Issue.record("expected .notFound, got \(error)")
                return
            }
        }
    }

    @Test("an HTML body on a status a gate answers with is still a gate")
    func htmlOnGateStatusIsStillAGate() async throws {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: makeServerURL(), credentialStore: credentialStore)

        // The case the check exists for, and which must keep working: a closed gate
        // serving its own login page under a perfectly ordinary 200.
        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/html"],
                body: Data("<!DOCTYPE html><html><body>Sign in</body></html>".utf8)
            )
        }

        do {
            try await client.ignoreDownload(id: "abc")
            Issue.record("expected the login page to throw")
        } catch let error as TAError {
            guard case .interceptedByProxy = error else {
                Issue.record("expected .interceptedByProxy, got \(error)")
                return
            }
        }
    }

    @Test("fetchMedia treats a gate's login page the same way perform() already does")
    func fetchMediaCatchesGateLoginPage() async throws {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: makeServerURL(), credentialStore: credentialStore)

        MockURLProtocol.handler = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/html"],
                body: Data("<!DOCTYPE html><html><body>Sign in</body></html>".utf8)
            )
        }

        do {
            _ = try await client.fetchMedia(path: "/cache/videos/abc/thumb.jpg")
            Issue.record("expected the login page to throw")
        } catch let error as TAError {
            guard case .interceptedByProxy = error else {
                Issue.record("expected .interceptedByProxy, got \(error)")
                return
            }
        }
    }

    @Test("fetchMedia still returns ordinary bytes untouched")
    func fetchMediaReturnsOrdinaryBytes() async throws {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = makeClient(serverURL: makeServerURL(), credentialStore: credentialStore)

        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0])
        MockURLProtocol.handler = { _ in
            .init(statusCode: 200, headers: ["Content-Type": "image/jpeg"], body: payload)
        }

        let data = try await client.fetchMedia(path: "/cache/videos/abc/thumb.jpg")
        #expect(data == payload)
    }
}

}
