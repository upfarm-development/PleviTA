
import Foundation
import Testing
@testable import PleviCore

@Suite("SSOCookieBridge")
struct SSOCookieBridgeTests {
    private func makeCookie(domain: String, name: String, value: String = "v") -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value
        ])!
    }

    /// A storage instance of its own, so nothing here can bleed into
    /// `.shared` (or another test) the way a real adopt-into-shared would.
    private func makeStorage() -> HTTPCookieStorage {
        HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "test-\(UUID().uuidString.prefix(8))")
    }

    @Test("adopts a cookie whose domain is exactly the server host")
    func adoptsExactHostCookie() {
        let storage = makeStorage()
        let serverURL = URL(string: "https://ta.example.com")!
        let cookie = makeCookie(domain: "ta.example.com", name: "proxy_session")

        let adopted = SSOCookieBridge.adopt([cookie], for: serverURL, into: storage)

        #expect(adopted.map(\.name) == ["proxy_session"])
        #expect(storage.cookies(for: serverURL)?.map(\.name) == ["proxy_session"])
    }

    @Test("adopts a leading-dot parent-domain cookie covering the server host")
    func adoptsParentDomainCookie() {
        let storage = makeStorage()
        let serverURL = URL(string: "https://ta.example.com")!
        // The common real shape: the proxy/IdP sets one cookie for the whole
        // apex domain so it covers every service behind it.
        let cookie = makeCookie(domain: ".example.com", name: "sso_session")

        let adopted = SSOCookieBridge.adopt([cookie], for: serverURL, into: storage)

        #expect(adopted.map(\.name) == ["sso_session"])
    }

    @Test("leaves an unrelated identity-provider cookie behind")
    func ignoresUnrelatedHostCookie() {
        let storage = makeStorage()
        let serverURL = URL(string: "https://ta.example.com")!
        // Landing on the IdP's own login page sets cookies the app has no
        // business copying into its own jar.
        let idpCookie = makeCookie(domain: "login.identityprovider.net", name: "idp_session")

        let adopted = SSOCookieBridge.adopt([idpCookie], for: serverURL, into: storage)

        #expect(adopted.isEmpty)
        #expect(storage.cookies(for: serverURL)?.isEmpty != false)
    }

    @Test("a lookalike domain is not treated as a parent domain")
    func rejectsLookalikeDomain() {
        let storage = makeStorage()
        let serverURL = URL(string: "https://notexample.com")!
        // Suffix matching without requiring the dot separator would wrongly
        // match ".example.com" against "notexample.com".
        let cookie = makeCookie(domain: ".example.com", name: "sso_session")

        #expect(SSOCookieBridge.adopt([cookie], for: serverURL, into: storage).isEmpty)
    }

    @Test("host matching is case-insensitive")
    func matchesHostCaseInsensitively() {
        let storage = makeStorage()
        let serverURL = URL(string: "https://TA.Example.com")!
        let cookie = makeCookie(domain: "ta.example.COM", name: "proxy_session")

        #expect(SSOCookieBridge.adopt([cookie], for: serverURL, into: storage).count == 1)
    }

    @Test("a URL with no host adopts nothing rather than crashing")
    func handlesHostlessURL() {
        let storage = makeStorage()
        let cookie = makeCookie(domain: "ta.example.com", name: "proxy_session")

        #expect(SSOCookieBridge.adopt([cookie], for: URL(string: "file:///tmp")!, into: storage).isEmpty)
    }
}
