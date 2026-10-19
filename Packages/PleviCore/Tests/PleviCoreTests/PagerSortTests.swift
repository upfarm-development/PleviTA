import Testing
@testable import PleviCore

@Suite("Playlist pager sorting")
struct PagerSortTests {

    private func entry(_ id: String, title: String?, idx: Int?) -> PlaylistEntry {
        PlaylistEntry(youtubeId: id, title: title, uploader: nil, idx: idx, downloaded: true)
    }

    private var sample: [PlaylistEntry] {
        [
            entry("c", title: "Cherry", idx: 2),
            entry("a", title: "Apple", idx: 0),
            entry("b", title: "Banana", idx: 1),
        ]
    }

    private let published = [
        "a": "2026-03-01T00:00:00+00:00",
        "b": "2026-01-01T00:00:00+00:00",
        "c": "2026-02-01T00:00:00+00:00",
    ]

    @Test("playlist order ascending reproduces idx order")
    func playlistOrderAscending() {
        let sorted = VideoDetailStore.sortedPagerEntries(sample, field: .playlistOrder, order: .asc, publishedById: [:])
        #expect(sorted.map(\.youtubeId) == ["a", "b", "c"])
    }

    @Test("playlist order descending reverses it")
    func playlistOrderDescending() {
        let sorted = VideoDetailStore.sortedPagerEntries(sample, field: .playlistOrder, order: .desc, publishedById: [:])
        #expect(sorted.map(\.youtubeId) == ["c", "b", "a"])
    }

    @Test("title sorts alphabetically, not by playlist position")
    func titleSort() {
        let sorted = VideoDetailStore.sortedPagerEntries(sample, field: .title, order: .asc, publishedById: [:])
        #expect(sorted.map(\.title) == ["Apple", "Banana", "Cherry"])
    }

    @Test("date published uses the supplied dates, not idx")
    func datePublishedSort() {
        let sorted = VideoDetailStore.sortedPagerEntries(sample, field: .datePublished, order: .asc, publishedById: published)
        #expect(sorted.map(\.youtubeId) == ["b", "c", "a"])
    }

    @Test("newest first is the exact reverse of oldest first")
    func datePublishedDescending() {
        let sorted = VideoDetailStore.sortedPagerEntries(sample, field: .datePublished, order: .desc, publishedById: published)
        #expect(sorted.map(\.youtubeId) == ["a", "c", "b"])
    }

    @Test("an entry with no published date sorts as the earliest possible one")
    func missingPublishedDate() {
        let withUnknown = sample + [entry("d", title: "Durian", idx: 3)]
        let sorted = VideoDetailStore.sortedPagerEntries(withUnknown, field: .datePublished, order: .asc, publishedById: published)
        #expect(sorted.first?.youtubeId == "d")
    }

    @Test("entries with the same title fall back to playlist order, not id order")
    func tiedTitlesKeepPlaylistOrder() {
        // Ids deliberately descending against idx, so an id-based tiebreak
        // would flip them and this would catch it.
        let tied = [entry("z", title: "Same", idx: 0), entry("a", title: "Same", idx: 1)]
        let sorted = VideoDetailStore.sortedPagerEntries(tied, field: .title, order: .asc, publishedById: [:])
        #expect(sorted.map(\.youtubeId) == ["z", "a"])
    }
}

extension PagerSortTests {
    @Test("with no published dates at all, entries keep playlist order")
    func noPublishedDatesFallsBackToPlaylistOrder() {
        let entries = [
            PlaylistEntry(youtubeId: "zzz", title: "First", uploader: nil, idx: 0, downloaded: true),
            PlaylistEntry(youtubeId: "aaa", title: "Second", uploader: nil, idx: 1, downloaded: true),
            PlaylistEntry(youtubeId: "mmm", title: "Third", uploader: nil, idx: 2, downloaded: true),
        ]
        let sorted = VideoDetailStore.sortedPagerEntries(entries, field: .datePublished, order: .asc, publishedById: [:])
        #expect(sorted.map(\.youtubeId) == ["zzz", "aaa", "mmm"])
    }

    @Test("entries sharing a published date keep playlist order between them")
    func equalDatesKeepPlaylistOrder() {
        let entries = [
            PlaylistEntry(youtubeId: "zzz", title: "First", uploader: nil, idx: 0, downloaded: true),
            PlaylistEntry(youtubeId: "aaa", title: "Second", uploader: nil, idx: 1, downloaded: true),
        ]
        let same = ["zzz": "2026-01-01T00:00:00+00:00", "aaa": "2026-01-01T00:00:00+00:00"]
        let sorted = VideoDetailStore.sortedPagerEntries(entries, field: .datePublished, order: .asc, publishedById: same)
        #expect(sorted.map(\.youtubeId) == ["zzz", "aaa"])
    }
}

