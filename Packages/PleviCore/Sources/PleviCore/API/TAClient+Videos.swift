
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
}
