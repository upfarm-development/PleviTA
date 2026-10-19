import Foundation
import Testing
@testable import PleviCore

// Nested inside `MockedNetworkTests` (TAClientTests.swift's own doc comment explains why) since
// `beginSaveFetchesThumbnail` below drives the shared, process-global `MockURLProtocol.handler`.
extension MockedNetworkTests {

@MainActor
@Suite("OfflineLibrary", .serialized)
struct OfflineLibraryTests {
    private func makeLibrary() -> (OfflineLibrary, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineLibraryTests-\(UUID().uuidString)")
        return (OfflineLibrary(root: root), root)
    }

    private func makeVideo(id: String = "abc123", thumbPath: String? = "/cache/videos/abc123/thumb.jpg") -> Video {
        Video(youtubeId: id, title: "A Video", vidThumbUrl: thumbPath, mediaUrl: "/media/chan/\(id).mp4")
    }

    /// Writes a bundle straight through a store on the same root, so `savedAt` can be chosen —
    /// `beginSave` stamps it with the current time, and queue ordering is a question about
    /// which video was asked for first.
    private func seed(root: URL, id: String, savedAt: TimeInterval, scope: String = "https://ta.example.com") async throws {
        let store = OfflineStore(root: root)
        _ = try await store.beginDownload(
            serverDigest: ServerScope.digest(of: scope),
            video: makeVideo(id: id, thumbPath: nil),
            reason: .savedByUser,
            savedAt: Date(timeIntervalSince1970: savedAt)
        )
    }

    @Test("before adopting a server, nothing is saved and nothing can be looked up")
    func noScopeMeansEmptyShelf() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(library.entries.isEmpty)
        #expect(library.localMediaURL(forVideoId: "abc123") == nil)
        await library.reload()
        #expect(library.entries.isEmpty)
    }

