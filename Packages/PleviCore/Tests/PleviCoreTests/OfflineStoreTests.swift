import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineStore")
struct OfflineStoreTests {
    private func makeStore() -> (OfflineStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineStoreTests-\(UUID().uuidString)")
        return (OfflineStore(root: root), root)
    }

    private func makeVideo(id: String = "abc123") -> Video {
        var video = Video(youtubeId: id, title: "A Video", mediaUrl: "/media/chan/\(id).mp4")
        video.player = VideoPlayerState(duration: 754, durationStr: "12:34", watched: true, position: 300, progress: 40)
        return video
    }

    @Test("beginDownload writes a stripped video.json and a .downloading record")
    func beginDownloadWritesBundle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        #expect(record.state == .downloading)
        #expect(record.mediaFilename == "abc123.mp4")

        let readBack = await store.video(serverDigest: "s1", youtubeId: "abc123")
        #expect(readBack?.player?.watched == nil, "the stored video must have its player state stripped")

        // Nothing is playable yet — no media file has been moved into place.
        #expect(await store.mediaURL(serverDigest: "s1", youtubeId: "abc123") == nil)
    }

    @Test("completeDownload moves the file into place and mediaURL then resolves")
    func completeDownloadMakesMediaAvailable() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        let payload = Data(repeating: 0xAB, count: 1024)
        try payload.write(to: tempFile)

        try await store.completeDownload(serverDigest: "s1", youtubeId: "abc123", from: tempFile)

        let mediaURL = await store.mediaURL(serverDigest: "s1", youtubeId: "abc123")
        #expect(mediaURL != nil)
        #expect(try mediaURL.map { try Data(contentsOf: $0) } == payload)

        let record = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(record?.state == .complete)
        #expect(record?.receivedByteCount == 1024)
    }

    @Test("a .downloading record with no media file on disk never resolves as playable")
    func incompleteDownloadIsNeverPlayable() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        #expect(await store.mediaURL(serverDigest: "s1", youtubeId: "abc123") == nil)
    }

    @Test("failDownload records the state and the reason")
    func failDownloadRecordsReason() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        try await store.failDownload(serverDigest: "s1", youtubeId: "abc123", reason: "the server sent a web page instead of the video")

        let record = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(record?.state == .failed)
        #expect(record?.lastError == "the server sent a web page instead of the video")
    }

    @Test("delete removes the whole bundle, and a missing bundle deletes without throwing")
    func deleteRemovesBundle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        try await store.delete(serverDigest: "s1", youtubeId: "abc123")
        #expect(await store.video(serverDigest: "s1", youtubeId: "abc123") == nil)
        #expect(await store.videoIds(serverDigest: "s1").isEmpty)

        // Deleting again (nothing there) must not throw.
        try await store.delete(serverDigest: "s1", youtubeId: "abc123")
    }

    @Test("videoIds lists exactly the videos saved under one server digest")
    func videoIdsListsOnlyThatServer() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(id: "v1"), reason: .savedByUser, savedAt: Date())
        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(id: "v2"), reason: .savedByUser, savedAt: Date())
        _ = try await store.beginDownload(serverDigest: "s2", video: makeVideo(id: "v3"), reason: .savedByUser, savedAt: Date())

        #expect(Set(await store.videoIds(serverDigest: "s1")) == Set(["v1", "v2"]))
        #expect(await store.videoIds(serverDigest: "s2") == ["v3"])
    }

    @Test("a nonexistent server digest lists no videos rather than throwing")
    func missingServerDigestListsEmpty() async {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await store.videoIds(serverDigest: "never-saved-here").isEmpty)
    }

    @Test("updateVideoMetadata overwrites video.json with a freshly stripped copy")
    func updateVideoMetadataOverwritesVideoJSON() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())

        var refreshed = makeVideo()
        refreshed.title = "A Video (retitled after reindex)"
        try await store.updateVideoMetadata(serverDigest: "s1", youtubeId: "abc123", video: refreshed)

        let readBack = await store.video(serverDigest: "s1", youtubeId: "abc123")
        #expect(readBack?.title == "A Video (retitled after reindex)")
        #expect(readBack?.player?.watched == nil, "a refreshed snapshot must be stripped exactly like the original")

        // The record itself (state, byte counts) is untouched by a metadata-only refresh.
        let record = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(record?.state == .downloading)
    }

    @Test("setOrphaned flips the flag independently of every other record field")
    func setOrphanedFlipsFlag() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data(repeating: 0xAB, count: 1024).write(to: tempFile)
        try await store.completeDownload(serverDigest: "s1", youtubeId: "abc123", from: tempFile)
        try await store.setSubtitleFilenames(serverDigest: "s1", youtubeId: "abc123", filenames: ["abc123.en.vtt"])
        let before = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(before?.isOrphaned == false)

        try await store.setOrphaned(serverDigest: "s1", youtubeId: "abc123", isOrphaned: true)
        let afterOrphaned = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(afterOrphaned?.isOrphaned == true)
        #expect(afterOrphaned?.state == before?.state)
        #expect(afterOrphaned?.mediaFilename == before?.mediaFilename)
        #expect(afterOrphaned?.receivedByteCount == before?.receivedByteCount)
        #expect(afterOrphaned?.subtitleFilenames == before?.subtitleFilenames)

        try await store.setOrphaned(serverDigest: "s1", youtubeId: "abc123", isOrphaned: false)
        let afterCleared = await store.record(serverDigest: "s1", youtubeId: "abc123")
        #expect(afterCleared?.isOrphaned == false)
        #expect(afterCleared?.receivedByteCount == before?.receivedByteCount)
        #expect(afterCleared?.subtitleFilenames == before?.subtitleFilenames)
    }

    @Test("updateVideoMetadata throws videoNotFound for a video with no bundle on disk")
    func updateVideoMetadataThrowsForMissingBundle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: OfflineStore.StoreError.videoNotFound) {
            try await store.updateVideoMetadata(serverDigest: "s1", youtubeId: "never-saved", video: makeVideo(id: "never-saved"))
        }
    }

    @Test("setOrphaned throws videoNotFound for a video with no bundle on disk")
    func setOrphanedThrowsForMissingBundle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: OfflineStore.StoreError.videoNotFound) {
            try await store.setOrphaned(serverDigest: "s1", youtubeId: "never-saved", isOrphaned: true)
        }
    }

    @Test("resume data round-trips and clears on completion")
    func resumeDataRoundTrips() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        let blob = Data([1, 2, 3, 4])
        try await store.setResumeData(serverDigest: "s1", youtubeId: "abc123", data: blob)
        #expect(await store.resumeData(serverDigest: "s1", youtubeId: "abc123") == blob)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data([0xFF]).write(to: tempFile)
        try await store.completeDownload(serverDigest: "s1", youtubeId: "abc123", from: tempFile)

        #expect(await store.resumeData(serverDigest: "s1", youtubeId: "abc123") == nil, "resume data is stale once the download has finished")
    }

    // MARK: - Download queue

    @Test("setQueuePosition survives a round trip through record.json")
    func queuePositionPersists() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        #expect(await store.record(serverDigest: "s1", youtubeId: "abc123")?.queuePosition == nil)

        try await store.setQueuePosition(serverDigest: "s1", youtubeId: "abc123", position: 4)
        #expect(await store.record(serverDigest: "s1", youtubeId: "abc123")?.queuePosition == 4)

        try await store.setQueuePosition(serverDigest: "s1", youtubeId: "abc123", position: nil)
        #expect(await store.record(serverDigest: "s1", youtubeId: "abc123")?.queuePosition == nil)
    }

    @Test("requeue sends a failed video to the back of the queue rather than its old place")
    func requeueClearsQueuePosition() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(), reason: .savedByUser, savedAt: Date())
        try await store.setQueuePosition(serverDigest: "s1", youtubeId: "abc123", position: 0)
        try await store.updateProgress(serverDigest: "s1", youtubeId: "abc123", receivedByteCount: 900, expectedByteCount: 5000)
        try await store.failDownload(serverDigest: "s1", youtubeId: "abc123", reason: "the network went away")

        let retriedAt = Date(timeIntervalSince1970: 1_000_000)
        try await store.requeue(serverDigest: "s1", youtubeId: "abc123", now: retriedAt)

        let record = try #require(await store.record(serverDigest: "s1", youtubeId: "abc123"))
        #expect(record.state == .downloading)
        // A fresh savedAt, or an undragged queue (ordered by savedAt) puts it at the front.
        #expect(record.savedAt == retriedAt)
        #expect(record.lastError == nil)
        // Keeping position 0 would jump this video ahead of an order the user had since chosen.
        #expect(record.queuePosition == nil)
        // And the bytes are not on disk any more, so Storage must not keep counting them.
        #expect(record.receivedByteCount == 0)
        #expect(record.expectedByteCount == nil)
    }

    @Test("a drag's positions are written together, skipping a video deleted since")
    func setQueuePositionsSkipsMissing() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(id: "a"), reason: .savedByUser, savedAt: Date())
        _ = try await store.beginDownload(serverDigest: "s1", video: makeVideo(id: "b"), reason: .savedByUser, savedAt: Date())

        // "gone" was deleted between the drag and the write; the rest must still land.
        try await store.setQueuePositions(serverDigest: "s1", positions: ["b": 0, "gone": 1, "a": 2])

        #expect(await store.record(serverDigest: "s1", youtubeId: "b")?.queuePosition == 0)
        #expect(await store.record(serverDigest: "s1", youtubeId: "a")?.queuePosition == 2)
    }
}
