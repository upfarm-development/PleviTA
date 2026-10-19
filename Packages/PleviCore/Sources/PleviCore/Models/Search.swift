// `GET /api/search/?query=<text>` -> `{ results: { video_results, channel_results, playlist_results, fulltext_results? } }`.

import Foundation

public struct SearchResults: Codable, Sendable, Equatable {
    public var videoResults: [Video]?
    public var channelResults: [Channel]?
    public var playlistResults: [Playlist]?
    public var fulltextResults: [Video]?

    enum CodingKeys: String, CodingKey {
        case videoResults = "video_results"
        case channelResults = "channel_results"
        case playlistResults = "playlist_results"
        case fulltextResults = "fulltext_results"
    }

    public init(
        videoResults: [Video]? = nil,
        channelResults: [Channel]? = nil,
        playlistResults: [Playlist]? = nil,
        fulltextResults: [Video]? = nil
    ) {
        self.videoResults = videoResults
        self.channelResults = channelResults
        self.playlistResults = playlistResults
        self.fulltextResults = fulltextResults
    }

    /// Whether there is anything to *show* — which is not the same as whether the server sent anything.
    public var isEmpty: Bool {
        (videoResults?.isEmpty ?? true)
            && (channelResults?.isEmpty ?? true)
            && (playlistResults?.isEmpty ?? true)
    }

    /// Drops anything that does not actually contain every word of `query`, comparing with accents folded away.
    public func filtered(matching query: String) -> SearchResults {
        func keep(_ text: String?) -> Bool {
            guard let text, !text.isEmpty else { return false }
            return SearchAccentProbe.matches(text, query: query)
        }
        return SearchResults(
            // A video matches on its own title or on its channel's name — searching "bjorn"
            // should reach his videos, not only his channel.
            videoResults: videoResults?.filter { keep($0.title) || keep($0.channel?.channelName) },
            channelResults: channelResults?.filter { keep($0.channelName) },
            playlistResults: playlistResults?.filter { keep($0.playlistName) },
            fulltextResults: nil
        )
    }

    /// Appends everything in `other` that this does not already hold, matched by id.
    public func appending(_ other: SearchResults) -> SearchResults {
        func merge<T: Identifiable>(_ mine: [T]?, _ theirs: [T]?) -> [T]? where T.ID == String {
            guard let theirs, !theirs.isEmpty else { return mine }
            let existing = Set((mine ?? []).map(\.id))
            let added = theirs.filter { !existing.contains($0.id) }
            guard !added.isEmpty else { return mine }
            return (mine ?? []) + added
        }
        return SearchResults(
            videoResults: merge(videoResults, other.videoResults),
            channelResults: merge(channelResults, other.channelResults),
            playlistResults: merge(playlistResults, other.playlistResults),
            fulltextResults: fulltextResults
        )
    }
}

public struct SearchResponse: Decodable, Sendable, Equatable {
    public var results: SearchResults

    enum CodingKeys: String, CodingKey {
        case results
    }

    public init(from decoder: Decoder) throws {
        // Prefer the documented `{ results: {...} }` wrapper; fall back to
        // the groups being present directly at the root.
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try? container.decodeIfPresent(SearchResults.self, forKey: .results) {
            results = nested
        } else {
            results = try SearchResults(from: decoder)
        }
    }

    public init(results: SearchResults) {
        self.results = results
    }
}
