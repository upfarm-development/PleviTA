// `InMemoryCredentialStore` covers the `CredentialStoring` contract (used the same way by `TAClient`/`AuthStore`).

import Foundation
import Testing
@testable import PleviCore

@Suite("CredentialStore")
struct CredentialStoreTests {
    @Test("InMemoryCredentialStore round-trips every field")
    func inMemoryRoundTrip() {
        let store = InMemoryCredentialStore()
        #expect(store.serverURL() == nil)
        #expect(store.token() == nil)
        #expect(store.sessionCredential() == nil)
        #expect(store.displayUsername() == nil)

        let url = URL(string: "http://127.0.0.1:8081")!
        store.setServerURL(url)
        store.setToken("tok")
        store.setSessionCredential(SessionCredential(csrfToken: "csrf", username: "alice"))
        store.setDisplayUsername("alice")

        #expect(store.serverURL() == url)
        #expect(store.token() == "tok")
        #expect(store.sessionCredential()?.csrfToken == "csrf")
        #expect(store.displayUsername() == "alice")

        store.clearAll()
        #expect(store.serverURL() == nil)
        #expect(store.token() == nil)
        #expect(store.sessionCredential() == nil)
        #expect(store.displayUsername() == nil)
    }

    @Test("connectionMode defaults to .automatic when never set")
    func connectionModeDefaultsToAutomatic() {
        #expect(InMemoryCredentialStore().connectionMode() == .automatic)
    }

    @Test("localServerURL/remoteServerURL/connectionMode round-trip independently of serverURL")
    func inMemoryConnectionSettingsRoundTrip() {
        let store = InMemoryCredentialStore()
        #expect(store.localServerURL() == nil)
        #expect(store.remoteServerURL() == nil)

        let local = URL(string: "http://127.0.0.1:8081")!
        let remote = URL(string: "https://remote.example.com")!
        store.setLocalServerURL(local)
        store.setRemoteServerURL(remote)
        store.setConnectionMode(.alwaysLocal)

        #expect(store.localServerURL() == local)
        #expect(store.remoteServerURL() == remote)
        #expect(store.connectionMode() == .alwaysLocal)

        store.setLocalServerURL(nil)
        #expect(store.localServerURL() == nil)
        // Clearing local didn't disturb remote/mode.
        #expect(store.remoteServerURL() == remote)
        #expect(store.connectionMode() == .alwaysLocal)
    }

    @Test("clearAll() leaves localServerURL/remoteServerURL/connectionMode untouched")
    func clearAllDoesNotTouchConnectionSettings() {
        let store = InMemoryCredentialStore()
        let local = URL(string: "http://127.0.0.1:8081")!
        let remote = URL(string: "https://remote.example.com")!
        store.setLocalServerURL(local)
        store.setRemoteServerURL(remote)
        store.setConnectionMode(.alwaysRemote)
        store.setServerURL(URL(string: "http://127.0.0.1:9000")!)
        store.setToken("tok")

        store.clearAll()

        // Sign-out-critical fields are gone…
        #expect(store.serverURL() == nil)
        #expect(store.token() == nil)
        // …but the network-topology settings (not a login session) survive,
        // per `CredentialStoring.clearAll()`'s own doc comment.
        #expect(store.localServerURL() == local)
        #expect(store.remoteServerURL() == remote)
        #expect(store.connectionMode() == .alwaysRemote)
    }

    @Test("KeychainStore set/get/delete round-trip")
    func keychainStoreRoundTrip() {
        let keychain = KeychainStore(service: "com.plevi.ta.tests.\(UUID().uuidString)")
        let key = "sampleKey"
        defer { keychain.delete(forKey: key) }

        #expect(keychain.get(forKey: key) == nil)
        keychain.set("hello", forKey: key)
        #expect(keychain.get(forKey: key) == "hello")
        keychain.set("updated", forKey: key)
        #expect(keychain.get(forKey: key) == "updated")
        keychain.delete(forKey: key)
        #expect(keychain.get(forKey: key) == nil)
    }
}
