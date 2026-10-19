
import Foundation

@MainActor
@Observable
public final class OfflineLibrary {
    /// One row's worth of what `OfflineVideosView`/a Home section needs — the player-stripped
    /// `Video` (so `VideoRow`/`VideoDetailStore`'s seed path render it unchanged) plus its
    /// download bookkeeping.
    public struct Entry: Identifiable, Sendable, Equatable {
        public var video: Video
        public var record: OfflineVideoRecord
        public var id: String { video.youtubeId }
    }

    /// One "Save a Copy…" request in flight — see `pendingExport`'s own doc comment.
    public struct PendingExport: Identifiable, Equatable {
        public var id: String { videoId }
        public var videoId: String
        public var sourceURL: URL
        public var suggestedFilename: String
    }

    public private(set) var entries: [Entry] = []
    /// Live byte counts and speed for transfers in flight. Apart from `entries` on purpose; see
    /// `OfflineTransferProgress`.
    public let transfers = OfflineTransferProgress()
    private var lastProgressPersist: [String: Date] = [:]
    public var videos: [Video] { entries.map(\.video) }
    public private(set) var waitingForWiFiVideoIds: Set<String> = []
    /// Videos actually transferring right now, as opposed to sitting in the queue waiting for a slot.
    public internal(set) var activeDownloadVideoIds: Set<String> = []
    /// Transfers that exist but that the system is holding for Wi-Fi — their request forbids an expensive path and the path is expensive.
    public internal(set) var heldForWiFiVideoIds: Set<String> = []
    public var pendingExport: PendingExport?

    /// Called after every delete with the ids that were removed.
    public var didDelete: (@MainActor ([String]) -> Void)?

    /// Positions from the most recent drag, applied over whatever `reload()` reads from disk
    /// until the disk agrees. See `reorderQueue`.
    private var pendingQueuePositions: [String: Int] = [:]
    /// The in-flight write of a drag's positions, so the next drag's write waits for it.
    private var queuePositionWrite: Task<Void, Never>?
    /// Bumped by every `reload()` as it starts, and by every delete. A reload only commits
    /// what it read if nothing has bumped this since it began — see `reload()`.
    private var reloadGeneration = 0
    /// The newest generation whose read has been committed to `entries`.
    private var committedGeneration = 0
    /// Superseded reloads waiting for a newer one to commit — see `reload()`.
    private var commitWaiters: [(generation: Int, continuation: CheckedContinuation<Void, Never>)] = []

    private let store: OfflineStore
    /// Kept alongside the actor's own copy so `localMediaURL(forVideoId:)` can check the
    /// filesystem directly, without a round trip through the actor, on every playback splice —
    /// see that method's own doc comment.
    private let root: URL
    private let thumbnailIndex = ThumbnailIndex()
    private var serverDigest: String?

    public init(root: URL) {
        self.root = root
        self.store = OfflineStore(root: root)
    }

