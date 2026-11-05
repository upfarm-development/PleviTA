
import Foundation

extension TAClient {
    public func videos(_ query: VideoListQuery = VideoListQuery()) async throws -> Paginated<Video> {
        try await request(.videos(query))
    }

    public func video(id: String) async throws -> Video {
        try await request(.video(id: id))
    }

    @discardableResult
    public func setProgress(videoId: String, position: Double) async throws -> VideoProgressResponse {
        try await request(.setProgress(id: videoId, position: position))
    }

    public func clearProgress(videoId: String) async throws {
        try await requestNoContent(.clearProgress(id: videoId))
    }

    public func comments(videoId: String) async throws -> [Comment] {
        try await request(.comments(id: videoId))
    }

    public func similarVideos(videoId: String) async throws -> [Video] {
        try await request(.similar(id: videoId))
    }

    public func nav(videoId: String) async throws -> [VideoNavEntry] {
        try await request(.nav(id: videoId))
    }

    public func setWatched(id: String, isWatched: Bool) async throws {
        try await requestNoContent(.setWatched(id: id, isWatched: isWatched))
    }

    public func deleteVideo(id: String) async throws { try await requestNoContent(.deleteVideo(id: id)) }
    /// `"ignore-force"`, not `"ignore"`.
    public func ignoreDownload(id: String) async throws {
        try await requestNoContent(.ignoreDownload(id: id))
    }

    /// Adds a video to Tube Archivist's download queue as `pending`, without starting the download.
    public func addToDownloadQueue(id: String) async throws {
        try await addToDownloadQueue(ids: [id])
    }

    /// Every video a query matches, walked across all its pages. For a channel's whole library,
    /// which no single screen's loaded list holds.
    public func allVideos(matching query: VideoListQuery) async throws -> [Video] {
        var all: [Video] = []
        var query = query
        var page = 1
        while true {
            query.page = page
            let result = try await videos(query)
            all.append(contentsOf: result.data)
            guard let paginate = result.paginate, paginate.hasNextPage else { break }
            page += 1
            if page > 200 { break }
        }
        return all
    }

    /// One request for any number of videos, so re-downloading a whole channel is a single
    /// extraction task on the server rather than one per video.
    public func addToDownloadQueue(ids: [String]) async throws {
        try await requestNoContent(.addToDownloadQueue(ids: ids))
    }

    /// Delete each video, and with `ignoring` also tell Tube Archivist not to download it again.
    public func deleteVideos(
        ids: [String],
        ignoring: Bool,
        onProgress: @MainActor @Sendable (_ deleted: Int) -> Void = { _ in }
    ) async -> BulkDeleteResult {
        var result = BulkDeleteResult()
        for (index, id) in ids.enumerated() {
            if Task.isCancelled {
                result.notAttempted = Array(ids[index...])
                break
            }
            do {
                try await deleteVideo(id: id)
            } catch TAError.notFound {
                // Already gone.
            } catch {
                result.stopError = (error as? TAError) ?? .network(error.localizedDescription)
                result.notAttempted = Array(ids[index...])
                break
            }
            result.deleted.append(id)
            if ignoring {
                do { try await ignoreDownload(id: id) } catch { result.ignoreFailures += 1 }
            }
            await onProgress(result.deleted.count)
        }
        return result
    }

    /// Delete each video, then put the ones that are gone back on the download queue in one request.
    public func redownload(
        videoIds: [String],
        onProgress: @MainActor @Sendable (_ deleted: Int) -> Void = { _ in }
    ) async -> BulkRedownloadResult {
        var result = BulkRedownloadResult()
        for (index, id) in videoIds.enumerated() {
            if Task.isCancelled {
                result.notAttempted = Array(videoIds[index...])
                break
            }
            do {
                try await deleteVideo(id: id)
            } catch TAError.notFound {
                // Already gone.
            } catch {
                result.stopError = (error as? TAError) ?? .network(error.localizedDescription)
                result.notAttempted = Array(videoIds[index...])
                break
            }
            result.deleted.append(id)
            await onProgress(result.deleted.count)
        }
        guard !result.deleted.isEmpty else { return result }
        do {
            try await addToDownloadQueue(ids: result.deleted)
            result.queued = true
        } catch {
            result.queueError = (error as? TAError) ?? .network(error.localizedDescription)
        }
        return result
    }
}
