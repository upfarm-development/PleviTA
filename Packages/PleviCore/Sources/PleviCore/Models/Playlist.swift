
import Foundation

public struct Playlist: Codable, Sendable, Identifiable, Equatable {
    public var playlistId: String
    public var playlistName: String?
    public var playlistChannel: String?
    public var playlistChannelId: String?
    public var playlistDescription: String?
    public var playlistThumbnail: String?
    public var playlistSubscribed: Bool?
    public var playlistType: String?
    public var playlistSortOrder: String?
    public var playlistEntries: [PlaylistEntry]?

    public var id: String { playlistId }

    enum CodingKeys: String, CodingKey {
        case playlistId = "playlist_id"
        case playlistName = "playlist_name"
        case playlistChannel = "playlist_channel"
        case playlistChannelId = "playlist_channel_id"
        case playlistDescription = "playlist_description"
        case playlistThumbnail = "playlist_thumbnail"
        case playlistSubscribed = "playlist_subscribed"
        case playlistType = "playlist_type"
        case playlistSortOrder = "playlist_sort_order"
        case playlistEntries = "playlist_entries"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playlistId = try container.decode(String.self, forKey: .playlistId)
        playlistName = try? container.decodeIfPresent(String.self, forKey: .playlistName)
        playlistChannel = try? container.decodeIfPresent(String.self, forKey: .playlistChannel)
        playlistChannelId = try? container.decodeIfPresent(String.self, forKey: .playlistChannelId)
        playlistDescription = Self.sanitizedDescription(try? container.decodeIfPresent(String.self, forKey: .playlistDescription))
        playlistThumbnail = try? container.decodeIfPresent(String.self, forKey: .playlistThumbnail)
        playlistSubscribed = container.decodeFlexibleBoolIfPresent(forKey: .playlistSubscribed)
        playlistType = try? container.decodeIfPresent(String.self, forKey: .playlistType)
        playlistSortOrder = try? container.decodeIfPresent(String.self, forKey: .playlistSortOrder)
        playlistEntries = try? container.decodeIfPresent([PlaylistEntry].self, forKey: .playlistEntries)
    }

    public init(
        playlistId: String,
        playlistName: String? = nil,
        playlistChannel: String? = nil,
        playlistChannelId: String? = nil,
        playlistDescription: String? = nil,
        playlistThumbnail: String? = nil,
        playlistSubscribed: Bool? = nil,
        playlistType: String? = nil,
        playlistSortOrder: String? = nil,
        playlistEntries: [PlaylistEntry]? = nil
    ) {
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.playlistChannel = playlistChannel
        self.playlistChannelId = playlistChannelId
        self.playlistDescription = playlistDescription
        self.playlistThumbnail = playlistThumbnail
        self.playlistSubscribed = playlistSubscribed
        self.playlistType = playlistType
        self.playlistSortOrder = playlistSortOrder
        self.playlistEntries = playlistEntries
    }

    private static func sanitizedDescription(_ raw: String?) -> String? {
        raw == "False" ? nil : raw
    }
}

public struct PlaylistEntry: Codable, Sendable, Identifiable, Equatable {
    public var youtubeId: String
    public var title: String?
    public var uploader: String?
    public var idx: Int?
    public var downloaded: Bool?

    public var id: String { youtubeId }

    enum CodingKeys: String, CodingKey {
        case youtubeId = "youtube_id"
        case title
        case uploader
        case idx
        case downloaded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        youtubeId = try container.decode(String.self, forKey: .youtubeId)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        uploader = try? container.decodeIfPresent(String.self, forKey: .uploader)
        idx = container.decodeFlexibleIntIfPresent(forKey: .idx)
        downloaded = container.decodeFlexibleBoolIfPresent(forKey: .downloaded)
    }

    public init(youtubeId: String, title: String?, uploader: String?, idx: Int?, downloaded: Bool?) {
        self.youtubeId = youtubeId
        self.title = title
        self.uploader = uploader
        self.idx = idx
        self.downloaded = downloaded
    }
}

extension Playlist {
    public static let previewPlaylist = Playlist(
        playlistId: "preview-playlist",
        playlistName: "A Sample Playlist With A Longer Name",
        playlistChannel: "Preview Channel",
        playlistChannelId: "preview-channel",
        playlistDescription: "A short synthetic description used only in SwiftUI previews.",
        playlistThumbnail: nil,
        playlistSubscribed: true,
        playlistType: "regular",
        playlistSortOrder: "playlist",
        playlistEntries: [
            PlaylistEntry(youtubeId: "preview000001", title: "Preview Entry One", uploader: "Preview Channel", idx: 0, downloaded: true),
            PlaylistEntry(youtubeId: "preview000002", title: "Preview Entry Two", uploader: "Preview Channel", idx: 1, downloaded: true)
        ]
    )
}
