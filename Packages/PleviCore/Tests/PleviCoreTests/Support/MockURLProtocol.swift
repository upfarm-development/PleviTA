
import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse {
        var statusCode: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
        var error: URLError?
    }

    /// Not actor-isolated: tests run serially within a file and always set
    /// this before making requests, so a plain static var is sufficient here.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> StubResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // Likewise, the built-in HTTP protocol attaches a `Cookie` header
        // from matching stored cookies before a request goes out; replicate
        // that here so `TAClient`'s session-mode requests are testable.
        var effectiveRequest = request
        if effectiveRequest.value(forHTTPHeaderField: "Cookie") == nil,
           let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                effectiveRequest.setValue(value, forHTTPHeaderField: field)
            }
        }

        let stub = handler(effectiveRequest)
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        // Apple's built-in HTTP protocol applies `Set-Cookie` response headers to the session's cookie storage internally.
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: stub.headers, for: url)
        if !cookies.isEmpty {
            HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: nil)
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }
}
