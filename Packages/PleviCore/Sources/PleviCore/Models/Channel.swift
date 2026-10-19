
import Foundation

public struct Channel: Codable, Sendable, Identifiable, Equatable {
    public var channelId: String
    public var channelName: String?
    public var channelDescription: String?
    public var channelSubscribed: Bool?
    public var channelThumbUrl: String?
    public var channelBannerUrl: String?
    public var channelTvartUrl: String?
    public var channelLastRefresh: String?
    public var channelSubs: Int?
    public var channelViews: Int?

    public var id: String { channelId }

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case channelName = "channel_name"
        case channelDescription = "channel_description"
        case channelSubscribed = "channel_subscribed"
        case channelThumbUrl = "channel_thumb_url"
        case channelBannerUrl = "channel_banner_url"
        case channelTvartUrl = "channel_tvart_url"
        case channelLastRefresh = "channel_last_refresh"
        case channelSubs = "channel_subs"
        case channelViews = "channel_views"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelId = try container.decode(String.self, forKey: .channelId)
        channelName = try? container.decodeIfPresent(String.self, forKey: .channelName)
        channelDescription = try? container.decodeIfPresent(String.self, forKey: .channelDescription)
        channelSubscribed = container.decodeFlexibleBoolIfPresent(forKey: .channelSubscribed)
        channelThumbUrl = try? container.decodeIfPresent(String.self, forKey: .channelThumbUrl)
        channelBannerUrl = try? container.decodeIfPresent(String.self, forKey: .channelBannerUrl)
        channelTvartUrl = try? container.decodeIfPresent(String.self, forKey: .channelTvartUrl)
        channelLastRefresh = container.decodeFlexibleStringIfPresent(forKey: .channelLastRefresh)
        channelSubs = container.decodeFlexibleIntIfPresent(forKey: .channelSubs)
        channelViews = container.decodeFlexibleIntIfPresent(forKey: .channelViews)
    }

    public init(
        channelId: String,
        channelName: String? = nil,
        channelDescription: String? = nil,
        channelSubscribed: Bool? = nil,
        channelThumbUrl: String? = nil,
        channelBannerUrl: String? = nil,
        channelTvartUrl: String? = nil,
        channelLastRefresh: String? = nil,
        channelSubs: Int? = nil,
        channelViews: Int? = nil
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.channelDescription = channelDescription
        self.channelSubscribed = channelSubscribed
        self.channelThumbUrl = channelThumbUrl
        self.channelBannerUrl = channelBannerUrl
        self.channelTvartUrl = channelTvartUrl
        self.channelLastRefresh = channelLastRefresh
        self.channelSubs = channelSubs
        self.channelViews = channelViews
    }
}

/// `GET /api/channel/<id>/aggs/` response.
public struct ChannelAggs: Codable, Sendable, Equatable {
    public var totalItems: Int?
    public var totalSize: Int?
    public var totalDuration: Double?

    enum CodingKeys: String, CodingKey {
        case totalItems = "total_items"
        case totalSize = "total_size"
        case totalDuration = "total_duration"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalItems = container.decodeFlexibleIntIfPresent(forKey: .totalItems)
        totalSize = container.decodeFlexibleIntIfPresent(forKey: .totalSize)
        totalDuration = container.decodeFlexibleDoubleIfPresent(forKey: .totalDuration)
    }

    public init(totalItems: Int?, totalSize: Int?, totalDuration: Double?) {
        self.totalItems = totalItems
        self.totalSize = totalSize
        self.totalDuration = totalDuration
    }
}

/// `GET /api/channel/<id>/nav/` response — which sub-tabs exist.
public struct ChannelNav: Codable, Sendable, Equatable {
    public var hasVideos: Bool?
    public var hasStreams: Bool?
    public var hasShorts: Bool?
    public var hasPlaylists: Bool?

    enum CodingKeys: String, CodingKey {
        case hasVideos = "videos"
        case hasStreams = "streams"
        case hasShorts = "shorts"
        case hasPlaylists = "playlists"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasVideos = container.decodeFlexibleBoolIfPresent(forKey: .hasVideos)
        hasStreams = container.decodeFlexibleBoolIfPresent(forKey: .hasStreams)
        hasShorts = container.decodeFlexibleBoolIfPresent(forKey: .hasShorts)
        hasPlaylists = container.decodeFlexibleBoolIfPresent(forKey: .hasPlaylists)
    }

    public init(hasVideos: Bool?, hasStreams: Bool?, hasShorts: Bool?, hasPlaylists: Bool?) {
        self.hasVideos = hasVideos
        self.hasStreams = hasStreams
        self.hasShorts = hasShorts
        self.hasPlaylists = hasPlaylists
    }
}

extension Channel {
    public static let previewChannel = Channel(
        channelId: "preview-channel",
        channelName: "Preview Channel",
        channelDescription: "A short synthetic description used only in SwiftUI previews.",
        channelSubscribed: true,
        channelThumbUrl: nil,
        channelBannerUrl: nil,
        channelTvartUrl: nil,
        channelLastRefresh: "Sep 01, 2026",
        channelSubs: 12_345,
        channelViews: 678_901
    )
}
