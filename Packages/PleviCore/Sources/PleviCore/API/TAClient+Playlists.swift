
import Foundation

extension TAClient {
    public func playlists(
        page: Int? = nil,
        subscribedOnly: Bool = false,
        type: Endpoint.PlaylistType? = nil,
        channel: String? = nil
    ) async throws -> Paginated<Playlist> {
        try await request(.playlists(page: page, subscribedOnly: subscribedOnly, type: type, channel: channel))
    }

    public func playlist(id: String) async throws -> Playlist {
        try await request(.playlist(id: id))
    }

    public func videos(inPlaylist playlistId: String) async throws -> Paginated<Video> {
        try await request(.videos(VideoListQuery(playlist: playlistId)))
    }

    public func addVideo(_ videoId: String, toPlaylist playlistId: String) async throws {
        try await requestNoContent(.addToCustomPlaylist(playlistId: playlistId, videoId: videoId))
    }
}
