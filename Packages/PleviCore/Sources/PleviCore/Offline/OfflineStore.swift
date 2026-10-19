
import Foundation

public actor OfflineStore {
    public enum StoreError: Error, Sendable, Equatable {
        case videoNotFound
    }

    private let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func layout(serverDigest: String, youtubeId: String) -> OfflineBundle.Layout {
        OfflineBundle.layout(root: root, serverDigest: serverDigest, youtubeId: youtubeId)
    }

    // MARK: - Reading the shelf

    /// Every video id saved under `serverDigest`, regardless of state — `.downloading` and
    /// `.failed` bundles are included, since the caller (`OfflineLibrary`) decides what each
    /// state should look like on screen, not this actor.
    public func videoIds(serverDigest: String) -> [String] {
        let dir = OfflineBundle.serverDirectory(root: root, serverDigest: serverDigest)
        guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.lastPathComponent }
    }

    /// Every server shelf on disk, not just the one currently signed in.
    public func serverDigests() -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.lastPathComponent }
    }

    /// Bytes on disk under one server shelf, walked rather than summed from records — a
    /// foreign shelf's records are exactly what this cannot assume are readable.
    public func byteCount(forDigest digest: String) -> Int {
        let dir = OfflineBundle.serverDirectory(root: root, serverDigest: digest)
        guard let walker = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let url as URL in walker {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }

    /// Removes a whole server shelf. Used only for shelves that are not the current one —
    /// the current one is managed a bundle at a time by `delete(serverDigest:youtubeId:)`.
    public func deleteDigest(_ digest: String) throws {
        try fileManager.removeItem(at: OfflineBundle.serverDirectory(root: root, serverDigest: digest))
    }

    public func record(serverDigest: String, youtubeId: String) -> OfflineVideoRecord? {
        guard let data = try? Data(contentsOf: layout(serverDigest: serverDigest, youtubeId: youtubeId).recordJSON) else {
            return nil
        }
        return try? OfflineBundle.decodeRecordJSON(data)
    }

    public func video(serverDigest: String, youtubeId: String) -> Video? {
        guard let data = try? Data(contentsOf: layout(serverDigest: serverDigest, youtubeId: youtubeId).videoJSON) else {
            return nil
        }
        return try? OfflineBundle.decodeVideoJSON(data)
    }

    public func thumbnailData(serverDigest: String, youtubeId: String) -> Data? {
        try? Data(contentsOf: layout(serverDigest: serverDigest, youtubeId: youtubeId).thumbnail)
    }

    /// The local media file's URL — `nil` unless the record says `.complete` **and** the file
    /// is actually there, so a bundle left half-written by a killed app (record updated, file
    /// not yet moved into place) is never handed to the player as if it were finished.
    public func mediaURL(serverDigest: String, youtubeId: String) -> URL? {
        guard let record = record(serverDigest: serverDigest, youtubeId: youtubeId), record.state == .complete else {
            return nil
        }
        let fileURL = layout(serverDigest: serverDigest, youtubeId: youtubeId).mediaFile(named: record.mediaFilename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public func resumeData(serverDigest: String, youtubeId: String) -> Data? {
        try? Data(contentsOf: resumeDataURL(serverDigest: serverDigest, youtubeId: youtubeId))
    }

    private func resumeDataURL(serverDigest: String, youtubeId: String) -> URL {
        layout(serverDigest: serverDigest, youtubeId: youtubeId).directory.appendingPathComponent("resume.data")
    }

    // MARK: - Writing

    /// Creates (or replaces) a video's bundle at the start of a download: writes the
    /// player-stripped `video.json` and a fresh `.downloading` record, so the row can appear
    /// in `OfflineVideosView` before a single byte of media has arrived.
    @discardableResult
    public func beginDownload(
        serverDigest: String,
        video: Video,
        reason: OfflineVideoRecord.Reason,
        savedAt: Date
    ) throws -> OfflineVideoRecord {
        let layout = layout(serverDigest: serverDigest, youtubeId: video.youtubeId)
        try fileManager.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        try OfflineBundle.encodeVideoJSON(video).write(to: layout.videoJSON, options: .atomic)
        excludeFromBackup(layout.videoJSON)
        let record = OfflineVideoRecord(
            youtubeId: video.youtubeId,
            state: .downloading,
            reason: reason,
            savedAt: savedAt,
            mediaFilename: OfflineBundle.mediaFilename(for: video)
        )
        try write(record, layout: layout)
        return record
    }

    public func updateProgress(
        serverDigest: String,
        youtubeId: String,
        receivedByteCount: Int,
        expectedByteCount: Int?
    ) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) {
            $0.receivedByteCount = receivedByteCount
            if let expectedByteCount { $0.expectedByteCount = expectedByteCount }
        }
    }

    public func completeDownload(serverDigest: String, youtubeId: String, from tempURL: URL) throws {
        guard var record = record(serverDigest: serverDigest, youtubeId: youtubeId) else {
            throw StoreError.videoNotFound
        }
        let layout = layout(serverDigest: serverDigest, youtubeId: youtubeId)
        let destination = layout.mediaFile(named: record.mediaFilename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        excludeFromBackup(destination)
        let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
        record.receivedByteCount = (attributes?[.size] as? Int) ?? record.receivedByteCount
        record.state = .complete
        record.lastError = nil
        try write(record, layout: layout)
        try? fileManager.removeItem(at: resumeDataURL(serverDigest: serverDigest, youtubeId: youtubeId))
    }

    public func failDownload(serverDigest: String, youtubeId: String, reason: String) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) {
            $0.state = .failed
            $0.lastError = reason
        }
    }

    /// `cancel(byProducingResumeData:)` blobs — `data: nil` clears whatever was there, so a resume attempt that turns out stale doesn't linger.
    public func setResumeData(serverDigest: String, youtubeId: String, data: Data?) throws {
        let url = resumeDataURL(serverDigest: serverDigest, youtubeId: youtubeId)
        if let data {
            try data.write(to: url, options: .atomic)
            excludeFromBackup(url)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    public func writeThumbnail(serverDigest: String, youtubeId: String, data: Data) throws {
        let layout = layout(serverDigest: serverDigest, youtubeId: youtubeId)
        try data.write(to: layout.thumbnail, options: .atomic)
        excludeFromBackup(layout.thumbnail)
    }

    public func writeSubtitle(serverDigest: String, youtubeId: String, filename: String, data: Data) throws {
        let layout = layout(serverDigest: serverDigest, youtubeId: youtubeId)
        let url = layout.subtitleFile(named: filename)
        try data.write(to: url, options: .atomic)
        excludeFromBackup(url)
    }

    public func setSubtitleFilenames(serverDigest: String, youtubeId: String, filenames: [String]) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) { $0.subtitleFilenames = filenames }
    }

    public func updateVideoMetadata(serverDigest: String, youtubeId: String, video: Video) throws {
        guard record(serverDigest: serverDigest, youtubeId: youtubeId) != nil else {
            throw StoreError.videoNotFound
        }
        let layout = layout(serverDigest: serverDigest, youtubeId: youtubeId)
        try OfflineBundle.encodeVideoJSON(video).write(to: layout.videoJSON, options: .atomic)
        excludeFromBackup(layout.videoJSON)
    }

    public func setOrphaned(serverDigest: String, youtubeId: String, isOrphaned: Bool) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) { $0.isOrphaned = isOrphaned }
    }

    /// Where this video sits in the download queue — see `OfflineDownloadQueue`. Written for
    /// every queued video at once when the queue is reordered, never for one in isolation,
    /// since a position only means anything next to the others.
    public func setQueuePosition(serverDigest: String, youtubeId: String, position: Int?) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) { $0.queuePosition = position }
    }

    /// Writes a whole drag's positions in one call — see `OfflineLibrary.reorderQueue`.
    public func setQueuePositions(serverDigest: String, positions: [String: Int]) throws {
        for (youtubeId, position) in positions {
            do {
                try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) { $0.queuePosition = position }
            } catch StoreError.videoNotFound {
                continue
            }
        }
    }

    /// Puts a failed video back into the queue: `.downloading`, error cleared, at the BACK of the queue.
    public func requeue(serverDigest: String, youtubeId: String, now: Date = Date()) throws {
        try updateRecord(serverDigest: serverDigest, youtubeId: youtubeId) { record in
            record.state = .downloading
            record.lastError = nil
            record.savedAt = now
            record.queuePosition = nil
            record.receivedByteCount = 0
            record.expectedByteCount = nil
        }
    }

    public func delete(serverDigest: String, youtubeId: String) throws {
        let directory = layout(serverDigest: serverDigest, youtubeId: youtubeId).directory
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func updateRecord(
        serverDigest: String,
        youtubeId: String,
        _ mutate: (inout OfflineVideoRecord) -> Void
    ) throws {
        guard var record = record(serverDigest: serverDigest, youtubeId: youtubeId) else {
            throw StoreError.videoNotFound
        }
        mutate(&record)
        try write(record, layout: layout(serverDigest: serverDigest, youtubeId: youtubeId))
    }

    private func write(_ record: OfflineVideoRecord, layout: OfflineBundle.Layout) throws {
        try OfflineBundle.encodeRecordJSON(record).write(to: layout.recordJSON, options: .atomic)
        excludeFromBackup(layout.recordJSON)
    }

    private func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}
