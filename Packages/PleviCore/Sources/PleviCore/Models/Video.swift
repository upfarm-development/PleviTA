
import Foundation

public struct Video: Codable, Sendable, Identifiable, Equatable {
    public var youtubeId: String
    public var title: String?
    public var videoDescription: String?
    public var published: String?
    public var dateDownloaded: Double?
    public var vidType: String?
    public var vidThumbUrl: String?
    public var mediaUrl: String?
    public var mediaSize: Int?
    public var active: Bool?
    public var tags: [String]?
    public var category: [String]?
    public var commentCount: Int?
    public var streams: [VideoStream]?
    public var stats: VideoStats?
    public var player: VideoPlayerState?
    public var channel: VideoChannelSummary?
    public var subtitles: [Subtitle]?
    public var playlist: [String]?
    public var sponsorblock: SponsorBlockInfo?

    public var id: String { youtubeId }

    enum CodingKeys: String, CodingKey {
        case youtubeId = "youtube_id"
        case title
        case videoDescription = "description"
        case published
        case dateDownloaded = "date_downloaded"
        case vidType = "vid_type"
        case vidThumbUrl = "vid_thumb_url"
        case mediaUrl = "media_url"
        case mediaSize = "media_size"
        case active
        case tags
        case category
        case commentCount = "comment_count"
        case streams
        case stats
        case player
        case channel
        case subtitles
        case playlist
        case sponsorblock
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        youtubeId = try container.decode(String.self, forKey: .youtubeId)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        videoDescription = try? container.decodeIfPresent(String.self, forKey: .videoDescription)
        published = container.decodeFlexibleStringIfPresent(forKey: .published)
        dateDownloaded = container.decodeFlexibleDoubleIfPresent(forKey: .dateDownloaded)
        vidType = try? container.decodeIfPresent(String.self, forKey: .vidType)
        vidThumbUrl = try? container.decodeIfPresent(String.self, forKey: .vidThumbUrl)
        mediaUrl = try? container.decodeIfPresent(String.self, forKey: .mediaUrl)
        mediaSize = container.decodeFlexibleIntIfPresent(forKey: .mediaSize)
        active = container.decodeFlexibleBoolIfPresent(forKey: .active)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
        category = try? container.decodeIfPresent([String].self, forKey: .category)
        commentCount = container.decodeFlexibleIntIfPresent(forKey: .commentCount)
        streams = try? container.decodeIfPresent([VideoStream].self, forKey: .streams)
        stats = try? container.decodeIfPresent(VideoStats.self, forKey: .stats)
        player = try? container.decodeIfPresent(VideoPlayerState.self, forKey: .player)
        channel = try? container.decodeIfPresent(VideoChannelSummary.self, forKey: .channel)
        subtitles = try? container.decodeIfPresent([Subtitle].self, forKey: .subtitles)
        playlist = try? container.decodeIfPresent([String].self, forKey: .playlist)
        sponsorblock = try? container.decodeIfPresent(SponsorBlockInfo.self, forKey: .sponsorblock)
    }

    public init(
        youtubeId: String,
        title: String? = nil,
        videoDescription: String? = nil,
        published: String? = nil,
        dateDownloaded: Double? = nil,
        vidType: String? = nil,
        vidThumbUrl: String? = nil,
        mediaUrl: String? = nil,
        mediaSize: Int? = nil,
        active: Bool? = nil,
        tags: [String]? = nil,
        category: [String]? = nil,
        commentCount: Int? = nil,
        streams: [VideoStream]? = nil,
        stats: VideoStats? = nil,
        player: VideoPlayerState? = nil,
        channel: VideoChannelSummary? = nil,
        subtitles: [Subtitle]? = nil,
        playlist: [String]? = nil,
        sponsorblock: SponsorBlockInfo? = nil
    ) {
        self.youtubeId = youtubeId
        self.title = title
        self.videoDescription = videoDescription
        self.published = published
        self.dateDownloaded = dateDownloaded
        self.vidType = vidType
        self.vidThumbUrl = vidThumbUrl
        self.mediaUrl = mediaUrl
        self.mediaSize = mediaSize
        self.active = active
        self.tags = tags
        self.category = category
        self.commentCount = commentCount
        self.streams = streams
        self.stats = stats
        self.player = player
        self.channel = channel
        self.subtitles = subtitles
        self.playlist = playlist
        self.sponsorblock = sponsorblock
    }
}