    @Test("beginSave puts the video on the shelf immediately, before any bytes have arrived")
    func beginSaveShowsRowImmediately() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        let record = await library.beginSave(video: makeVideo())
        #expect(record?.state == .downloading)
        #expect(library.isSaved(videoId: "abc123"))
        #expect(library.localMediaURL(forVideoId: "abc123") == nil, "not playable until the download completes")
    }

    @Test("saved videos group by channel, largest first, with the channel-less kept")
    func entriesGroupByChannel() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        func video(_ id: String, channel: String?) -> Video {
            Video(
                youtubeId: id,
                title: "Video \(id)",
                mediaUrl: "/media/chan/\(id).mp4",
                channel: channel.map {
                    VideoChannelSummary(
                        channelId: $0,
                        channelName: "Name \($0)",
                        channelThumbUrl: nil,
                        channelBannerUrl: nil,
                        channelTvartUrl: nil,
                        channelSubscribed: nil,
                        channelDescription: nil,
                        channelLastRefresh: nil
                    )
                }
            )
        }

        for (id, channel) in [("a1", "c1"), ("a2", "c1"), ("b1", "c2"), ("z1", nil)] {
            _ = await library.beginSave(video: video(id, channel: channel))
        }

        let groups = library.entriesByChannel()
        #expect(groups.count == 3)
        #expect(Set(groups.map(\.channelId)) == ["c1", "c2", ""])
        #expect(groups.first(where: { $0.channelId == "c1" })?.entries.count == 2)
        #expect(groups.first(where: { $0.channelId == "" })?.channelName == "Unknown channel")
        // Every saved video lands in exactly one group, so the group sizes still add up.
        #expect(groups.flatMap(\.videoIds).sorted() == ["a1", "a2", "b1", "z1"])
    }

    @Test("removing several videos at once leaves the rest alone")
    func batchDeleteRemovesOnlyWhatWasAsked() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        for id in ["a1", "a2", "b1"] {
            _ = await library.beginSave(video: makeVideo(id: id, thumbPath: nil))
        }
        let removed = await library.delete(videoIds: ["a1", "b1"])
        #expect(removed == 2)
        #expect(library.entries.map(\.id) == ["a2"])
    }

    @Test("completing a download makes the video's file resolvable, and the entry survives player state stripping")
    func completingDownloadMakesItPlayable() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        var video = makeVideo()
        video.player = VideoPlayerState(duration: 100, durationStr: "1:40", watched: true, position: 42, progress: 42)
        _ = await library.beginSave(video: video)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data([0x01, 0x02, 0x03]).write(to: tempFile)
        await library.markComplete(videoId: "abc123", from: tempFile)

        let mediaURL = library.localMediaURL(forVideoId: "abc123")
        #expect(mediaURL != nil)

        let stored = library.entry(for: "abc123")?.video
        #expect(stored?.player?.watched == nil, "the stored copy must never carry stale watched state")
    }

    @Test("localImageData resolves a saved video's own thumbnail by its exact vid_thumb_url path")
    func localImageDataResolvesThumbnail() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo(thumbPath: "/cache/videos/abc123/thumb.jpg"))
        let thumbBytes = Data([0xFF, 0xD8, 0xFF])
        await library.writeThumbnail(videoId: "abc123", data: thumbBytes)

        #expect(library.localImageData(forPath: "/cache/videos/abc123/thumb.jpg") == thumbBytes)
        #expect(library.localImageData(forPath: "/cache/videos/someone-else/thumb.jpg") == nil)
    }

    @Test("beginSave fetches and stores the thumbnail immediately when a client is given")
    func beginSaveFetchesThumbnail() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        let thumbBytes = Data([0xFF, 0xD8, 0xFF])
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = TAClient(
            serverURL: URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!,
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { _ in .init(statusCode: 200, headers: ["Content-Type": "image/jpeg"], body: thumbBytes) }

        _ = await library.beginSave(video: makeVideo(thumbPath: "/cache/videos/abc123/thumb.jpg"), client: client)

        #expect(library.localImageData(forPath: "/cache/videos/abc123/thumb.jpg") == thumbBytes)
    }

    @Test("delete removes the video from the shelf and it's no longer playable")
    func deleteRemovesFromShelf() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo())
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data([0x01]).write(to: tempFile)
        await library.markComplete(videoId: "abc123", from: tempFile)

        await library.delete(videoId: "abc123")
        #expect(!library.isSaved(videoId: "abc123"))
        #expect(library.localMediaURL(forVideoId: "abc123") == nil)
    }

    @Test("adopting a different server shows only that server's own shelf")
    func adoptSwitchesShelf() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        await library.adopt(scope: "https://a.example")
        _ = await library.beginSave(video: makeVideo(id: "v1"))

        await library.adopt(scope: "https://b.example")
        #expect(library.entries.isEmpty)

        await library.adopt(scope: "https://a.example")
        #expect(library.isSaved(videoId: "v1"))
    }

    @Test("markFailed records the failure and the video stays visible as failed, not playable")
    func markFailedKeepsRowVisible() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo())
        await library.markFailed(videoId: "abc123", reason: "the server sent a web page instead of the video")

        let entry = library.entry(for: "abc123")
        #expect(entry?.record.state == .failed)
        #expect(entry?.record.lastError == "the server sent a web page instead of the video")
        #expect(library.localMediaURL(forVideoId: "abc123") == nil)
    }

    // MARK: - Slice 2

    @Test("beginSave fetches every subtitle sidecar it can derive a filename for")
    func beginSaveFetchesSubtitles() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        var video = makeVideo()
        video.subtitles = [
            Subtitle(name: "English", lang: "en", mediaUrl: "/cache/subs/abc123/en.vtt", source: nil),
            Subtitle(name: "No URL", lang: "xx", mediaUrl: nil, source: nil)
        ]
        let subtitleBytes = Data("WEBVTT".utf8)
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = TAClient(
            serverURL: URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!,
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { _ in .init(statusCode: 200, body: subtitleBytes) }

        _ = await library.beginSave(video: video, client: client)

        let subtitles = library.localSubtitles(forVideoId: "abc123")
        #expect(subtitles.count == 1)
        #expect(subtitles.first?.name == "English")
        #expect(try Data(contentsOf: subtitles[0].url) == subtitleBytes)
    }

    @Test("localSubtitles is empty until a download has actually landed a file")
    func localSubtitlesEmptyBeforeDownload() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        var video = makeVideo()
        video.subtitles = [Subtitle(name: "English", lang: "en", mediaUrl: "/cache/subs/abc123/en.vtt", source: nil)]
        _ = await library.beginSave(video: video) // no client: nothing fetched

        #expect(library.localSubtitles(forVideoId: "abc123").isEmpty)
    }

    @Test("waiting-for-WiFi marks are purely in-memory and independent per video")
    func waitingForWiFiTracking() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        library.markWaitingForWiFi(videoId: "v1")
        library.markWaitingForWiFi(videoId: "v2")
        #expect(library.waitingForWiFiVideoIds == ["v1", "v2"])

        library.clearWaitingForWiFi(videoId: "v1")
        #expect(library.waitingForWiFiVideoIds == ["v2"])
    }

    @Test("totalBytesUsed sums receivedByteCount across every entry, never mediaSize")
    func totalBytesUsedSumsReceivedBytes() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        var videoA = makeVideo(id: "v1")
        videoA.mediaSize = 999_999_999 // deliberately wrong/unrelated — must be ignored
        _ = await library.beginSave(video: videoA)
        let tempA = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data(repeating: 0xAB, count: 1000).write(to: tempA)
        await library.markComplete(videoId: "v1", from: tempA)

        _ = await library.beginSave(video: makeVideo(id: "v2"))
        let tempB = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data(repeating: 0xCD, count: 2000).write(to: tempB)
        await library.markComplete(videoId: "v2", from: tempB)

        #expect(library.totalBytesUsed == 3000)
    }

    @Test("removeWatched deletes only the entries the live server currently reports as watched")
    func removeWatchedDeletesOnlyServerWatched() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        for id in ["v1", "v2"] {
            _ = await library.beginSave(video: makeVideo(id: id))
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
            try Data([0x01]).write(to: temp)
            await library.markComplete(videoId: id, from: temp)
        }

        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        let client = TAClient(
            serverURL: URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!,
            credentialStore: credentialStore,
            urlSession: MockURLProtocol.makeSession()
        )
        MockURLProtocol.handler = { request in
            let watched = request.url?.absoluteString.contains("/video/v1/") == true
            return .init(statusCode: 200, body: Data("""
            {"youtube_id": "\(watched ? "v1" : "v2")", "player": {"watched": \(watched)}}
            """.utf8))
        }

        let removed = await library.removeWatched(client: client)
        #expect(removed == 1)
        #expect(!library.isSaved(videoId: "v1"))
        #expect(library.isSaved(videoId: "v2"))
    }

    @Test("skipReload leaves entries stale until the caller reloads itself")
    func skipReloadDeferesEntriesUpdate() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo(), skipReload: true)
        #expect(library.entries.isEmpty, "skipReload must not touch entries on its own")

        await library.reload()
        #expect(library.isSaved(videoId: "abc123"))
    }

    // MARK: - Slice 4

    @Test("updateVideoMetadata overwrites the stored video, reloading by default")
    func updateVideoMetadataOverwritesStoredVideo() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        _ = await library.beginSave(video: makeVideo())

        var refreshed = makeVideo()
        refreshed.title = "Retitled after reindex"
        await library.updateVideoMetadata(videoId: "abc123", video: refreshed)

        #expect(library.entry(for: "abc123")?.video.title == "Retitled after reindex")
    }

    @Test("updateVideoMetadata with skipReload leaves entries stale until the caller reloads")
    func updateVideoMetadataSkipReloadDefersEntriesUpdate() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        _ = await library.beginSave(video: makeVideo())

        var refreshed = makeVideo()
        refreshed.title = "Retitled after reindex"
        await library.updateVideoMetadata(videoId: "abc123", video: refreshed, skipReload: true)
        #expect(library.entry(for: "abc123")?.video.title == "A Video", "skipReload must not touch entries on its own")

        await library.reload()
        #expect(library.entry(for: "abc123")?.video.title == "Retitled after reindex")
    }

    @Test("updateVideoMetadata/setOrphaned for a video with no bundle fail silently, without creating anything")
    func metadataRefreshMethodsFailSilentlyForAnUnknownVideo() async {
        // Simulates OfflineMetadataSync.refresh racing a swipe-to-delete on the same video between its `library.entries` snapshot and this call.
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        await library.updateVideoMetadata(videoId: "never-saved", video: makeVideo(id: "never-saved"))
        await library.setOrphaned(videoId: "never-saved", isOrphaned: true)

        #expect(library.entries.isEmpty, "neither call may create an entry for a video that was never saved")
    }

    @Test("setOrphaned toggles the flag and reloads by default")
    func setOrphanedTogglesFlag() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        _ = await library.beginSave(video: makeVideo())

        await library.setOrphaned(videoId: "abc123", isOrphaned: true)
        #expect(library.entry(for: "abc123")?.record.isOrphaned == true)

        await library.setOrphaned(videoId: "abc123", isOrphaned: false)
        #expect(library.entry(for: "abc123")?.record.isOrphaned == false)
    }

    @Test("requestExport arms pendingExport with the local file, only once it's complete")
    func requestExportArmsPendingExport() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo())
        library.requestExport(videoId: "abc123")
        #expect(library.pendingExport == nil, "not complete yet — nothing to export")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp4")
        try Data([0x01]).write(to: temp)
        await library.markComplete(videoId: "abc123", from: temp)

        library.requestExport(videoId: "abc123")
        #expect(library.pendingExport?.videoId == "abc123")
        #expect(library.pendingExport?.suggestedFilename == "A Video.mp4")
    }

    // MARK: - Download queue

    @Test("the queue runs oldest-saved first, which is the reverse of the shelf's own order")
    func queueIsOldestFirst() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        try? await seed(root: root, id: "first", savedAt: 100)
        try? await seed(root: root, id: "second", savedAt: 200)
        await library.reload()

        // The shelf shows newest first...
        #expect(library.entries.map(\.id) == ["second", "first"])
        // ...and the queue runs the other way, so a long list downloads in the order asked for.
        #expect(library.queueItems().map(\.videoId) == ["first", "second"])
    }

    @Test("a completed video leaves the queue, a failed one too")
    func queueExcludesResolved() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        _ = await library.beginSave(video: makeVideo(id: "ok", thumbPath: nil))
        _ = await library.beginSave(video: makeVideo(id: "bad", thumbPath: nil))
        #expect(library.queueItems().count == 2)

        await library.markFailed(videoId: "bad", reason: "nope")
        // A failure must not keep holding a concurrency slot.
        #expect(library.queueItems().map(\.videoId) == ["ok"])
    }

    @Test("reorderQueue writes a position for every video and takes effect immediately")
    func reorderQueueAppliesAtOnce() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        for (index, id) in ["a", "b", "c"].enumerated() {
            try? await seed(root: root, id: id, savedAt: TimeInterval(index))
        }
        await library.reload()
        #expect(library.queueItems().map(\.videoId) == ["a", "b", "c"])

        await library.reorderQueue(videoIds: ["c", "a", "b"])
        #expect(library.queueItems().map(\.videoId) == ["c", "a", "b"])

        // And it survives a reload, so the downloader agrees with the sheet after a relaunch.
        await library.reload()
        #expect(library.queueItems().map(\.videoId) == ["c", "a", "b"])
    }

    @Test("requeue puts a retried video behind the order the user chose, not back at its old slot")
    func requeueGoesToTheBack() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        for (index, id) in ["a", "b", "c"].enumerated() {
            try? await seed(root: root, id: id, savedAt: TimeInterval(index))
        }
        await library.reload()
        await library.reorderQueue(videoIds: ["a", "b", "c"])
        await library.markFailed(videoId: "a", reason: "the network went away")

        await library.requeue(videoId: "a")
        // "a" held position 0; retrying it must not jump it back to the front.
        #expect(library.queueItems().map(\.videoId) == ["b", "c", "a"])
    }

    @Test("Retry goes to the back of the queue even when nothing was ever dragged")
    func requeueGoesToTheBackWithoutADrag() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        for (index, id) in ["a", "b", "c"].enumerated() {
            try await seed(root: root, id: id, savedAt: TimeInterval(index))
        }
        await library.reload()
        // The oldest save fails — the one the queue started first.
        await library.markFailed(videoId: "a", reason: "the network went away")

        await library.requeue(videoId: "a")
        #expect(library.queueItems().map(\.videoId) == ["b", "c", "a"])
    }

    @Test("bundleExists answers from disk, so it is still right while the snapshot is stale")
    func bundleExistsReadsDisk() async {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        // `skipReload` is exactly the state a batch save is in: written to disk, absent from
        // `entries`. The orphan check must not mistake that for a deleted video.
        _ = await library.beginSave(video: makeVideo(id: "batched", thumbPath: nil), skipReload: true)
        #expect(library.entries.isEmpty)
        #expect(await library.bundleExists(videoId: "batched"))
        #expect(await library.bundleExists(videoId: "never-saved") == false)
    }

    @Test("a reload that reads a half-written drag from disk does not scramble the queue")
    func reloadOfStaleDiskKeepsTheDraggedOrder() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")

        let ids = (0..<6).map { "v\($0)" }
        for (index, id) in ids.enumerated() {
            try await seed(root: root, id: id, savedAt: TimeInterval(index))
        }
        await library.reload()
        let dragged = Array(ids.reversed())
        await library.reorderQueue(videoIds: dragged)

        // Put the disk into the state a reload can catch mid-write: the first half of the drag landed, the rest still on the old positions.
        let digest = ServerScope.digest(of: "https://ta.example.com")
        try await OfflineStore(root: root).setQueuePositions(
            serverDigest: digest,
            positions: ["v5": 0, "v4": 1, "v3": 2]
        )
        for id in ["v2", "v1", "v0"] {
            try await OfflineStore(root: root).setQueuePosition(serverDigest: digest, youtubeId: id, position: nil)
        }

        await library.reload()
        // Without the overlay this read `v5,v4,v3,v0,v1,v2`: the unwritten half fell back to
        // `savedAt` order behind the written half — an order nobody chose, and the one the
        // downloader would then have started videos in.
        #expect(library.queueItems().map(\.videoId) == dragged)

        // Once the disk agrees, the overlay lets go — or a later legitimate change on disk
        // would be fought forever by a drag that has long since been saved.
        try await OfflineStore(root: root).setQueuePositions(
            serverDigest: digest,
            positions: OfflineDownloadQueue.positions(forOrder: dragged)
        )
        await library.reload()
        try await OfflineStore(root: root).setQueuePositions(
            serverDigest: digest,
            positions: OfflineDownloadQueue.positions(forOrder: ids)
        )
        await library.reload()
        #expect(library.queueItems().map(\.videoId) == ids, "disk is authoritative again")
    }

    @Test("every delete tells the downloader, after the video has left the shelf")
    func deleteFiresTheHookAfterRemoval() async throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        await library.adopt(scope: "https://ta.example.com")
        for (index, id) in ["a", "b", "c"].enumerated() {
            try await seed(root: root, id: id, savedAt: TimeInterval(index))
        }
        await library.reload()

        var calls: [[String]] = []
        var stillVisibleWhenCalled = false
        library.didDelete = { ids in
            calls.append(ids)
            // The downloader pumps from here. If the deleted video were still in the queue, the
            // pump would see the slot its cancellation freed and start it straight back up.
            if ids.contains(where: { id in library.queueItems().contains { $0.videoId == id } }) {
                stillVisibleWhenCalled = true
            }
        }

        await library.delete(videoId: "a")
        await library.delete(videoIds: ["b", "c"])

        #expect(calls == [["a"], ["b", "c"]])
        #expect(!stillVisibleWhenCalled)
    }

    @Test("clearing every Wi-Fi deferral clears them all, not a remembered subset")
    func clearAllWaitingForWiFi() {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        library.markWaitingForWiFi(videoId: "a")
        library.markWaitingForWiFi(videoId: "b")
        library.clearAllWaitingForWiFi()
        #expect(library.waitingForWiFiVideoIds.isEmpty)
    }
}

}
