
import Foundation
import Testing
@testable import PleviCore

@Suite("ServerAddressClassifier")
struct ServerAddressClassifierTests {
    private func classify(_ string: String) -> ServerAddressKind {
        ServerAddressClassifier.classify(URL(string: string)!)
    }

    @Test("RFC 1918 ranges are local, whatever the scheme or port")
    func privateRangesAreLocal() {
        #expect(classify("http://192.168.1.50:8000") == .local)
        #expect(classify("http://10.0.0.5:8000") == .local)
        #expect(classify("http://172.16.4.4:8000") == .local)
        #expect(classify("http://172.31.255.255") == .local)
        // The rule that is easy to get wrong: a LAN server with a certificate is still a LAN server.
        #expect(classify("https://192.168.1.50:8443") == .local)
    }

    @Test("172.x outside 16-31 is public, not private")
    func adjacentTo172PrivateRangeIsRemote() {
        // 172.16.0.0/12 is 172.16 through 172.31 — the neighbours either
        // side are ordinary public addresses.
        #expect(classify("http://172.15.0.1") == .remote)
        #expect(classify("http://172.32.0.1") == .remote)
    }

    @Test("loopback, link-local and .local hostnames are local")
    func loopbackAndBonjourAreLocal() {
        #expect(classify("http://127.0.0.1:8081") == .local)
        #expect(classify("http://localhost:8081") == .local)
        #expect(classify("http://169.254.3.4") == .local)
        #expect(classify("http://tubearchivist.local:8000") == .local)
        #expect(classify("https://NAS.LOCAL") == .local)
    }

    @Test("public hostnames and public IPs are remote")
    func publicAddressesAreRemote() {
        #expect(classify("https://ta.example.com") == .remote)
        #expect(classify("https://ta.example.com:8443/tubearchivist") == .remote)
        #expect(classify("http://example.com") == .remote)
        #expect(classify("https://93.184.216.34") == .remote)
    }

    @Test("a bare single-label host is left alone")
    func singleLabelHostIsIndeterminate() {
        // Probably a LAN machine, but it could be a search-domain shorthand
        // for a public name — not enough to write a setting on.
        #expect(classify("http://nas:8000") == .indeterminate)
        #expect(classify("http://tubearchivist") == .indeterminate)
    }

    @Test("IPv6 link-local and unique-local are local, routable is remote")
    func ipv6RangesAreClassified() {
        #expect(classify("http://[::1]:8000") == .local)
        #expect(classify("http://[fe80::1]:8000") == .local)
        #expect(classify("http://[fd12:3456::1]:8000") == .local)
        #expect(classify("http://[2606:4700::1111]") == .remote)
    }

    @Test("a malformed dotted quad is not mistaken for an IP")
    func malformedQuadIsNotAnIP() {
        // Four numeric labels where one is out of range is not an IPv4
        // address; it falls through to the dotted-name rule.
        #expect(ServerAddressClassifier.ipv4Octets("192.168.1.999") == nil)
        #expect(ServerAddressClassifier.ipv4Octets("192.168.1") == nil)
        #expect(ServerAddressClassifier.ipv4Octets("192.168.1.1.1") == nil)
        #expect(ServerAddressClassifier.ipv4Octets("192.168.one.1") == nil)
    }
}

extension MockedNetworkTests {

/// The store-level half: signing in fills the matching slot, and never
/// overwrites one the user set by hand.
@MainActor
@Suite("AuthStore connection-address adoption", .serialized)
struct AuthStoreAddressAdoptionTests {
    private nonisolated func makeCredentialStore() -> InMemoryCredentialStore {
        let store = InMemoryCredentialStore()
        store.setToken("sometoken")
        return store
    }

    /// Same ancillary endpoints `AuthStoreLoginRetryTests` stubs, from the
    /// same fixtures — a token login pings, then best-effort reads
    /// /user/me and /user/account before reaching `.loggedIn`.
    private nonisolated func stubLoginEndpoints(_ request: URLRequest) -> MockURLProtocol.StubResponse {
        switch request.url?.path {
        case "/api/ping":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("ping.json"))
        case "/api/user/me":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        case "/api/user/account":
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: try! Fixture.data("account.json"))
        default:
            return .init(statusCode: 404, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }
    }