public struct VideoStream: Codable, Sendable, Equatable {
    public var type: String?
    public var codec: String?
    public var width: Int?
    public var height: Int?
    public var bitrate: Int?

    public init(type: String?, codec: String?, width: Int?, height: Int?, bitrate: Int?) {
        self.type = type
        self.codec = codec
        self.width = width
        self.height = height
        self.bitrate = bitrate
    }
}

public struct VideoStats: Codable, Sendable, Equatable {
    public var viewCount: Int?
    public var likeCount: Int?
    public var dislikeCount: Int?
    public var averageRating: Double?

    enum CodingKeys: String, CodingKey {
        case viewCount = "view_count"
        case likeCount = "like_count"
        case dislikeCount = "dislike_count"
        case averageRating = "average_rating"
    }

    public init(viewCount: Int?, likeCount: Int?, dislikeCount: Int?, averageRating: Double?) {
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.dislikeCount = dislikeCount
        self.averageRating = averageRating
    }
}

/// `player { duration, duration_str, watched, position?, progress? }`.
public struct VideoPlayerState: Codable, Sendable, Equatable {
    public var duration: Double?
    public var durationStr: String?
    public var watched: Bool?
    public var position: Double?
    public var progress: Double?

    enum CodingKeys: String, CodingKey {
        case duration
        case durationStr = "duration_str"
        case watched
        case position
        case progress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = container.decodeFlexibleDoubleIfPresent(forKey: .duration)
        durationStr = try? container.decodeIfPresent(String.self, forKey: .durationStr)
        watched = container.decodeFlexibleBoolIfPresent(forKey: .watched)
        position = container.decodeFlexibleDoubleIfPresent(forKey: .position)
        progress = container.decodeFlexibleDoubleIfPresent(forKey: .progress)
    }

    public init(
        duration: Double?,
        durationStr: String?,
        watched: Bool?,
        position: Double?,
        progress: Double?
    ) {
        self.duration = duration
        self.durationStr = durationStr
        self.watched = watched
        self.position = position
        self.progress = progress
    }
}

/// The `channel` object embedded in a video document.
public struct VideoChannelSummary: Codable, Sendable, Equatable {
    public var channelId: String?
    public var channelName: String?
    public var channelThumbUrl: String?
    public var channelBannerUrl: String?
    public var channelTvartUrl: String?
    public var channelSubscribed: Bool?
    public var channelDescription: String?
    public var channelLastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case channelName = "channel_name"
        case channelThumbUrl = "channel_thumb_url"
        case channelBannerUrl = "channel_banner_url"
        case channelTvartUrl = "channel_tvart_url"
        case channelSubscribed = "channel_subscribed"
        case channelDescription = "channel_description"
        case channelLastRefresh = "channel_last_refresh"
    }

    public init(
        channelId: String?,
        channelName: String?,
        channelThumbUrl: String?,
        channelBannerUrl: String?,
        channelTvartUrl: String?,
        channelSubscribed: Bool?,
        channelDescription: String?,
        channelLastRefresh: String?
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.channelThumbUrl = channelThumbUrl
        self.channelBannerUrl = channelBannerUrl
        self.channelTvartUrl = channelTvartUrl
        self.channelSubscribed = channelSubscribed
        self.channelDescription = channelDescription
        self.channelLastRefresh = channelLastRefresh
    }
}

public struct Subtitle: Codable, Sendable, Equatable {
    public var name: String?
    public var lang: String?
    public var mediaUrl: String?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case name
        case lang
        case mediaUrl = "media_url"
        case source
    }

    public init(name: String?, lang: String?, mediaUrl: String?, source: String?) {
        self.name = name
        self.lang = lang
        self.mediaUrl = mediaUrl
        self.source = source
    }
}

