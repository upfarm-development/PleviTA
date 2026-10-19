
import Foundation
import os

public actor TAClient {
    public struct LoginOutcome: Sendable, Equatable {
        public enum Mode: Sendable, Equatable { case token, session }
        public var mode: Mode
        public var token: String?
    }

    /// `private(set)` rather than `private`: callers that need to scope per-server state by it
    /// (`PlaybackHistory`) have to be able to read which server this client is talking to.
    public private(set) var serverURL: URL
    private let credentialStore: CredentialStoring
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.plevi.ta", category: "TAClient")

    public init(serverURL: URL, credentialStore: CredentialStoring, urlSession: URLSession? = nil) {
        self.serverURL = serverURL
        self.credentialStore = credentialStore
        self.decoder = JSONDecoder()
        if let urlSession {
            self.session = urlSession
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024, directory: nil)
            configuration.httpCookieStorage = Self.defaultCookieStorage
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            self.session = URLSession(configuration: configuration)
        }
    }

    /// The cookie jar the default session uses.
    static var defaultCookieStorage: HTTPCookieStorage {
        #if os(tvOS)
        let shared = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: KeychainCredentialStore.appGroupIdentifier
        )
        migrateCookiesToAppGroupOnce(into: shared)
        return shared
        #else
        return .shared
        #endif
    }

    #if os(tvOS)
    private static let cookieMigrationKey = "taclient.didMigrateCookiesToAppGroup"

    /// Hands the existing per-process cookies over to the shared jar, exactly once.
    private static func migrateCookiesToAppGroupOnce(into storage: HTTPCookieStorage) {
        // Only the app migrates. The extension's own `.shared` jar is empty by definition, and
        // it can run first (Top Shelf builds its content when the user focuses the app icon), so
        // letting it claim the flag would mean the app's real cookies were never handed over.
        guard Bundle.main.bundleURL.pathExtension != "appex",
              let defaults = UserDefaults(suiteName: KeychainCredentialStore.appGroupIdentifier),
              !defaults.bool(forKey: cookieMigrationKey)
        else { return }
        defaults.set(true, forKey: cookieMigrationKey)
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            storage.setCookie(cookie)
        }
    }
    #endif

    public func updateServerURL(_ url: URL) {
        serverURL = url
    }

    public func currentServerURL() -> URL {
        serverURL
    }

    // MARK: - Request machinery

    private struct ServerErrorBody: Decodable {
        var detail: String?
    }

    private func buildRequest(_ endpoint: Endpoint, explicitToken: String? = nil) throws -> URLRequest {
        guard let scheme = serverURL.scheme, let host = serverURL.host else {
            throw TAError.invalidServerURL
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = serverURL.port
        let existingPath = serverURL.path
        let basePath = (existingPath.isEmpty || existingPath == "/") ? "" : existingPath
        components.path = basePath + "/api/" + endpoint.path
        components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query

        guard let url = components.url else { throw TAError.invalidServerURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if endpoint.requiresAuth {
            attachAuthHeader(to: &request, method: endpoint.method, explicitToken: explicitToken)
        }
        return request
    }

    private func attachAuthHeader(to request: inout URLRequest, method: Endpoint.Method, explicitToken: String? = nil) {
        if let explicitToken {
            request.setValue("Token \(explicitToken)", forHTTPHeaderField: "Authorization")
        } else if let token = credentialStore.token() {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        } else if let sessionCredential = credentialStore.sessionCredential() {
            if method != .get, !sessionCredential.csrfToken.isEmpty {
                request.setValue(sessionCredential.csrfToken, forHTTPHeaderField: "X-CSRFToken")
                request.setValue(serverURL.absoluteString, forHTTPHeaderField: "Referer")
            }
            // The sessionid cookie itself is attached automatically by
            // URLSession from HTTPCookieStorage.shared.
        }
    }

    private func perform(_ endpoint: Endpoint, explicitToken: String? = nil) async throws -> Data {
        let request = try buildRequest(endpoint, explicitToken: explicitToken)
        logger.debug("\(endpoint.method.rawValue, privacy: .public) /api/\(endpoint.path, privacy: .public)")

        let data: Data
        let response: URLResponse
        let collector = RequestMetricsCollector()
        let started = ProcessInfo.processInfo.systemUptime
        let label = "\(endpoint.method.rawValue) \(PlaybackLog.redacted(request.url))"
        do {
            (data, response) = try await session.data(for: request, delegate: collector)
        } catch {
            PlaybackLog.shared.log("api", String(format: "%@ FAILED after %.3fs: %@ %@", label,
                                                 ProcessInfo.processInfo.systemUptime - started,
                                                 (error as NSError).domain + "#" + String((error as NSError).code),
                                                 error.localizedDescription))
            throw TAError.network(error.localizedDescription)
        }
        PlaybackLog.shared.log("api", String(format: "%@ -> %d %dB in %.3fs ", label,
                                             (response as? HTTPURLResponse)?.statusCode ?? -1, data.count,
                                             ProcessInfo.processInfo.systemUptime - started) + collector.summary)

        guard let http = response as? HTTPURLResponse else {
            throw TAError.network("No HTTP response")
        }
        if Self.looksLikeWebPage(data: data, response: http), Self.isGateStatus(http.statusCode) {
            throw TAError.interceptedByProxy
        }
        try validate(http, data: data)
        return data
    }

    /// No `/api/` endpoint ever answers with HTML, so HTML here means something other than Tube Archivist answered.
    nonisolated static func looksLikeWebPage(data: Data, response: HTTPURLResponse) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            return true
        }
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D) }) else {
            return false
        }
        return first == UInt8(ascii: "<")
    }

    nonisolated static func isGateStatus(_ status: Int) -> Bool {
        (200..<400).contains(status) || status == 401 || status == 403
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw TAError.unauthorized
        case 404:
            throw TAError.notFound
        default:
            let message = (try? decoder.decode(ServerErrorBody.self, from: data))?.detail
            throw TAError.server(status: response.statusCode, message: message)
        }
    }

    func request<T: Decodable & Sendable>(_ endpoint: Endpoint, explicitToken: String? = nil) async throws -> T {
        let data = try await perform(endpoint, explicitToken: explicitToken)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TAError.decoding("\(error)")
        }
    }

    func requestNoContent(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: - Connection and auth

    public func ping() async throws -> PingResponse {
        try await request(.ping)
    }

    /// Validates a pasted API token against `/api/ping/` without mutating
    /// any stored credential — the caller persists it only on success.
    public func validateToken(_ token: String) async throws -> PingResponse {
        let ping: PingResponse = try await request(.ping, explicitToken: token)
        guard ping.isPong else {
            throw TAError.server(status: 200, message: "Server did not respond to ping as expected.")
        }
        return ping
    }

    public func account() async throws -> Account {
        try await request(.account)
    }

    public func fetchUserConfig() async throws -> UserConfig {
        try await request(.userConfig)
    }

    @discardableResult
    public func updateUserConfig(_ config: UserConfig) async throws -> UserConfig {
        try await request(.updateUserConfig(config))
    }

    public func login(username: String, password: String, rememberMe: Bool = true) async throws -> LoginOutcome {
        _ = try await perform(.login(username: username, password: password, rememberMe: rememberMe))

        let csrfToken = readCSRFTokenCookie() ?? ""
        // Stash the session credential immediately: even the token-fetch
        // call right below needs *some* credential attached, and the
        // sessionid cookie is already set from the login response.
        credentialStore.setToken(nil)
        credentialStore.setSessionCredential(SessionCredential(csrfToken: csrfToken, username: username))

        do {
            let tokenResponse: TokenResponse = try await request(.appToken)
            guard let token = tokenResponse.token, !token.isEmpty else {
                return LoginOutcome(mode: .session, token: nil)
            }
            credentialStore.setToken(token)
            credentialStore.setSessionCredential(nil)
            clearSessionCookies()
            return LoginOutcome(mode: .token, token: token)
        } catch TAError.unauthorized {
            // Non-admin user: keep the session credential set above.
            return LoginOutcome(mode: .session, token: nil)
        }
    }

    public func logout() async {
        _ = try? await requestNoContent(.logout)
        clearSessionCookies()
    }

    // MARK: - Media

    /// Resolves a server-root-relative path (`vid_thumb_url`, `media_url`, `channel_thumb_url`, …) against the configured server origin.
    public func mediaURL(forPath path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil, url.host != nil {
            return url
        }
        guard let scheme = serverURL.scheme, let host = serverURL.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = serverURL.port
        let existingBase = serverURL.path
        let basePath = (existingBase.isEmpty || existingBase == "/") ? "" : existingBase
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + normalizedPath
        return components.url
    }

    /// Headers a non-`URLSession` HTTP client needs to authenticate against `/media/<...>` the same way `fetchMedia` does for `/cache/` thumbnails.
    public func authorizationHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let token = credentialStore.token() {
            headers["Authorization"] = "Token \(token)"
        }
        if let cookies = session.configuration.httpCookieStorage?.cookies(for: serverURL),
           !cookies.isEmpty {
            headers["Cookie"] = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        return headers
    }

    /// Fetches raw bytes (a thumbnail image, a media file range, …) from a server-root-relative path with the same credential attached to `/api/` requests.
    public func fetchMedia(path: String) async throws -> Data {
        guard let url = mediaURL(forPath: path) else { throw TAError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = Endpoint.Method.get.rawValue
        attachAuthHeader(to: &request, method: .get)
        logger.debug("GET \(url.path, privacy: .public) (media)")

        let data: Data
        let response: URLResponse
        let collector = RequestMetricsCollector()
        let started = ProcessInfo.processInfo.systemUptime
        let label = "GET(media) \(PlaybackLog.redacted(request.url))"
        do {
            (data, response) = try await session.data(for: request, delegate: collector)
        } catch {
            PlaybackLog.shared.log("api", String(format: "%@ FAILED after %.3fs: %@ %@", label,
                                                 ProcessInfo.processInfo.systemUptime - started,
                                                 (error as NSError).domain + "#" + String((error as NSError).code),
                                                 error.localizedDescription))
            throw TAError.network(error.localizedDescription)
        }
        PlaybackLog.shared.log("api", String(format: "%@ -> %d %dB in %.3fs ", label,
                                             (response as? HTTPURLResponse)?.statusCode ?? -1, data.count,
                                             ProcessInfo.processInfo.systemUptime - started) + collector.summary)
        guard let http = response as? HTTPURLResponse else {
            throw TAError.network("No HTTP response")
        }
        // `perform` (above) already runs this check for every `/api/` call.
        if Self.looksLikeWebPage(data: data, response: http), Self.isGateStatus(http.statusCode) {
            throw TAError.interceptedByProxy
        }
        try validate(http, data: data)
        return data
    }

    private func readCSRFTokenCookie() -> String? {
        session.configuration.httpCookieStorage?
            .cookies(for: serverURL)?
            .first(where: { $0.name == "csrftoken" })?
            .value
    }

    /// Tube Archivist's own (Django) session cookies — the only ones this client is entitled to
    /// throw away.
    private static let djangoSessionCookieNames: Set<String> = ["sessionid", "csrftoken"]

    /// Drops Tube Archivist's own session cookies, and only those.
    private func clearSessionCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies(for: serverURL) ?? []
        where Self.djangoSessionCookieNames.contains(cookie.name.lowercased()) {
            storage.deleteCookie(cookie)
        }
    }
}
