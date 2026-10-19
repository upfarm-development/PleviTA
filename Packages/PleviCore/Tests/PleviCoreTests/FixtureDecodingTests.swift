
import Foundation
import Testing
@testable import PleviCore

@Suite("Fixture decoding")
struct FixtureDecodingTests {
    @Test("video.json decodes with nested player/channel/streams/subtitles")
    func decodesVideo() throws {
        let video = try Fixture.decode(Video.self, from: "video.json")
        #expect(video.youtubeId == "dQw4w9WgXcQ")
        #expect(video.title == "Synthetic Fixture Video One")
        #expect(video.mediaUrl == "/media/synthetic-channel/dQw4w9WgXcQ.mp4")
        #expect(video.player?.watched == false)
        #expect(video.player?.position == 90)
        #expect(video.player?.duration == 754)
        #expect(video.channel?.channelId == "UCsynthetic00000000000000")
        #expect(video.channel?.channelSubscribed == true)
        #expect(video.streams?.count == 2)
        #expect(video.subtitles?.first?.lang == "en")
        #expect(video.stats?.viewCount == 42000)
    }

    @Test("video.json's sponsorblock decodes real captured segments, including a zero-length poi_highlight")
    func decodesVideoSponsorblockPopulated() throws {
        let video = try Fixture.decode(Video.self, from: "video.json")
        let sponsorblock = try #require(video.sponsorblock)
        #expect(sponsorblock.isEnabled == true)
        // One of the five real segments is locked; `has_unlocked` means "no segment here is
        // locked", so its presence must be false, not the vestigial `is_enabled`.
        #expect(sponsorblock.hasUnlocked == false)
        #expect(sponsorblock.segments.count == 5)
        #expect(sponsorblock.segments.filter { $0.category == "selfpromo" }.count == 3)
        let poi = try #require(sponsorblock.segments.first { $0.category == "poi_highlight" })
        #expect(poi.start == poi.end)
        // TA overwrites actionType to "none" for every non-sponsor category — real capture, not an assumption.
        #expect(sponsorblock.segments.allSatisfy { $0.actionType == "none" })
    }

    @Test("video_sponsorblock_empty.json decodes segments: [] with has_unlocked genuinely absent")
    func decodesVideoSponsorblockEmpty() throws {
        let video = try Fixture.decode(Video.self, from: "video_sponsorblock_empty.json")
        let sponsorblock = try #require(video.sponsorblock)
        #expect(sponsorblock.isEnabled == true)
        #expect(sponsorblock.segments.isEmpty)
        // Confirmed live: no `has_unlocked` key at all when segments is empty, not `false`.
        #expect(sponsorblock.hasUnlocked == nil)
    }

    @Test("video_sponsorblock_none.json decodes with the sponsorblock key entirely absent")
    func decodesVideoSponsorblockNone() throws {
        let video = try Fixture.decode(Video.self, from: "video_sponsorblock_none.json")
        #expect(video.sponsorblock == nil)
    }

    @Test("SponsorBlockInfo defaults segments to [] when the segments key itself is missing")
    func sponsorBlockInfoDefaultsMissingSegments() throws {
        let json = Data("""
        { "is_enabled": true, "last_refresh": 1700000000 }
        """.utf8)
        let info = try JSONDecoder().decode(SponsorBlockInfo.self, from: json)
        #expect(info.isEnabled == true)
        #expect(info.segments.isEmpty)
    }

    @Test("video_list.json decodes as Paginated<Video> with flexible paginate types")
    func decodesVideoList() throws {
        let page = try Fixture.decode(Paginated<Video>.self, from: "video_list.json")
        #expect(page.data.count == 2)
        #expect(page.data.first?.youtubeId == "aaaaaaaaaaa")
        #expect(page.data.last?.vidType == "shorts")
        #expect(page.paginate?.maxHits == nil)
        #expect(page.paginate?.nextPages == [2, 3])
        #expect(page.paginate?.totalHits == 6)
        #expect(page.paginate?.hasNextPage == true)
    }

    @Test("channel.json decodes")
    func decodesChannel() throws {
        let channel = try Fixture.decode(Channel.self, from: "channel.json")
        #expect(channel.channelId == "UCsynthetic00000000000000")
        #expect(channel.channelSubscribed == true)
        #expect(channel.channelSubs == 128000)
    }

    @Test("channel_list.json decodes as Paginated<Channel>")
    func decodesChannelList() throws {
        let page = try Fixture.decode(Paginated<Channel>.self, from: "channel_list.json")
        #expect(page.data.count == 2)
        #expect(page.data.first?.channelSubscribed == true)
        #expect(page.data.last?.channelSubscribed == false)
    }

