// `SearchResults.isEmpty` decides which of two branches `SearchView` takes — the results list, or `ContentUnavailableView.search`.

import Foundation
import Testing
@testable import PleviCore

@Suite("SearchResults")
struct SearchModelTests {
    private func video(_ id: String) -> Video {
        Video(youtubeId: id, title: "Title \(id)")
    }

    @Test("a response with only full-text hits counts as empty, because nothing renders them")
    func fulltextOnlyCountsAsEmpty() {
        let results = SearchResults(
            videoResults: [],
            channelResults: [],
            playlistResults: [],
            fulltextResults: [video("a")]
        )
        #expect(results.isEmpty)
    }

    @Test("any rendered group makes it non-empty")
    func renderedGroupsCount() {
        #expect(!SearchResults(videoResults: [video("a")]).isEmpty)
        #expect(!SearchResults(channelResults: [Channel(channelId: "c", channelName: "C")]).isEmpty)
        #expect(!SearchResults(playlistResults: [Playlist(playlistId: "p", playlistName: "P")]).isEmpty)
    }

    @Test("all groups absent or empty is empty")
    func nothingAtAllIsEmpty() {
        #expect(SearchResults().isEmpty)
        #expect(SearchResults(videoResults: [], channelResults: [], playlistResults: []).isEmpty)
    }
}
