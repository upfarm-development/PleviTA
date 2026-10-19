
import Foundation

public struct APIGateProbe: Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    /// Deliberately sends no credential.
    public func callAsFunction(_ url: URL) async -> Bool {
        guard let pingURL = Self.pingURL(for: url) else { return false }

        var request = URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        // The whole point: the cookie the web view just handed to
        // `HTTPCookieStorage.shared` has to ride along, or this asks the
        // question as though the SSO login never happened.
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (data, _) = try await session.data(for: request)
            return Self.isJSONObject(data)
        } catch {
            return false
        }
    }

    static func pingURL(for url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        let existingPath = url.path
        let basePath = (existingPath.isEmpty || existingPath == "/") ? "" : existingPath
        components.path = basePath + "/api/ping/"
        return components.url
    }

    static func isJSONObject(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return false }
        return parsed is [String: Any]
    }
}
