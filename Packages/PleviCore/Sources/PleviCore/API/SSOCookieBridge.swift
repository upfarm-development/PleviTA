
import Foundation

public enum SSOCookieBridge {
    /// Copies the subset of `cookies` scoped to `serverURL`'s host into `storage`, leaving every other cookie behind.
    @discardableResult
    public static func adopt(
        _ cookies: [HTTPCookie],
        for serverURL: URL,
        into storage: HTTPCookieStorage = .shared
    ) -> [HTTPCookie] {
        guard let host = serverURL.host?.lowercased(), !host.isEmpty else { return [] }
        let matching = cookies.filter { domain(cookie: $0, matches: host) }
        for cookie in matching {
            storage.setCookie(cookie)
        }
        return matching
    }

    private static func domain(cookie: HTTPCookie, matches host: String) -> Bool {
        var domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            domain.removeFirst()
        }
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }
}
