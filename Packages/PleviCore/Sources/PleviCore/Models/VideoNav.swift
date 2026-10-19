
import Foundation

/// One playlist's navigation context for the video being viewed.
public struct VideoNavEntry: Codable, Sendable, Equatable {
    public var playlistMeta: PlaylistNavMeta?
    /// `nil` when this video is the first downloaded entry in the playlist —
    /// the server sends an explicit `null` in that case.
    public var playlistPrevious: PlaylistNavVideo?
    /// `nil` when this video is the last downloaded entry in the playlist.
    public var playlistNext: PlaylistNavVideo?

    enum CodingKeys: String, CodingKey {
        case playlistMeta = "playlist_meta"
        case playlistPrevious = "playlist_previous"
        case playlistNext = "playlist_next"
    }

    public init(
        playlistMeta: PlaylistNavMeta? = nil,
        playlistPrevious: PlaylistNavVideo? = nil,
        playlistNext: PlaylistNavVideo? = nil
    ) {
        self.playlistMeta = playlistMeta
        self.playlistPrevious = playlistPrevious
        self.playlistNext = playlistNext
    }
}

/// `playlist_meta`: which playlist this entry describes, and where the
/// currently-viewed video sits inside it.
public struct PlaylistNavMeta: Codable, Sendable, Equatable {
    public var currentIdx: Int?
    public var playlistId: String?
    public var playlistName: String?
    public var playlistChannel: String?

    enum CodingKeys: String, CodingKey {
        case currentIdx = "current_idx"
        case playlistId = "playlist_id"
        case playlistName = "playlist_name"
        case playlistChannel = "playlist_channel"
    }

    public init(
        currentIdx: Int? = nil,
        playlistId: String? = nil,
        playlistName: String? = nil,
        playlistChannel: String? = nil
    ) {
        self.currentIdx = currentIdx
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.playlistChannel = playlistChannel
    }
}

/// `playlist_previous` / `playlist_next`: the neighbouring video itself.
public struct PlaylistNavVideo: Codable, Sendable, Equatable {
    public var youtubeId: String?
    public var title: String?
    public var uploader: String?
    public var idx: Int?
    public var downloaded: Bool?
    public var vidThumb: String?

    enum CodingKeys: String, CodingKey {
        case youtubeId = "youtube_id"
        case title
        case uploader
        case idx
        case downloaded
        case vidThumb = "vid_thumb"
    }

    public init(
        youtubeId: String? = nil,
        title: String? = nil,
        uploader: String? = nil,
        idx: Int? = nil,
        downloaded: Bool? = nil,
        vidThumb: String? = nil
    ) {
        self.youtubeId = youtubeId
        self.title = title
        self.uploader = uploader
        self.idx = idx
        self.downloaded = downloaded
        self.vidThumb = vidThumb
    }
}

/// Body for `POST /api/video/<id>/progress/`.
struct ProgressRequestBody: Encodable, Sendable {
    var position: Double
}

/// Body for `POST /api/watched/`.
struct WatchedRequestBody: Encodable, Sendable {
    var id: String
    var isWatched: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isWatched = "is_watched"
    }
}

/// Body for `POST /api/download/<id>/`.
struct DownloadStatusRequestBody: Encodable, Sendable { var status: String }

/// Body for `POST /api/playlist/<id>/`.
struct CustomPlaylistActionBody: Encodable, Sendable {
    var action: String
    var videoId: String
    enum CodingKeys: String, CodingKey { case action; case videoId = "video_id" }
}