    @Test("channel_aggs.json decodes")
    func decodesChannelAggs() throws {
        let aggs = try Fixture.decode(ChannelAggs.self, from: "channel_aggs.json")
        #expect(aggs.totalItems == 87)
        #expect(aggs.totalSize == 48318023680)
    }

    @Test("channel_nav.json decodes")
    func decodesChannelNav() throws {
        let nav = try Fixture.decode(ChannelNav.self, from: "channel_nav.json")
        #expect(nav.hasVideos == true)
        #expect(nav.hasStreams == false)
    }

    @Test("playlist.json decodes with ordered entries")
    func decodesPlaylist() throws {
        let playlist = try Fixture.decode(Playlist.self, from: "playlist.json")
        #expect(playlist.playlistId == "PLsynthetic0000000000000000")
        #expect(playlist.playlistEntries?.count == 3)
        #expect(playlist.playlistEntries?.map(\.idx) == [0, 1, 2])
        #expect(playlist.playlistEntries?.last?.downloaded == false)
    }

    @Test("playlist_list.json decodes as Paginated<Playlist>")
    func decodesPlaylistList() throws {
        let page = try Fixture.decode(Paginated<Playlist>.self, from: "playlist_list.json")
        #expect(page.data.count == 1)
        #expect(page.data.first?.playlistType == "regular")
    }

    @Test("comment_list.json decodes as a flat [Comment]")
    func decodesCommentList() throws {
        // `Comment` is qualified because `Testing` also exports a type
        // named `Comment` (the trailing-string-argument annotation type),
        // which otherwise makes plain `Comment` ambiguous in this file.
        let comments = try Fixture.decode([PleviCore.Comment].self, from: "comment_list.json")
        #expect(comments.count == 3)
        #expect(comments[0].isTopLevel)
        #expect(comments[1].commentParent == "c1")
        // comment_likecount missing on c3 must decode as nil, not throw.
        #expect(comments[2].commentLikecount == nil)
    }

    @Test("search.json decodes into SearchResults via the `results` wrapper")
    func decodesSearch() throws {
        let response = try Fixture.decode(SearchResponse.self, from: "search.json")
        #expect(response.results.videoResults?.count == 1)
        #expect(response.results.channelResults?.first?.channelId == "UCsynthetic00000000000000")
        #expect(response.results.playlistResults?.first?.playlistId == "PLsynthetic0000000000000000")
        #expect(!response.results.isEmpty)
    }

    @Test("ping.json decodes")
    func decodesPing() throws {
        let ping = try Fixture.decode(PingResponse.self, from: "ping.json")
        #expect(ping.isPong)
        #expect(ping.version == "v0.5.12-synthetic")
        // `user` arrives as a JSON number (1) in the fixture; PingResponse
        // stores it flexibly as a String.
        #expect(ping.user == "1")
    }

    @Test("token.json decodes")
    func decodesToken() throws {
        let token = try Fixture.decode(TokenResponse.self, from: "token.json")
        #expect(token.token == "synthetic0fixture0token0000000000000000")
    }

    @Test("account.json decodes")
    func decodesAccount() throws {
        let account = try Fixture.decode(Account.self, from: "account.json")
        #expect(account.username == "admin")
        #expect(account.isSuperuser == true)
    }

    @Test("user_config.json decodes every key")
    func decodesUserConfig() throws {
        let config = try Fixture.decode(UserConfig.self, from: "user_config.json")
        #expect(config.pageSize == 12)
        #expect(config.hideWatched == false)
        #expect(config.showSubedOnly == true)
        #expect(config.showSubedOnlyPlaylists == false)
        #expect(config.gridItems == 3)
        #expect(config.stylesheet == "dark.css")
    }

    @Test("video_nav.json decodes")
    func decodesVideoNav() throws {
        let nav = try Fixture.decode([VideoNavEntry].self, from: "video_nav.json")
        #expect(nav.count == 1)
        #expect(nav.first?.playlistMeta?.playlistName == "Synthetic Fixture Playlist")
        #expect(nav.first?.playlistNext?.youtubeId == "bbbbbbbbbbb")
        #expect(nav.first?.playlistNext?.title == "Synthetic List Video B")
        // Explicit `null` in the payload (first entry of the playlist), not
        // a missing key — both must decode to nil.
        #expect(nav.first?.playlistPrevious == nil)
    }

    @Test("UserConfig round-trips through encode, omitting nil fields (partial POST body)")
    func userConfigPartialEncoding() throws {
        let partial = UserConfig(hideWatched: true)
        let data = try JSONEncoder().encode(partial)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.count == 1)
        #expect(object?["hide_watched"] as? Bool == true)
    }
}