    public static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PleviOffline", isDirectory: true)
    }

    /// Points this library at a (possibly different) server's own shelf.
    public func adopt(scope: String) async {
        let digest = ServerScope.digest(of: scope)
        guard digest != serverDigest else { return }
        serverDigest = digest
        await reload()
    }

    /// Re-reads every bundle under the current server's shelf.
    public func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        guard let serverDigest else {
            entries = []
            thumbnailIndex.replace([:])
            didCommit(generation)
            return
        }
        let ids = await store.videoIds(serverDigest: serverDigest)
        var loaded: [Entry] = []
        var thumbnails: [String: URL] = [:]
        for id in ids {
            guard let video = await store.video(serverDigest: serverDigest, youtubeId: id),
                  let record = await store.record(serverDigest: serverDigest, youtubeId: id)
            else { continue }
            loaded.append(Entry(video: video, record: record))
            if let path = video.vidThumbUrl {
                thumbnails[path] = await store.layout(serverDigest: serverDigest, youtubeId: id).thumbnail
            }
        }
        // Superseded while reading — a newer reload, or a delete, has happened since this one
        // began. The newer reload read the disk later, so it is the one that commits; this one
        // waits for it rather than returning with `entries` possibly still stale.
        guard generation == reloadGeneration else {
            await waitForCommit(atLeast: generation)
            return
        }
        applyPendingQueuePositions(to: &loaded)
        entries = loaded.sorted { $0.record.savedAt > $1.record.savedAt }
        transfers.prune(keeping: Set(entries.lazy.filter { $0.record.state == .downloading }.map(\.id)))
        for id in lastProgressPersist.keys where transfers.samples[id] == nil { lastProgressPersist.removeValue(forKey: id) }
        thumbnailIndex.replace(thumbnails)
        didCommit(generation)
    }

    /// Records a commit and releases every superseded reload it satisfies. Always reached: the
    /// newest reload started is never itself superseded, so it always commits, and every
    /// waiter's generation is at most its.
    private func didCommit(_ generation: Int) {
        committedGeneration = max(committedGeneration, generation)
        let ready = commitWaiters.filter { $0.generation <= committedGeneration }
        commitWaiters.removeAll { $0.generation <= committedGeneration }
        for waiter in ready { waiter.continuation.resume() }
    }

    private func waitForCommit(atLeast generation: Int) async {
        guard committedGeneration < generation else { return }
        await withCheckedContinuation { continuation in
            commitWaiters.append((generation, continuation))
        }
    }

    public func isSaved(videoId: String) -> Bool {
        entries.contains { $0.id == videoId }
    }

    /// Ids of videos that are fully on disk, as a set.
    public var downloadedVideoIds: Set<String> {
        Set(entries.lazy.filter { $0.record.state == .complete }.map(\.id))
    }

    public func entry(for videoId: String) -> Entry? {
        entries.first { $0.id == videoId }
    }

    @discardableResult
    public func beginSave(
        video: Video,
        client: TAClient? = nil,
        reason: OfflineVideoRecord.Reason = .savedByUser,
        skipReload: Bool = false
    ) async -> OfflineVideoRecord? {
        guard let serverDigest else { return nil }
        var record = try? await store.beginDownload(serverDigest: serverDigest, video: video, reason: reason, savedAt: Date())
        if let client, let thumbPath = video.vidThumbUrl, let data = try? await client.fetchMedia(path: thumbPath) {
            try? await store.writeThumbnail(serverDigest: serverDigest, youtubeId: video.youtubeId, data: data)
        }
        if let client {
            var savedFilenames: [String] = []
            for subtitle in video.subtitles ?? [] {
                guard let mediaPath = subtitle.mediaUrl, let filename = OfflineBundle.subtitleFilename(for: subtitle) else { continue }
                guard let data = try? await client.fetchMedia(path: mediaPath) else { continue }
                try? await store.writeSubtitle(serverDigest: serverDigest, youtubeId: video.youtubeId, filename: filename, data: data)
                savedFilenames.append(filename)
            }
            if !savedFilenames.isEmpty {
                try? await store.setSubtitleFilenames(serverDigest: serverDigest, youtubeId: video.youtubeId, filenames: savedFilenames)
                record = await store.record(serverDigest: serverDigest, youtubeId: video.youtubeId)
            }
        }
        if !skipReload { await reload() }
        return record
    }

    public func markComplete(videoId: String, from tempURL: URL) async {
        guard let serverDigest else { return }
        try? await store.completeDownload(serverDigest: serverDigest, youtubeId: videoId, from: tempURL)
        await reload()
    }

    public func markFailed(videoId: String, reason: String) async {
        guard let serverDigest else { return }
        try? await store.failDownload(serverDigest: serverDigest, youtubeId: videoId, reason: reason)
        await reload()
    }

    public func updateProgress(videoId: String, receivedByteCount: Int, expectedByteCount: Int?) async {
        // Live numbers go to `transfers`, which only the downloads screen reads. Writing them into
        // `entries`, which almost every screen reads, re-rendered all of those on every tick: the
        // lag while a download ran, and the menus flashing as they opened.
        transfers.update(videoId: videoId, receivedByteCount: receivedByteCount, expectedByteCount: expectedByteCount)

        // The record on disk only needs to be roughly current (a completion rewrites it from the
        // file's real size), so it is written every few seconds rather than on every tick.
        let now = Date()
        if let last = lastProgressPersist[videoId], now.timeIntervalSince(last) < 5 { return }
        lastProgressPersist[videoId] = now
        guard let serverDigest else { return }
        try? await store.updateProgress(serverDigest: serverDigest, youtubeId: videoId, receivedByteCount: receivedByteCount, expectedByteCount: expectedByteCount)
    }

    /// Everything still owed a download, in the order `OfflineDownloadQueue` will run it.
    public func queueItems() -> [OfflineDownloadQueue.Item] {
        OfflineDownloadQueue.order(
            entries
                .filter { $0.record.state == .downloading }
                .map { entry in
                    OfflineDownloadQueue.Item(
                        videoId: entry.id,
                        queuePosition: entry.record.queuePosition,
                        savedAt: entry.record.savedAt,
                        isWaitingForWiFi: waitingForWiFiVideoIds.contains(entry.id)
                    )
                }
        )
    }

    /// Records a queue order chosen by dragging, writing a position for every video in it.
    public func reorderQueue(videoIds: [String]) async {
        guard let serverDigest else { return }
        let positions = OfflineDownloadQueue.positions(forOrder: videoIds)

        // The newest drag is the whole truth about order — replace, never merge.
        pendingQueuePositions = positions
        for index in entries.indices {
            if let position = positions[entries[index].id] {
                entries[index].record.queuePosition = position
            }
        }

        let previous = queuePositionWrite
        let store = self.store
        let write = Task {
            await previous?.value
            try? await store.setQueuePositions(serverDigest: serverDigest, positions: positions)
        }
        queuePositionWrite = write
        await write.value
    }

    /// See `reorderQueue`. An override is dropped as soon as a reload reads the same value
    /// back from disk — that is the disk catching up — and for any video no longer on the
    /// shelf, so the overlay empties itself rather than needing to be cleared by anyone.
    private func applyPendingQueuePositions(to loaded: inout [Entry]) {
        guard !pendingQueuePositions.isEmpty else { return }
        var stillPending: [String: Int] = [:]
        for index in loaded.indices {
            let id = loaded[index].id
            guard let pending = pendingQueuePositions[id] else { continue }
            if loaded[index].record.queuePosition != pending {
                loaded[index].record.queuePosition = pending
                stillPending[id] = pending
            }
        }
        pendingQueuePositions = stillPending
    }

    /// Whether a bundle for this video still exists on disk.
    public func bundleExists(videoId: String) async -> Bool {
        guard let serverDigest else { return false }
        return await store.record(serverDigest: serverDigest, youtubeId: videoId) != nil
    }

    /// Puts a failed video back in the queue — the Downloads sheet's Retry. The transfer is
    /// started by `OfflineDownloader`, which picks it up on its next pump.
    public func requeue(videoId: String) async {
        guard let serverDigest else { return }
        // A drag's pending position would otherwise be re-applied by the reload below and put
        // the retried video straight back where it failed — undoing the "back of the queue"
        // that `OfflineStore.requeue` exists for.
        pendingQueuePositions[videoId] = nil
        try? await store.requeue(serverDigest: serverDigest, youtubeId: videoId)
        await reload()
    }

    /// Called by `OfflineDownloader` after every pump — see `activeDownloadVideoIds`.
    public func setActiveDownloads(_ videoIds: Set<String>) {
        guard activeDownloadVideoIds != videoIds else { return }
        activeDownloadVideoIds = videoIds
    }

    /// Called by `OfflineDownloader` on every pump — see `heldForWiFiVideoIds`.
    public func setHeldForWiFi(_ videoIds: Set<String>) {
        guard heldForWiFiVideoIds != videoIds else { return }
        heldForWiFiVideoIds = videoIds
    }

    public func isWaitingForWiFi(videoId: String) -> Bool {
        waitingForWiFiVideoIds.contains(videoId) || heldForWiFiVideoIds.contains(videoId)
    }

    public func delete(videoId: String) async {
        guard let serverDigest else { return }
        entries.removeAll { $0.id == videoId }
        reloadGeneration += 1
        try? await store.delete(serverDigest: serverDigest, youtubeId: videoId)
        waitingForWiFiVideoIds.remove(videoId)
        activeDownloadVideoIds.remove(videoId)
        heldForWiFiVideoIds.remove(videoId)
        if pendingExport?.videoId == videoId { pendingExport = nil }
        await reload()
        // After the reload, never before: see `OfflineDownloader.handleDeleted` on why a pump
        // that can still see the deleted video would start it again.
        didDelete?([videoId])
    }

    /// Deletes several bundles with one reload at the end.
    @discardableResult
    public func delete(videoIds: [String]) async -> Int {
        guard let serverDigest, !videoIds.isEmpty else { return 0 }
        // See `delete(videoId:)`.
        let doomed = Set(videoIds)
        entries.removeAll { doomed.contains($0.id) }
        reloadGeneration += 1
        var removed = 0
        for videoId in videoIds {
            do {
                try await store.delete(serverDigest: serverDigest, youtubeId: videoId)
                removed += 1
            } catch {
                continue
            }
            waitingForWiFiVideoIds.remove(videoId)
            activeDownloadVideoIds.remove(videoId)
            heldForWiFiVideoIds.remove(videoId)
            if pendingExport?.videoId == videoId { pendingExport = nil }
        }
        await reload()
        didDelete?(videoIds)
        return removed
    }

    /// The saved shelf grouped by the channel each video came from, largest first.
    public func entriesByChannel() -> [ChannelGroup] {
        var byChannel: [String: ChannelGroup] = [:]
        for entry in entries {
            let id = entry.video.channel?.channelId ?? ""
            let name = entry.video.channel?.channelName ?? "Unknown channel"
            var group = byChannel[id] ?? ChannelGroup(channelId: id, channelName: name, entries: [])
            group.entries.append(entry)
            byChannel[id] = group
        }
        return byChannel.values.sorted { $0.byteCount > $1.byteCount }
    }

    public struct ChannelGroup: Identifiable, Sendable {
        public let channelId: String
        public let channelName: String
        public var entries: [Entry]

        public var id: String { channelId }
        public var byteCount: Int { entries.map(\.record.receivedByteCount).reduce(0, +) }
        public var videoIds: [String] { entries.map(\.id) }
    }

    public func resumeData(videoId: String) async -> Data? {
        guard let serverDigest else { return nil }
        return await store.resumeData(serverDigest: serverDigest, youtubeId: videoId)
    }

    public func setResumeData(videoId: String, data: Data?) async {
        guard let serverDigest else { return }
        try? await store.setResumeData(serverDigest: serverDigest, youtubeId: videoId, data: data)
    }

    public func writeThumbnail(videoId: String, data: Data) async {
        guard let serverDigest else { return }
        try? await store.writeThumbnail(serverDigest: serverDigest, youtubeId: videoId, data: data)
        if let video = video(forVideoId: videoId), let path = video.vidThumbUrl {
            let layout = await store.layout(serverDigest: serverDigest, youtubeId: videoId)
            thumbnailIndex.set(url: layout.thumbnail, for: path)
        }
    }

    private func video(forVideoId videoId: String) -> Video? {
        entry(for: videoId)?.video
    }

    // MARK: - Playback splice

    /// `VideoPlaybackController`'s `offlineMediaProvider` hook: a saved video's own file, if one is fully downloaded.
    public func localMediaURL(forVideoId videoId: String) -> URL? {
        guard let serverDigest, let entry = entry(for: videoId), entry.record.state == .complete else { return nil }
        let fileURL = OfflineBundle.layout(root: root, serverDigest: serverDigest, youtubeId: videoId)
            .mediaFile(named: entry.record.mediaFilename)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public nonisolated func localImageData(forPath path: String) -> Data? {
        guard let url = thumbnailIndex.url(for: path) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func localSubtitles(forVideoId videoId: String) -> [ExternalSubtitle] {
        guard let serverDigest, let entry = entry(for: videoId), !entry.record.subtitleFilenames.isEmpty else { return [] }
        let layout = OfflineBundle.layout(root: root, serverDigest: serverDigest, youtubeId: videoId)
        var subtitles: [ExternalSubtitle] = []
        for subtitle in entry.video.subtitles ?? [] {
            guard let filename = OfflineBundle.subtitleFilename(for: subtitle),
                  entry.record.subtitleFilenames.contains(filename)
            else { continue }
            let fileURL = layout.subtitleFile(named: filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            subtitles.append(ExternalSubtitle(url: fileURL, name: subtitle.name ?? subtitle.lang ?? "Subtitles", language: subtitle.lang))
        }
        return subtitles
    }

    // MARK: - Cellular gating

    /// Called by `OfflineDownloader` when it defers a download rather than starting it.
    public func markWaitingForWiFi(videoId: String) {
        waitingForWiFiVideoIds.insert(videoId)
    }

    /// Clears every deferral at once — `OfflineDownloader.drainCellularDeferrals`, when the
    /// connection or the setting changes so that nothing need be blocked any longer.
    public func clearAllWaitingForWiFi() {
        guard !waitingForWiFiVideoIds.isEmpty else { return }
        waitingForWiFiVideoIds.removeAll()
    }

    public func clearWaitingForWiFi(videoId: String) {
        waitingForWiFiVideoIds.remove(videoId)
    }

    // MARK: - Storage

    /// Settings → Storage's headline number — the sum of what's actually landed on disk per record, never `video.mediaSize`.
    public var totalBytesUsed: Int {
        entries.map(\.record.receivedByteCount).reduce(0, +)
    }

    /// Bytes held by shelves belonging to some OTHER server — see `OfflineStore.serverDigests()` for how they come about.
    public func foreignBytesUsed() async -> Int {
        let current = serverDigest
        var total = 0
        for digest in await store.serverDigests() where digest != current {
            total += await store.byteCount(forDigest: digest)
        }
        return total
    }

    /// Deletes every shelf that is not the current server's, and returns the bytes reclaimed.
    @discardableResult
    public func removeForeignShelves() async -> Int {
        let current = serverDigest
        var reclaimed = 0
        for digest in await store.serverDigests() where digest != current {
            reclaimed += await store.byteCount(forDigest: digest)
            try? await store.deleteDigest(digest)
        }
        return reclaimed
    }

    @discardableResult
    public func removeWatched(client: TAClient) async -> Int {
        var removed = 0
        for entry in entries where entry.record.state == .complete {
            guard let video = try? await client.video(id: entry.id), video.player?.watched == true else { continue }
            await delete(videoId: entry.id)
            removed += 1
        }
        return removed
    }

    // MARK: - Metadata refresh and orphans

    /// Overwrites a saved video's stored metadata with the server's current copy — called once per entry by `OfflineMetadataSync`.
    public func updateVideoMetadata(videoId: String, video: Video, skipReload: Bool = false) async {
        guard let serverDigest else { return }
        try? await store.updateVideoMetadata(serverDigest: serverDigest, youtubeId: videoId, video: video)
        if !skipReload { await reload() }
    }

    /// Flags (or clears) a saved video as gone server-side.
    public func setOrphaned(videoId: String, isOrphaned: Bool, skipReload: Bool = false) async {
        guard let serverDigest else { return }
        try? await store.setOrphaned(serverDigest: serverDigest, youtubeId: videoId, isOrphaned: isOrphaned)
        if !skipReload { await reload() }
    }

    // MARK: - Export

    /// Arms the one `.fileExporter` presentation for this video's downloaded file.
    public func requestExport(videoId: String) {
        guard let sourceURL = localMediaURL(forVideoId: videoId), let entry = entry(for: videoId) else { return }
        let title = entry.video.title?.isEmpty == false ? entry.video.title! : videoId
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
        let ext = sourceURL.pathExtension
        let filename = ext.isEmpty ? sanitizedTitle : "\(sanitizedTitle).\(ext)"
        pendingExport = PendingExport(videoId: videoId, sourceURL: sourceURL, suggestedFilename: filename)
    }
}

/// A plain, lock-protected snapshot of thumbnail path → local file URL, rebuilt on every `OfflineLibrary.reload()`.
private final class ThumbnailIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var mapping: [String: URL] = [:]

    func replace(_ newMapping: [String: URL]) {
        lock.lock()
        mapping = newMapping
        lock.unlock()
    }

    func set(url: URL, for path: String) {
        lock.lock()
        mapping[path] = url
        lock.unlock()
    }

    func url(for path: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return mapping[path]
    }
}
