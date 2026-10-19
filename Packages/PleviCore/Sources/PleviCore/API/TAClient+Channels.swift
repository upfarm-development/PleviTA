
import Foundation

extension TAClient {
    public func channels(page: Int? = nil, subscribedOnly: Bool = false) async throws -> Paginated<Channel> {
        try await request(.channels(page: page, subscribedOnly: subscribedOnly))
    }

    public func channel(id: String) async throws -> Channel {
        try await request(.channel(id: id))
    }

    public func channelAggs(id: String) async throws -> ChannelAggs {
        try await request(.channelAggs(id: id))
    }

    public func channelNav(id: String) async throws -> ChannelNav {
        try await request(.channelNav(id: id))
    }

    public func playlists(forChannel channelId: String) async throws -> Paginated<Playlist> {
        try await request(.playlists(channel: channelId))
    }
}
