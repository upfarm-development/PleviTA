
import Foundation
import Observation

public enum ChannelSubTab: String, CaseIterable, Sendable, Identifiable, Hashable {
    case videos, streams, shorts, playlists
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .videos: "Videos"
        case .streams: "Streams"
        case .shorts: "Shorts"
        case .playlists: "Playlists"
        }
    }

    /// Whether this tab shows the channel's own video grid, and is therefore affected by `channelVideoSortField`/`channelVideoSortOrder`.
    public var isVideoGrid: Bool {
        switch self {
        case .videos, .streams, .shorts: true
        case .playlists: false
        }
    }
}

@Observable
@MainActor
public final class ChannelDetailStore {
    public let channelId: String

    public private(set) var channelState: LoadState<Channel> = .idle
    public private(set) var aggsState: LoadState<ChannelAggs> = .idle
    public private(set) var navState: LoadState<ChannelNav> = .idle
    /// The sub-tabs to actually show, derived from `navState` by
    /// `resolveTabs`. Starts as just `.videos` so the UI has something
    /// sensible to render before `/nav/` returns.
    public private(set) var availableTabs: [ChannelSubTab] = [.videos]

    public let videosGrid: ChannelVideoGridStore
    public let streamsGrid: ChannelVideoGridStore
    public let shortsGrid: ChannelVideoGridStore

    public private(set) var playlistsState: LoadState<[Playlist]> = .idle
    private var didLoadPlaylists = false

    public var isMarkingAllWatched = false
    public var markAllWatchedError: TAError?

    private let client: TAClient

    public init(client: TAClient, appSettings: AppSettings, channelId: String) {
        self.client = client
        self.channelId = channelId
        videosGrid = ChannelVideoGridStore(client: client, appSettings: appSettings, channelId: channelId, videoType: .videos)
        streamsGrid = ChannelVideoGridStore(client: client, appSettings: appSettings, channelId: channelId, videoType: .streams)
        shortsGrid = ChannelVideoGridStore(client: client, appSettings: appSettings, channelId: channelId, videoType: .shorts)
    }

    public var channel: Channel? { channelState.value }

    /// Loads the channel document, aggregates, and nav concurrently.
    public func loadHeader() async {
        async let channelLoad: Void = loadChannel()
        async let aggsLoad: Void = loadAggs()
        async let navLoad: Void = loadNav()
        _ = await (channelLoad, aggsLoad, navLoad)
    }

    public func loadChannel() async {
        channelState = .loading
        do {
            let channel = try await client.channel(id: channelId)
            channelState = .loaded(channel)
        } catch {
            channelState = .failed(Self.taError(error))
        }
    }

    public func loadAggs() async {
        aggsState = .loading
        do {
            let aggs = try await client.channelAggs(id: channelId)
            aggsState = .loaded(aggs)
        } catch {
            aggsState = .failed(Self.taError(error))
        }
    }

    public func loadNav() async {
        navState = .loading
        do {
            let nav = try await client.channelNav(id: channelId)
            navState = .loaded(nav)
            availableTabs = Self.resolveTabs(from: nav)
        } catch {
            navState = .failed(Self.taError(error))
            availableTabs = [.videos]
        }
    }

    nonisolated static func resolveTabs(from nav: ChannelNav) -> [ChannelSubTab] {
        guard nav.hasVideos != nil || nav.hasStreams != nil || nav.hasShorts != nil || nav.hasPlaylists != nil else {
            return [.videos]
        }
        var tabs: [ChannelSubTab] = [.videos]
        if nav.hasStreams == true { tabs.append(.streams) }
        if nav.hasShorts == true { tabs.append(.shorts) }
        if nav.hasPlaylists == true { tabs.append(.playlists) }
        return tabs
    }

    public func loadPlaylistsIfNeeded() async {
        guard !didLoadPlaylists else { return }
        didLoadPlaylists = true
        playlistsState = .loading
        do {
            let page = try await client.playlists(forChannel: channelId)
            playlistsState = .loaded(page.data)
        } catch {
            didLoadPlaylists = false
            playlistsState = .failed(Self.taError(error))
        }
    }

    public func retryPlaylists() async {
        didLoadPlaylists = false
        await loadPlaylistsIfNeeded()
    }

    @discardableResult
    public func markAllWatched() async -> Bool {
        isMarkingAllWatched = true
        markAllWatchedError = nil
        defer { isMarkingAllWatched = false }
        do {
            try await client.setWatched(id: channelId, isWatched: true)
            videosGrid.markAllLoadedWatchedLocally()
            streamsGrid.markAllLoadedWatchedLocally()
            shortsGrid.markAllLoadedWatchedLocally()
            return true
        } catch {
            markAllWatchedError = Self.taError(error)
            return false
        }
    }

    private static func taError(_ error: Error) -> TAError {
        (error as? TAError) ?? .network(error.localizedDescription)
    }
}
