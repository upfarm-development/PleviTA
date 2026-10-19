
import Foundation
import Testing
@testable import PleviCore

@Suite("Endpoint")
struct EndpointTests {
    @Test("every endpoint path ends with a trailing slash")
    func trailingSlashes() {
        let endpoints: [Endpoint] = [
            .ping,
            .login(username: "a", password: "b", rememberMe: true),
            .logout,
            .account,
            .appToken,
            .userConfig,
            .videos(VideoListQuery()),
            .video(id: "abc"),
            .setProgress(id: "abc", position: 1),
            .clearProgress(id: "abc"),
            .comments(id: "abc"),
            .similar(id: "abc"),
            .nav(id: "abc"),
            .setWatched(id: "abc", isWatched: true),
            .deleteVideo(id: "abc"),
            .setDownloadStatus(id: "abc", status: "ignore"),
            .channels(),
            .channel(id: "abc"),
            .channelAggs(id: "abc"),
            .channelNav(id: "abc"),
            .playlists(),
            .playlist(id: "abc"),
            .addToCustomPlaylist(playlistId: "pl1", videoId: "abc"),
            .search(query: "test")
        ]
        for endpoint in endpoints {
            #expect(endpoint.path.hasSuffix("/"), "\(endpoint.path) is missing its trailing slash")
            #expect(!endpoint.path.hasPrefix("/"), "\(endpoint.path) should not start with a slash")
        }
    }

    @Test("login body encodes remember_me as on/off and requires no auth")
    func loginEndpoint() throws {
        let endpoint = Endpoint.login(username: "alice", password: "secret", rememberMe: true)
        #expect(endpoint.method == .post)
        #expect(endpoint.requiresAuth == false)
        let body = try #require(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["username"] as? String == "alice")
        #expect(object?["password"] as? String == "secret")
        #expect(object?["remember_me"] as? String == "on")
    }

    @Test("video list query builds the documented query items")
    func videoListQuery() {
        let query = VideoListQuery(page: 2, watch: .continue, sort: .published, order: .desc, type: .videos, channel: "chan1")
        let endpoint = Endpoint.videos(query)
        let names = Set(endpoint.query.map(\.name))
        #expect(names == ["page", "watch", "sort", "order", "type", "channel"])
        #expect(endpoint.query.first(where: { $0.name == "watch" })?.value == "continue")
    }

    @Test("watched request body encodes is_watched")
    func watchedEndpoint() throws {
        let endpoint = Endpoint.setWatched(id: "vid1", isWatched: true)
        let body = try #require(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["id"] as? String == "vid1")
        #expect(object?["is_watched"] as? Bool == true)
    }

    @Test("delete video endpoint uses DELETE with no body")
    func deleteVideoEndpoint() {
        let endpoint = Endpoint.deleteVideo(id: "abc")
        #expect(endpoint.method == .delete)
        #expect(endpoint.path == "video/abc/")
        #expect(endpoint.body == nil)
    }

    @Test("download status endpoint posts the ignore status")
    func downloadStatusEndpoint() throws {
        let endpoint = Endpoint.setDownloadStatus(id: "abc", status: "ignore")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "download/abc/")
        let body = try #require(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["status"] as? String == "ignore")
    }

    @Test("the Ignore action sends ignore-force, not ignore")
    func ignoreDownloadUsesIgnoreForce() throws {
        let endpoint = Endpoint.ignoreDownload(id: "abc")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "download/abc/")
        let body = try #require(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["status"] as? String == "ignore-force")
    }

    @Test("custom playlist add endpoint encodes action and snake_case video_id")
    func customPlaylistAddEndpoint() throws {
        let endpoint = Endpoint.addToCustomPlaylist(playlistId: "pl1", videoId: "abc")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "playlist/pl1/")
        let body = try #require(endpoint.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["action"] as? String == "create")
        #expect(object?["video_id"] as? String == "abc")
    }

    @Test("channels endpoint adds filter=subscribed only when requested")
    func channelsEndpointSubscribedFilter() {
        let unfiltered = Endpoint.channels()
        #expect(unfiltered.query.isEmpty)

        let filtered = Endpoint.channels(page: 2, subscribedOnly: true)
        #expect(filtered.query.contains(URLQueryItem(name: "filter", value: "subscribed")))
        #expect(filtered.query.contains(URLQueryItem(name: "page", value: "2")))
    }

    @Test("video list query includes channel and type for a channel sub-tab")
    func videoListQueryChannelSubTab() {
        let query = VideoListQuery(page: 1, watch: .unwatched, sort: .downloaded, order: .desc, type: .streams, channel: "chan1")
        let endpoint = Endpoint.videos(query)
        #expect(endpoint.query.contains(URLQueryItem(name: "channel", value: "chan1")))
        #expect(endpoint.query.contains(URLQueryItem(name: "type", value: "streams")))
    }

    @Test("video list query includes playlist for a playlist detail screen")
    func videoListQueryPlaylistFilter() {
        let query = VideoListQuery(page: 2, playlist: "pl1")
        let endpoint = Endpoint.videos(query)
        #expect(endpoint.query.contains(URLQueryItem(name: "playlist", value: "pl1")))
        #expect(endpoint.query.contains(URLQueryItem(name: "page", value: "2")))
    }

    @Test("playlists endpoint adds subscribed/type/channel only when requested")
    func playlistsEndpointFilters() {
        let unfiltered = Endpoint.playlists()
        #expect(unfiltered.query.isEmpty)

        let filtered = Endpoint.playlists(page: 2, subscribedOnly: true, type: .custom, channel: "chan1")
        #expect(filtered.query.contains(URLQueryItem(name: "page", value: "2")))
        #expect(filtered.query.contains(URLQueryItem(name: "subscribed", value: "true")))
        #expect(filtered.query.contains(URLQueryItem(name: "type", value: "custom")))
        #expect(filtered.query.contains(URLQueryItem(name: "channel", value: "chan1")))
    }
}
