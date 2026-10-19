// Every path must include its own trailing slash.

import Foundation

public struct Endpoint: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    /// Path relative to `/api/`, no leading slash, trailing slash included
    /// (e.g. `"video/"`, `"video/abc123/progress/"`).
    public var path: String
    public var method: Method
    public var query: [URLQueryItem]
    public var body: Data?
    /// Whether this request should carry the stored credential (token or
    /// session). `false` only for `/api/user/login/`.
    public var requiresAuth: Bool

    public init(
        path: String,
        method: Method = .get,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool = true
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }

    static func jsonBody(_ value: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(value)
    }
}

// MARK: - Connection and auth

extension Endpoint {
    static var ping: Endpoint { Endpoint(path: "ping/") }

    static func login(username: String, password: String, rememberMe: Bool) -> Endpoint {
        let body = LoginRequestBody(username: username, password: password, rememberMe: rememberMe ? "on" : "off")
        return Endpoint(path: "user/login/", method: .post, body: jsonBody(body), requiresAuth: false)
    }

    static var logout: Endpoint { Endpoint(path: "user/logout/", method: .post) }
    static var account: Endpoint { Endpoint(path: "user/account/") }
    static var appToken: Endpoint { Endpoint(path: "appsettings/token/") }
    static var userConfig: Endpoint { Endpoint(path: "user/me/") }

    static func updateUserConfig(_ config: UserConfig) -> Endpoint {
        Endpoint(path: "user/me/", method: .post, body: jsonBody(config))
    }
}

// MARK: - Videos

public struct VideoListQuery: Sendable {
    public enum WatchFilter: String, Sendable { case watched, unwatched, `continue` }
    public enum SortField: String, Sendable { case published, downloaded, views, likes, duration, filesize }
    public enum SortOrder: String, Sendable { case asc, desc }
    public enum VideoType: String, Sendable { case videos, streams, shorts }

    public var page: Int?
    public var watch: WatchFilter?
    public var sort: SortField?
    public var order: SortOrder?
    public var type: VideoType?
    public var channel: String?
    public var playlist: String?
    public var height: Int?

    public init(
        page: Int? = nil,
        watch: WatchFilter? = nil,
        sort: SortField? = nil,
        order: SortOrder? = nil,
        type: VideoType? = nil,
        channel: String? = nil,
        playlist: String? = nil,
        height: Int? = nil
    ) {
        self.page = page
        self.watch = watch
        self.sort = sort
        self.order = order
        self.type = type
        self.channel = channel
        self.playlist = playlist
        self.height = height
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        if let watch { items.append(URLQueryItem(name: "watch", value: watch.rawValue)) }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        if let order { items.append(URLQueryItem(name: "order", value: order.rawValue)) }
        if let type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        if let channel { items.append(URLQueryItem(name: "channel", value: channel)) }
        if let playlist { items.append(URLQueryItem(name: "playlist", value: playlist)) }
        if let height { items.append(URLQueryItem(name: "height", value: String(height))) }
        return items
    }
}

extension Endpoint {
    static func videos(_ query: VideoListQuery) -> Endpoint {
        Endpoint(path: "video/", query: query.queryItems)
    }

    static func video(id: String) -> Endpoint { Endpoint(path: "video/\(id)/") }

    static func setProgress(id: String, position: Double) -> Endpoint {
        Endpoint(path: "video/\(id)/progress/", method: .post, body: jsonBody(ProgressRequestBody(position: position)))
    }

    static func clearProgress(id: String) -> Endpoint {
        Endpoint(path: "video/\(id)/progress/", method: .delete)
    }

    static func comments(id: String) -> Endpoint { Endpoint(path: "video/\(id)/comment/") }
    static func similar(id: String) -> Endpoint { Endpoint(path: "video/\(id)/similar/") }
    static func nav(id: String) -> Endpoint { Endpoint(path: "video/\(id)/nav/") }

    static func setWatched(id: String, isWatched: Bool) -> Endpoint {
        Endpoint(path: "watched/", method: .post, body: jsonBody(WatchedRequestBody(id: id, isWatched: isWatched)))
    }

    static func deleteVideo(id: String) -> Endpoint {
        Endpoint(path: "video/\(id)/", method: .delete)
    }
    static func setDownloadStatus(id: String, status: String) -> Endpoint {
        Endpoint(path: "download/\(id)/", method: .post, body: jsonBody(DownloadStatusRequestBody(status: status)))
    }

    /// The status the app's own Ignore actions use.
    static func ignoreDownload(id: String) -> Endpoint {
        setDownloadStatus(id: id, status: "ignore-force")
    }
}

// MARK: - Channels

extension Endpoint {
    static func channels(page: Int? = nil, subscribedOnly: Bool = false) -> Endpoint {
        var items: [URLQueryItem] = []
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        if subscribedOnly { items.append(URLQueryItem(name: "filter", value: "subscribed")) }
        return Endpoint(path: "channel/", query: items)
    }

    static func channel(id: String) -> Endpoint { Endpoint(path: "channel/\(id)/") }
    static func channelAggs(id: String) -> Endpoint { Endpoint(path: "channel/\(id)/aggs/") }
    static func channelNav(id: String) -> Endpoint { Endpoint(path: "channel/\(id)/nav/") }
}

// MARK: - Playlists

extension Endpoint {
    public enum PlaylistType: String, Sendable { case regular, custom }

    static func playlists(page: Int? = nil, subscribedOnly: Bool = false, type: PlaylistType? = nil, channel: String? = nil) -> Endpoint {
        var items: [URLQueryItem] = []
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        if subscribedOnly { items.append(URLQueryItem(name: "subscribed", value: "true")) }
        if let type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        if let channel { items.append(URLQueryItem(name: "channel", value: channel)) }
        return Endpoint(path: "playlist/", query: items)
    }

    static func playlist(id: String) -> Endpoint { Endpoint(path: "playlist/\(id)/") }

    static func addToCustomPlaylist(playlistId: String, videoId: String) -> Endpoint {
        Endpoint(path: "playlist/\(playlistId)/", method: .post, body: jsonBody(CustomPlaylistActionBody(action: "create", videoId: videoId)))
    }
}

// MARK: - Search

extension Endpoint {
    static func search(query: String) -> Endpoint {
        Endpoint(path: "search/", query: [URLQueryItem(name: "query", value: query)])
    }
}
