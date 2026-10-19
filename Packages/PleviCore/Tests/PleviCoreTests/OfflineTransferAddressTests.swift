import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineTransferAddress")
struct OfflineTransferAddressTests {
    private let login = URL(string: "https://ta.example.com")!
    private let resolved = URL(string: "http://192.168.1.20:8000")!

    @Test("rebuilds for the recorded address when the same login is still signed in")
    func sameLoginRebuilds() {
        let recorded = OfflineTransferAddress(loginURL: login, serverURL: resolved)
        #expect(OfflineTransferAddress.addressForRebuiltClient(recorded: recorded, currentLoginURL: login, hasCredential: true) == resolved)
    }

    @Test("builds nothing once signed out — there is no credential to use")
    func signedOutBuildsNothing() {
        let recorded = OfflineTransferAddress(loginURL: login, serverURL: resolved)
        #expect(OfflineTransferAddress.addressForRebuiltClient(recorded: recorded, currentLoginURL: login, hasCredential: false) == nil)
        #expect(OfflineTransferAddress.addressForRebuiltClient(recorded: recorded, currentLoginURL: nil, hasCredential: true) == nil)
    }

    @Test("never pairs one server's address with another server's credential")
    func differentLoginBuildsNothing() {
        // Recorded under server A; the Keychain now holds server B's login and token. A client
        // for A's address would read B's token at request time and send it to A.
        let recorded = OfflineTransferAddress(loginURL: login, serverURL: resolved)
        let otherServer = URL(string: "https://other.example.org")!
        #expect(OfflineTransferAddress.addressForRebuiltClient(recorded: recorded, currentLoginURL: otherServer, hasCredential: true) == nil)
    }

    @Test("builds nothing when nothing was ever recorded")
    func nothingRecorded() {
        #expect(OfflineTransferAddress.addressForRebuiltClient(recorded: nil, currentLoginURL: login, hasCredential: true) == nil)
    }

    @Test("survives a round trip through UserDefaults, and clearing removes it")
    func persistence() throws {
        let suite = "OfflineTransferAddressTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OfflineTransferAddress.load(from: defaults) == nil)
        let address = OfflineTransferAddress(loginURL: login, serverURL: resolved)
        OfflineTransferAddress.save(address, to: defaults)
        #expect(OfflineTransferAddress.load(from: defaults) == address)
        OfflineTransferAddress.save(nil, to: defaults)
        #expect(OfflineTransferAddress.load(from: defaults) == nil)
    }

    @MainActor
    @Test("the saved cellular setting can be read without constructing AppSettings")
    func persistedCellularSetting() throws {
        let suite = "PersistedCellular-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppSettings.persistedAllowCellularDownloads(in: defaults) == false, "unset means off")
        let settings = AppSettings(defaults: defaults)
        settings.allowCellularDownloads = true
        #expect(AppSettings.persistedAllowCellularDownloads(in: defaults) == true)
    }
}
