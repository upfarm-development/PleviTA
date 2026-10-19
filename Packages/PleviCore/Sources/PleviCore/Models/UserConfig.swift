
import Foundation

public struct UserConfig: Codable, Sendable, Equatable {
    public var pageSize: Int?
    public var sortBy: String?
    public var sortOrder: String?
    public var hideWatched: Bool?
    public var hideWatchedChannel: Bool?
    public var hideWatchedPlaylist: Bool?
    public var vidTypeFilter: String?
    public var showSubedOnly: Bool?
    public var showSubedOnlyPlaylists: Bool?
    public var gridItems: Int?
    public var viewStyleHome: String?
    public var viewStyleChannel: String?
    public var viewStylePlaylist: String?
    public var viewStyleDownloads: String?
    public var stylesheet: String?
    public var fileSizeUnit: String?
    public var showIgnoredOnly: Bool?
    public var showHelpText: Bool?

    enum CodingKeys: String, CodingKey {
        case pageSize = "page_size"
        case sortBy = "sort_by"
        case sortOrder = "sort_order"
        case hideWatched = "hide_watched"
        case hideWatchedChannel = "hide_watched_channel"
        case hideWatchedPlaylist = "hide_watched_playlist"
        case vidTypeFilter = "vid_type_filter"
        case showSubedOnly = "show_subed_only"
        case showSubedOnlyPlaylists = "show_subed_only_playlists"
        case gridItems = "grid_items"
        case viewStyleHome = "view_style_home"
        case viewStyleChannel = "view_style_channel"
        case viewStylePlaylist = "view_style_playlist"
        case viewStyleDownloads = "view_style_downloads"
        case stylesheet
        case fileSizeUnit = "file_size_unit"
        case showIgnoredOnly = "show_ignored_only"
        case showHelpText = "show_help_text"
    }

    public init(
        pageSize: Int? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        hideWatched: Bool? = nil,
        hideWatchedChannel: Bool? = nil,
        hideWatchedPlaylist: Bool? = nil,
        vidTypeFilter: String? = nil,
        showSubedOnly: Bool? = nil,
        showSubedOnlyPlaylists: Bool? = nil,
        gridItems: Int? = nil,
        viewStyleHome: String? = nil,
        viewStyleChannel: String? = nil,
        viewStylePlaylist: String? = nil,
        viewStyleDownloads: String? = nil,
        stylesheet: String? = nil,
        fileSizeUnit: String? = nil,
        showIgnoredOnly: Bool? = nil,
        showHelpText: Bool? = nil
    ) {
        self.pageSize = pageSize
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.hideWatched = hideWatched
        self.hideWatchedChannel = hideWatchedChannel
        self.hideWatchedPlaylist = hideWatchedPlaylist
        self.vidTypeFilter = vidTypeFilter
        self.showSubedOnly = showSubedOnly
        self.showSubedOnlyPlaylists = showSubedOnlyPlaylists
        self.gridItems = gridItems
        self.viewStyleHome = viewStyleHome
        self.viewStyleChannel = viewStyleChannel
        self.viewStylePlaylist = viewStylePlaylist
        self.viewStyleDownloads = viewStyleDownloads
        self.stylesheet = stylesheet
        self.fileSizeUnit = fileSizeUnit
        self.showIgnoredOnly = showIgnoredOnly
        self.showHelpText = showHelpText
    }
}