/// `sponsorblock` on the video document.
public struct SponsorBlockInfo: Codable, Sendable, Equatable {
    public var isEnabled: Bool?
    /// TA only ever writes `true`, in current and legacy TA code. A disabled integration shows
    /// up as this whole object being *absent* from the video document, never as `false` here.
    public var lastRefresh: Int?
    /// TA computes this as `not any(segment.locked)`, so despite the name it means "no segment
    /// here is locked". Genuinely absent (not `false`) in the empty-segments case — confirmed
    /// live.
    public var hasUnlocked: Bool?
    public var segments: [SponsorBlockSegment]

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled", lastRefresh = "last_refresh"
        case hasUnlocked = "has_unlocked", segments
    }

    public init(
        isEnabled: Bool? = nil,
        lastRefresh: Int? = nil,
        hasUnlocked: Bool? = nil,
        segments: [SponsorBlockSegment] = []
    ) {
        self.isEnabled = isEnabled
        self.lastRefresh = lastRefresh
        self.hasUnlocked = hasUnlocked
        self.segments = segments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)
        lastRefresh = try? c.decodeIfPresent(Int.self, forKey: .lastRefresh)
        hasUnlocked = try? c.decodeIfPresent(Bool.self, forKey: .hasUnlocked)
        segments = (try? c.decodeIfPresent([SponsorBlockSegment].self, forKey: .segments)) ?? []
    }
}

/// One SponsorBlock segment, as TA stores it.
public struct SponsorBlockSegment: Codable, Sendable, Equatable {
    /// Uppercase `UUID` on the wire; renamed here because it collides with Swift's `UUID` type.
    /// Confirmed live to be a long hex string, not a dashed 36-character UUID — treated as an
    /// opaque `String`, never parsed as `Foundation.UUID`.
    public var segmentID: String?
    public var category: String?
    /// TA overwrites SponsorBlock's own value: `"skip"` for `category == "sponsor"`, the literal `"none"` for every other category.
    public var actionType: String?
    /// Two-element `[start, end]` in seconds. NOT `startTime`/`endTime` keys.
    public var segment: [Double]?
    /// Per-segment, recorded at submission time — NOT the video's own length.
    public var videoDuration: Double?
    public var votes: Int?
    /// Integer 0/1 on the wire, not a bool.
    public var locked: Int?

    enum CodingKeys: String, CodingKey {
        case segmentID = "UUID"
        case category, actionType, segment, videoDuration, votes, locked
    }

    public var start: Double? { segment?.count == 2 ? segment?[0] : nil }
    public var end: Double? { segment?.count == 2 ? segment?[1] : nil }

    public init(
        segmentID: String? = nil,
        category: String? = nil,
        actionType: String? = nil,
        segment: [Double]? = nil,
        videoDuration: Double? = nil,
        votes: Int? = nil,
        locked: Int? = nil
    ) {
        self.segmentID = segmentID
        self.category = category
        self.actionType = actionType
        self.segment = segment
        self.videoDuration = videoDuration
        self.votes = votes
        self.locked = locked
    }
}

public typealias VideoProgressResponse = VideoPlayerState

extension Video {
    public static let previewVideo = Video(
        youtubeId: "preview000001",
        title: "A Sample Video Title That Runs Long Enough To Wrap",
        videoDescription: "A short synthetic description used only in SwiftUI previews.",
        published: "Sep 01, 2026",
        dateDownloaded: 1_756_684_800,
        vidType: "videos",
        vidThumbUrl: nil,
        mediaUrl: nil,
        mediaSize: 55_000_000,
        active: true,
        tags: [],
        category: [],
        commentCount: 0,
        streams: nil,
        stats: VideoStats(viewCount: 1234, likeCount: 88, dislikeCount: 0, averageRating: 4.6),
        player: VideoPlayerState(duration: 754, durationStr: "12:34", watched: false, position: 300, progress: 40),
        channel: VideoChannelSummary(
            channelId: "preview-channel",
            channelName: "Preview Channel",
            channelThumbUrl: nil,
            channelBannerUrl: nil,
            channelTvartUrl: nil,
            channelSubscribed: true,
            channelDescription: nil,
            channelLastRefresh: nil
        ),
        subtitles: [],
        playlist: [],
        sponsorblock: nil
    )
}