    @Test("signing in with a LAN address fills the local slot")
    func lanLoginFillsLocalSlot() async throws {
        let credentialStore = makeCredentialStore()
        let appSettings = AppSettings()
        let authStore = AuthStore(
            appSettings: appSettings,
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        await authStore.loginWithToken(serverURLText: "http://192.168.1.50:8000", token: "sometoken")

        #expect(credentialStore.localServerURL()?.absoluteString == "http://192.168.1.50:8000")
        #expect(credentialStore.remoteServerURL() == nil)
    }

    @Test("signing in with a public address fills the remote slot")
    func publicLoginFillsRemoteSlot() async throws {
        let credentialStore = makeCredentialStore()
        let authStore = AuthStore(
            appSettings: AppSettings(),
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        await authStore.loginWithToken(serverURLText: "https://ta.example.com", token: "sometoken")

        #expect(credentialStore.remoteServerURL()?.absoluteString == "https://ta.example.com")
        #expect(credentialStore.localServerURL() == nil)
    }

    @Test("signing back into the same server keeps addresses set by hand")
    func sameServerKeepsAddresses() async throws {
        let credentialStore = makeCredentialStore()
        // The user has already said something deliberate about their network.
        credentialStore.setLocalServerURL(URL(string: "http://192.168.1.50:8000")!)
        credentialStore.setRemoteServerURL(URL(string: "https://vpn.example.com")!)
        let authStore = AuthStore(
            appSettings: AppSettings(),
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        // Either of the server's own addresses is "the same server".
        await authStore.loginWithToken(serverURLText: "https://vpn.example.com", token: "sometoken")

        #expect(credentialStore.localServerURL()?.absoluteString == "http://192.168.1.50:8000")
        #expect(credentialStore.remoteServerURL()?.absoluteString == "https://vpn.example.com")
    }

    @Test("signing into a different server replaces the previous server's addresses")
    func differentServerReplacesAddresses() async throws {
        let credentialStore = makeCredentialStore()
        credentialStore.setLocalServerURL(URL(string: "http://192.168.1.50:8000")!)
        credentialStore.setRemoteServerURL(URL(string: "https://vpn.example.com")!)
        let authStore = AuthStore(
            appSettings: AppSettings(),
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        await authStore.loginWithToken(serverURLText: "https://ta.example.com", token: "sometoken")

        #expect(credentialStore.remoteServerURL()?.absoluteString == "https://ta.example.com")
        #expect(credentialStore.localServerURL() == nil)
    }

    @Test("restoring the stored session never discards addresses")
    func restoreKeepsAddresses() async throws {
        let credentialStore = makeCredentialStore()
        // Signed in on the LAN address, then the local address was edited to another one:
        // neither stored address matches the login URL any more, and that must survive a relaunch.
        credentialStore.setServerURL(URL(string: "http://192.168.1.50:8000")!)
        credentialStore.setLocalServerURL(URL(string: "http://192.168.1.60:8000")!)
        credentialStore.setRemoteServerURL(URL(string: "https://vpn.example.com")!)
        let authStore = AuthStore(
            appSettings: AppSettings(),
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        await authStore.restoreSessionIfPossible()

        #expect(credentialStore.localServerURL()?.absoluteString == "http://192.168.1.60:8000")
        #expect(credentialStore.remoteServerURL()?.absoluteString == "https://vpn.example.com")
    }

    @Test("an address that is neither leaves both slots alone")
    func indeterminateAddressFillsNothing() async throws {
        let credentialStore = makeCredentialStore()
        let authStore = AuthStore(
            appSettings: AppSettings(),
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { self.stubLoginEndpoints($0) }

        await authStore.loginWithToken(serverURLText: "http://nas:8000", token: "sometoken")

        #expect(credentialStore.localServerURL() == nil)
        #expect(credentialStore.remoteServerURL() == nil)
    }
}

}
