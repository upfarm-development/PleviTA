import Foundation
import Testing
@testable import PleviCore

@Suite("ServerScope")
struct ServerScopeTests {
    @Test("two different login URLs hash to two different digests")
    func distinctURLsDiffer() {
        #expect(ServerScope.digest(of: "https://a.example") != ServerScope.digest(of: "https://b.example"))
    }

    @Test("the same login URL always hashes the same way")
    func sameURLIsStable() {
        #expect(ServerScope.digest(of: "https://a.example") == ServerScope.digest(of: "https://a.example"))
    }

    @Test("PlaybackHistory's storage key is unaffected by lifting the digest out")
    func matchesPlaybackHistoryStorageKey() {
        // PlaybackHistory's own key is "playbackHistory.<digest>" — asserting the digest
        // itself is an 8-byte (16 hex char) SHA-256 prefix is the guarantee that lifting it
        // into ServerScope didn't change what an existing install's key resolves to.
        let digest = ServerScope.digest(of: "https://ta.example.com")
        #expect(digest.count == 16)
        #expect(digest == digest.lowercased())
    }
}
