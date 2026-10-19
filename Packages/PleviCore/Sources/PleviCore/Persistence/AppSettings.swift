// UserDefaults-backed, `@Observable`.

import Foundation
import Observation

public enum WatchedFilterScope: String, CaseIterable, Sendable, Hashable {
    /// Home's own grid.
    case home
    /// A channel's Videos/Streams/Shorts grid.
    case channelVideos
    /// A playlist's entry list, and the pager built from it on the video screen.
    case playlistEntries
}

public enum HomeSortField: String, CaseIterable, Sendable, Codable {
    case published
    case downloaded

    /// Display title shared by every sort menu that offers this field
    /// (Home, and independently a channel's own video grid).
    public var title: String {
        switch self {
        case .published: "Date Published"
        case .downloaded: "Date Added"
        }
    }
}

public enum HomeSortOrder: String, CaseIterable, Sendable, Codable {
    case asc
    case desc
}

public enum VideoTypeFilter: String, CaseIterable, Sendable, Codable {
    case videos
    case streams
    case shorts
}

public enum PlaylistsSortField: String, CaseIterable, Sendable, Codable {
    case name
    case channel

    public var title: String {
        switch self {
        case .name: "Name"
        case .channel: "Channel"
        }
    }
}

public enum PlaylistEntrySortField: String, CaseIterable, Sendable, Codable {
    case playlistOrder
    case title
    case datePublished

    public var menuTitle: String {
        switch self {
        case .playlistOrder: "Playlist Order"
        case .title: "Title"
        case .datePublished: "Date Published"
        }
    }
}

public enum ViewStyle: String, CaseIterable, Sendable, Codable {
    case grid
    case list
}

public enum SearchResultSection: String, CaseIterable, Sendable, Codable, Identifiable {
    case video
    case channel
    case playlist

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .video: "Videos"
        case .channel: "Channels"
        case .playlist: "Playlists"
        }
    }
}

/// Continue Watching's carousel-vs-list display, kept distinct from the existing `ViewStyle` (grid/list) enum used elsewhere.
public enum ContinueWatchingStyle: String, CaseIterable, Sendable, Codable {
    case carousel
    case list
}

