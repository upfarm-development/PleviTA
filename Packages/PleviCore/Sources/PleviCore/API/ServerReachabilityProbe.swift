
import Foundation

/// `GET {url}/api/ping/` on a short-lived session with a ~1.5s timeout, counting only a response that actually decodes as a pong.
public struct ServerReachabilityProbe: Sendable {
    private let credentialStore: CredentialStoring
    private let timeout: TimeInterval

    public init(credentialStore: CredentialStoring, timeout: TimeInterval = 1.5) {
        self.credentialStore = credentialStore
        self.timeout = timeout
    }

    /// Matches the `(URL) async -> Bool` shape `ServerAddressResolver`
    /// expects, so a `ServerReachabilityProbe` instance can be passed
    /// directly as `probe:` via `probe.callAsFunction`.
    public func callAsFunction(_ url: URL) async -> Bool {
        guard let scheme = url.scheme, let host = url.host else { return false }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        let existingPath = url.path
        let basePath = (existingPath.isEmpty || existingPath == "/") ? "" : existingPath
        components.path = basePath + "/api/ping/"
        guard let pingURL = components.url else { return false }

        var request = URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = credentialStore.token() {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        // The sessionid cookie (session-auth mode) is attached automatically
        // by URLSession from the shared HTTPCookieStorage below, same as
        // TAClient's own GET requests.

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let ping = try JSONDecoder().decode(PingResponse.self, from: data)
            return ping.isPong
        } catch {
            return false
        }
    }
}
