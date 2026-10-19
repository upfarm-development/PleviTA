import Foundation
import Testing
@testable import PleviCore

extension MockedNetworkTests {

@MainActor
@Suite("OfflineMetadataSync", .serialized)
struct OfflineMetadataSyncTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private func makeLibrary() -> (OfflineLibrary, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineMetadataSyncTests-\(UUID().uuidString)")
        return (OfflineLibrary(root: root), root)
    }

    private nonisolated func makeVideo(id: String = "abc123") -> Video {
        Video(youtubeId: id, title: "A Video", mediaUrl: "/media/chan/\(id).mp4")
    }

    /// Saves and completes a video so it shows up as a `.complete` entry — the only state
    /// `OfflineMetadataSync.refresh` looks at.
    private func saveCompleteVideo(_ library: OfflineLibrary, id: String) async throws {
        _ = await library.beginSave(video: makeVideo(id: id))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data([0x01]).write(to: temp)
        await library.markComplete(videoId: id, from: temp)
    }

    private nonisolated static func videoJSON(id: String, title: String) -> Data {
        Data("""
        {"youtube_id": "\(id)", "title": "\(title)"}
        """.utf8)
    }

    @Test("a successful refresh overwrites the stored video and clears a stale orphan flag")
    func refreshUpdatesVideoAndClearsOrphan() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")
        await library.setOrphaned(videoId: "v1", isOrphaned: true)

        MockURLProtocol.handler = { _ in .init(statusCode: 200, body: Self.videoJSON(id: "v1", title: "Retitled after reindex")) }

        await OfflineMetadataSync.refresh(library: library, client: client)

        let entry = library.entry(for: "v1")
        #expect(entry?.video.title == "Retitled after reindex")
        #expect(entry?.record.isOrphaned == false)
    }

    @Test("a 404 flags the entry orphaned without touching its stored video")
    func refreshMarksOrphanedOn404() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")

        MockURLProtocol.handler = { _ in .init(statusCode: 404) }

        await OfflineMetadataSync.refresh(library: library, client: client)

        let entry = library.entry(for: "v1")
        #expect(entry?.record.isOrphaned == true)
        #expect(entry?.video.title == "A Video", "an orphaned video's stored copy is left exactly as it was")
    }

    @Test("a transient failure leaves the entry queued exactly as it was")
    func refreshLeavesEntryUnchangedOnTransientFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }

        await OfflineMetadataSync.refresh(library: library, client: client)

        let entry = library.entry(for: "v1")
        #expect(entry?.record.isOrphaned == false)
        #expect(entry?.video.title == "A Video")
    }

    @Test("only .complete entries are refreshed — a .downloading entry is never even queried")
    func refreshSkipsIncompleteEntries() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")
        _ = await library.beginSave(video: makeVideo(id: "v2")) // left .downloading

        let requestCount = CountBox(0)
        MockURLProtocol.handler = { _ in
            requestCount.value += 1
            return .init(statusCode: 200, body: Self.videoJSON(id: "v1", title: "A Video"))
        }

        await OfflineMetadataSync.refresh(library: library, client: client)
        #expect(requestCount.value == 1)
    }

    @Test("a transient failure on an already-orphaned entry leaves the orphan flag set, not cleared")
    func refreshLeavesOrphanFlagSetOnTransientFailure() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")
        await library.setOrphaned(videoId: "v1", isOrphaned: true)

        MockURLProtocol.handler = { _ in .init(statusCode: 500) }

        await OfflineMetadataSync.refresh(library: library, client: client)

        #expect(library.entry(for: "v1")?.record.isOrphaned == true, "only a successful fetch may clear a stale orphan flag")
    }

    @Test("each of several saved videos gets its own server response, never another video's")
    func refreshAppliesEachResponseToItsOwnVideo() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        try await saveCompleteVideo(library, id: "v1")
        try await saveCompleteVideo(library, id: "v2")

        MockURLProtocol.handler = { request in
            let isV1 = request.url?.absoluteString.contains("/video/v1/") == true
            return .init(statusCode: 200, body: Self.videoJSON(id: isV1 ? "v1" : "v2", title: isV1 ? "v1's own title" : "v2's own title"))
        }

        await OfflineMetadataSync.refresh(library: library, client: client)

        #expect(library.entry(for: "v1")?.video.title == "v1's own title")
        #expect(library.entry(for: "v2")?.video.title == "v2's own title")
    }

    @Test("one refresh pass over a mixed shelf updates, orphans, and leaves every other entry exactly as it was")
    func refreshHandlesAMixedShelfInOnePass() async throws {
        let client = makeClient(serverURL: makeServerURL())
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        // v1: complete, currently orphaned, refresh will find it again — should clear the flag.
        try await saveCompleteVideo(library, id: "v1")
        await library.setOrphaned(videoId: "v1", isOrphaned: true)
        // v2: complete, ordinary — should just get its metadata refreshed.
        try await saveCompleteVideo(library, id: "v2")
        // v3: left mid-download — must never be queried or touched.
        _ = await library.beginSave(video: makeVideo(id: "v3"))
        // v4: failed — must never be queried or touched either.
        _ = await library.beginSave(video: makeVideo(id: "v4"))
        await library.markFailed(videoId: "v4", reason: "network error")

        let requestedIds = LockedSet()
        MockURLProtocol.handler = { request in
            let id = request.url?.absoluteString.contains("/video/v1/") == true ? "v1" : "v2"
            requestedIds.insert(id)
            return .init(statusCode: 200, body: Self.videoJSON(id: id, title: "\(id) refreshed"))
        }

        await OfflineMetadataSync.refresh(library: library, client: client)

        #expect(requestedIds.values == Set(["v1", "v2"]), "only the two .complete entries are ever queried")

        #expect(library.entry(for: "v1")?.video.title == "v1 refreshed")
        #expect(library.entry(for: "v1")?.record.isOrphaned == false)

        #expect(library.entry(for: "v2")?.video.title == "v2 refreshed")
        #expect(library.entry(for: "v2")?.record.isOrphaned == false)

        #expect(library.entry(for: "v3")?.record.state == .downloading)
        #expect(library.entry(for: "v3")?.video.title == "A Video", "an in-flight download's stored video must be left untouched by a refresh")

        #expect(library.entry(for: "v4")?.record.state == .failed)
        #expect(library.entry(for: "v4")?.record.lastError == "network error", "a failed entry's own record must be left untouched by a refresh")
    }
}

}

/// A plain, lock-protected set of ids a mocked handler observed, for asserting exactly which
/// videos a refresh pass queried — same reasoning `CountBox` exists for a count.
private final class LockedSet: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []

    func insert(_ id: String) {
        lock.lock()
        ids.insert(id)
        lock.unlock()
    }

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return ids
    }
}
