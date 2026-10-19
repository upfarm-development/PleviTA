// The flash fix (`VideoCache`): a video page opens from the copy the list the user tapped was already showing, instead of blank.

import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("VideoCache")
struct VideoCacheTests {
    private func makeVideo(id: String, title: String = "t") -> Video {
        Video(youtubeId: id, title: title)
    }

    @Test("a filed video comes back by id, and an unseen one does not")
    func storeAndFetch() {
        let cache = VideoCache()
        cache.store(makeVideo(id: "a", title: "Alpha"))
        #expect(cache.video(id: "a")?.title == "Alpha")
        #expect(cache.video(id: "nope") == nil)
    }

    @Test("re-filing an id replaces the value without growing the cache")
    func refilingDoesNotGrow() {
        let cache = VideoCache()
        cache.store(makeVideo(id: "a", title: "first"))
        cache.store(makeVideo(id: "a", title: "second"))
        #expect(cache.count == 1)
        #expect(cache.video(id: "a")?.title == "second")
    }

    @Test("the cache is bounded — oldest entries are evicted, newest survive")
    func evictsOldest() {
        // The point of the bound: this is a long-lived object on a screen the user can
        // scroll for as long as they like, so it must not grow without limit.
        let cache = VideoCache(limit: 3)
        cache.store((1...5).map { makeVideo(id: "v\($0)") })
        #expect(cache.count == 3)
        #expect(cache.video(id: "v1") == nil, "oldest should have been evicted")
        #expect(cache.video(id: "v2") == nil)
        #expect(cache.video(id: "v3") != nil)
        #expect(cache.video(id: "v5") != nil)
    }
}