@Observable
@MainActor
public final class AppSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let homeSortField = "settings.homeSortField"
        static let homeSortOrder = "settings.homeSortOrder"
        static let hideWatched = "settings.hideWatched"
        static let channelsSubscribedOnly = "settings.channelsSubscribedOnly"
        static let playlistsSubscribedOnly = "settings.playlistsSubscribedOnly"
        static let autoPlayNext = "settings.autoPlayNext"
        static let videoTypeFilter = "settings.videoTypeFilter"
        static let seededFromServer = "settings.seededFromServer"
        static let homeViewStyle = "settings.homeViewStyle"
        static let channelsViewStyle = "settings.channelsViewStyle"
        static let playlistsViewStyle = "settings.playlistsViewStyle"
        static let playlistsSortField = "settings.playlistsSortField"
        static let playlistsSortOrder = "settings.playlistsSortOrder"
        static let channelVideoSortField = "settings.channelVideoSortField"
        static let channelVideoSortOrder = "settings.channelVideoSortOrder"
        static let playlistDetailSortField = "settings.playlistDetailSortField"
        static let playlistDetailSortOrder = "settings.playlistDetailSortOrder"
        static let searchResultsOrder = "settings.searchResultsOrder"
        static let playlistNavSkipWatched = "settings.playlistNavSkipWatched"
        static let appTheme = "settings.appTheme"
        static let continueWatchingStyle = "settings.continueWatchingStyle"
        static let fallbackPlayerMode = "settings.fallbackPlayerMode"
        static let recentlyPlayedFirst = "settings.recentlyPlayedFirst"
        static let resumeBehavior = "settings.resumeBehavior"
        static let sponsorBlockEnabled = "settings.sponsorBlockEnabled"
        /// Set once the old SponsorBlock master switch has been folded into the categories.
        static let sponsorBlockSwitchRetired = "settings.sponsorBlockSwitchRetired"
        static let sponsorBlockCategories = "settings.sponsorBlockCategories"
        static let allowCellularDownloads = "settings.allowCellularDownloads"
        static let artworkCacheLimitMB = "settings.artworkCacheLimitMB"
    }

    /// Today's implicit, unchanged order for anyone who never touches the
    /// new "Search" Settings section.
    public static let defaultSearchResultsOrder: [SearchResultSection] = [.video, .channel, .playlist]

    /// The video-detail screen's section order.
    public static let videoDetailSectionOrder: [VideoDetailSection] = [
        .stats, .actions, .fileDetails, .description, .inThisPlaylist, .comments, .similarVideos
    ]

    public var homeSortField: HomeSortField {
        didSet { defaults.set(homeSortField.rawValue, forKey: Key.homeSortField) }
    }

    public var homeSortOrder: HomeSortOrder {
        didSet { defaults.set(homeSortOrder.rawValue, forKey: Key.homeSortOrder) }
    }

    /// The app-wide default, persisted, and what Settings' own "Hide watched videos" toggle writes.
    public var hideWatched: Bool {
        didSet {
            defaults.set(hideWatched, forKey: Key.hideWatched)
            sessionHideWatched.removeAll()
        }
    }

    /// Per-screen overrides of `hideWatched`, deliberately NOT persisted.
    private var sessionHideWatched: [WatchedFilterScope: Bool] = [:]

    /// The value a screen should actually filter by: its own override if it has one this
    /// session, otherwise the persisted default.
    public func hideWatched(in scope: WatchedFilterScope) -> Bool {
        sessionHideWatched[scope] ?? hideWatched
    }

    /// Sets one screen's override for this session only. Never touches `hideWatched`, so
    /// nothing here survives a relaunch or leaks into another screen.
    public func setHideWatched(_ newValue: Bool, in scope: WatchedFilterScope) {
        sessionHideWatched[scope] = newValue
    }

    public var channelsSubscribedOnly: Bool {
        didSet { defaults.set(channelsSubscribedOnly, forKey: Key.channelsSubscribedOnly) }
    }

    public var playlistsSubscribedOnly: Bool {
        didSet { defaults.set(playlistsSubscribedOnly, forKey: Key.playlistsSubscribedOnly) }
    }

    public var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: Key.autoPlayNext) }
    }

    public var videoTypeFilter: VideoTypeFilter? {
        didSet { defaults.set(videoTypeFilter?.rawValue, forKey: Key.videoTypeFilter) }
    }

    public var homeViewStyle: ViewStyle {
        didSet { defaults.set(homeViewStyle.rawValue, forKey: Key.homeViewStyle) }
    }

    public var channelsViewStyle: ViewStyle {
        didSet { defaults.set(channelsViewStyle.rawValue, forKey: Key.channelsViewStyle) }
    }

    public var playlistsViewStyle: ViewStyle {
        didSet { defaults.set(playlistsViewStyle.rawValue, forKey: Key.playlistsViewStyle) }
    }

    /// `PlaylistsView`'s sort control — sorts the loaded playlist list
    /// client-side (no server-side sort param exists for `/api/playlist/`,
    /// confirmed against `Endpoint.playlists`/`TAClient+Playlists.swift`).
    public var playlistsSortField: PlaylistsSortField {
        didSet { defaults.set(playlistsSortField.rawValue, forKey: Key.playlistsSortField) }
    }

    public var playlistsSortOrder: HomeSortOrder {
        didSet { defaults.set(playlistsSortOrder.rawValue, forKey: Key.playlistsSortOrder) }
    }

    public var channelVideoSortField: HomeSortField {
        didSet { defaults.set(channelVideoSortField.rawValue, forKey: Key.channelVideoSortField) }
    }

    public var channelVideoSortOrder: HomeSortOrder {
        didSet { defaults.set(channelVideoSortOrder.rawValue, forKey: Key.channelVideoSortOrder) }
    }

    /// `PlaylistDetailView`'s entry-list sort — a client-side re-sort of the
    /// already-loaded `downloadedEntries` (no new API calls).
    public var playlistDetailSortField: PlaylistEntrySortField {
        didSet { defaults.set(playlistDetailSortField.rawValue, forKey: Key.playlistDetailSortField) }
    }

    public var playlistDetailSortOrder: HomeSortOrder {
        didSet { defaults.set(playlistDetailSortOrder.rawValue, forKey: Key.playlistDetailSortOrder) }
    }

    /// `SearchView`'s section order (Videos/Channels/Playlists), reorderable from a new "Search" section in Settings.
    public var searchResultsOrder: [SearchResultSection] {
        didSet { defaults.set(searchResultsOrder.map(\.rawValue), forKey: Key.searchResultsOrder) }
    }

    public var playlistNavSkipWatched: Bool {
        didSet { defaults.set(playlistNavSkipWatched, forKey: Key.playlistNavSkipWatched) }
    }

    /// iOS/iPadOS only (see `AppTheme`) — tvOS never shows the control and
    /// keeps following the system appearance.
    public var appTheme: AppTheme {
        didSet { defaults.set(appTheme.rawValue, forKey: Key.appTheme) }
    }

    /// Continue Watching's carousel-vs-list display — see `ContinueWatchingStyle`'s own doc comment for why this isn't just `ViewStyle` again.
    public var continueWatchingStyle: ContinueWatchingStyle {
        didSet { defaults.set(continueWatchingStyle.rawValue, forKey: Key.continueWatchingStyle) }
    }

    public var fallbackPlayerMode: FallbackPlayerMode {
        didSet { defaults.set(fallbackPlayerMode.rawValue, forKey: Key.fallbackPlayerMode) }
    }

    public var recentlyPlayedFirst: Bool {
        didSet { defaults.set(recentlyPlayedFirst, forKey: Key.recentlyPlayedFirst) }
    }

    /// Settings → Playback → "Resuming videos". Whether a manual Play tap on a video with a
    /// saved position resumes silently or asks first. Per-device (`AppSettings` is device-local
    /// `UserDefaults`, no iCloud sync) — you may want the prompt on the TV and not on the phone.
    public var resumeBehavior: ResumeBehavior {
        didSet { defaults.set(resumeBehavior.rawValue, forKey: Key.resumeBehavior) }
    }

    /// Whether anything is skipped: true when at least one SponsorBlock category is selected.
    public var sponsorBlockEnabled: Bool { !sponsorBlockCategories.isEmpty }

    public var sponsorBlockCategories: Set<SponsorCategory> {
        didSet { defaults.set(sponsorBlockCategories.map(\.rawValue).sorted(), forKey: Key.sponsorBlockCategories) }
    }

    public var allowCellularDownloads: Bool {
        didSet { defaults.set(allowCellularDownloads, forKey: Key.allowCellularDownloads) }
    }

    /// Settings → Storage → "Artwork cache": the most disk the on-disk artwork cache
    /// (`ArtworkDiskCache`) may use, in megabytes. The least recently used images go first once
    /// it is over.
    public static let artworkCacheLimitChoicesMB = [100, 250, 500, 1000, 2000]
    public var artworkCacheLimitMB: Int {
        didSet { defaults.set(artworkCacheLimitMB, forKey: Key.artworkCacheLimitMB) }
    }
    public var artworkCacheLimitBytes: Int { artworkCacheLimitMB * 1_000_000 }

    /// The saved "Allow cellular downloads" value, without constructing an `AppSettings`.
    nonisolated public static func persistedAllowCellularDownloads(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Key.allowCellularDownloads) as? Bool ?? false
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeSortField = HomeSortField(rawValue: defaults.string(forKey: Key.homeSortField) ?? "") ?? .downloaded
        homeSortOrder = HomeSortOrder(rawValue: defaults.string(forKey: Key.homeSortOrder) ?? "") ?? .desc
        hideWatched = defaults.object(forKey: Key.hideWatched) as? Bool ?? false
        channelsSubscribedOnly = defaults.object(forKey: Key.channelsSubscribedOnly) as? Bool ?? false
        playlistsSubscribedOnly = defaults.object(forKey: Key.playlistsSubscribedOnly) as? Bool ?? false
        autoPlayNext = defaults.object(forKey: Key.autoPlayNext) as? Bool ?? true
        recentlyPlayedFirst = defaults.object(forKey: Key.recentlyPlayedFirst) as? Bool ?? true
        videoTypeFilter = (defaults.string(forKey: Key.videoTypeFilter)).flatMap(VideoTypeFilter.init(rawValue:))
        homeViewStyle = ViewStyle(rawValue: defaults.string(forKey: Key.homeViewStyle) ?? "") ?? .grid
        channelsViewStyle = ViewStyle(rawValue: defaults.string(forKey: Key.channelsViewStyle) ?? "") ?? .grid
        playlistsViewStyle = ViewStyle(rawValue: defaults.string(forKey: Key.playlistsViewStyle) ?? "") ?? .grid
        playlistsSortField = PlaylistsSortField(rawValue: defaults.string(forKey: Key.playlistsSortField) ?? "") ?? .name
        playlistsSortOrder = HomeSortOrder(rawValue: defaults.string(forKey: Key.playlistsSortOrder) ?? "") ?? .asc
        channelVideoSortField = HomeSortField(rawValue: defaults.string(forKey: Key.channelVideoSortField) ?? "") ?? .downloaded
        channelVideoSortOrder = HomeSortOrder(rawValue: defaults.string(forKey: Key.channelVideoSortOrder) ?? "") ?? .desc
        playlistDetailSortField = PlaylistEntrySortField(rawValue: defaults.string(forKey: Key.playlistDetailSortField) ?? "") ?? .playlistOrder
        playlistDetailSortOrder = HomeSortOrder(rawValue: defaults.string(forKey: Key.playlistDetailSortOrder) ?? "") ?? .asc
        playlistNavSkipWatched = defaults.object(forKey: Key.playlistNavSkipWatched) as? Bool ?? true
        appTheme = AppTheme(rawValue: defaults.string(forKey: Key.appTheme) ?? "") ?? .system
        continueWatchingStyle = ContinueWatchingStyle(rawValue: defaults.string(forKey: Key.continueWatchingStyle) ?? "") ?? .carousel
        fallbackPlayerMode = FallbackPlayerMode(rawValue: defaults.string(forKey: Key.fallbackPlayerMode) ?? "") ?? .automatic
        resumeBehavior = ResumeBehavior(rawValue: defaults.string(forKey: Key.resumeBehavior) ?? "") ?? .alwaysResume
        // `object(forKey:)` first, not `bool(forKey:)` alone: `bool` returns false for a missing key, which is the same as the default here.
        allowCellularDownloads = defaults.object(forKey: Key.allowCellularDownloads) as? Bool ?? false
        artworkCacheLimitMB = defaults.object(forKey: Key.artworkCacheLimitMB) as? Int ?? 500
        // Categories are the whole setting now.
        let storedCategories = defaults.array(forKey: Key.sponsorBlockCategories) as? [String]
        var categories: Set<SponsorCategory>
        if defaults.bool(forKey: Key.sponsorBlockSwitchRetired) {
            categories = Set((storedCategories ?? []).compactMap(SponsorCategory.init(rawValue:)))
        } else {
            let wasOn = defaults.object(forKey: Key.sponsorBlockEnabled) as? Bool ?? false
            if wasOn {
                categories = storedCategories.map { Set($0.compactMap(SponsorCategory.init(rawValue:))) }
                    ?? SponsorBlockPolicy.defaultCategories
            } else {
                categories = []
            }
            defaults.set(categories.map(\.rawValue).sorted(), forKey: Key.sponsorBlockCategories)
            defaults.set(true, forKey: Key.sponsorBlockSwitchRetired)
        }
        sponsorBlockCategories = categories

        // A stored order only counts if it's a genuine reordering of all three cases.
        let storedSearchResultsOrder = (defaults.array(forKey: Key.searchResultsOrder) as? [String])?
            .compactMap(SearchResultSection.init(rawValue:))
        if let storedSearchResultsOrder, Set(storedSearchResultsOrder) == Set(SearchResultSection.allCases) {
            searchResultsOrder = storedSearchResultsOrder
        } else {
            searchResultsOrder = Self.defaultSearchResultsOrder
        }
    }

    public func seedFromServerIfNeeded(_ config: UserConfig) {
        guard !defaults.bool(forKey: Key.seededFromServer) else { return }
        if let hideWatchedFromServer = config.hideWatched {
            hideWatched = hideWatchedFromServer
        }
        if let subedOnly = config.showSubedOnly {
            channelsSubscribedOnly = subedOnly
        }
        if let subedOnlyPlaylists = config.showSubedOnlyPlaylists {
            playlistsSubscribedOnly = subedOnlyPlaylists
        }
        defaults.set(true, forKey: Key.seededFromServer)
    }

    /// Resets the "seeded from server" flag so the next login seeds again.
    /// Called on sign-out so a different server/account's config isn't
    /// masked by the previous account's local overrides.
    public func resetServerSeed() {
        defaults.set(false, forKey: Key.seededFromServer)
    }
}
