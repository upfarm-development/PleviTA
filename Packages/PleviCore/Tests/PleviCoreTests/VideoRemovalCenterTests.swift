import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("VideoRemovalCenter")
struct VideoRemovalCenterTests {
    @MainActor
    final class FakeStore: VideoMutating {
        var removed: [String] = []
        func setWatched(_ video: Video, isWatched: Bool) async {}
        func removeVideoLocally(id: String) { removed.append(id) }
    }

    @Test("removal reaches every live registered store")
    func reachesEveryStore() {
        let center = VideoRemovalCenter()
        let a = FakeStore(), b = FakeStore()
        center.register(a)
        center.register(b)
        center.removeEverywhere(id: "v1")
        #expect(a.removed == ["v1"])
        #expect(b.removed == ["v1"])
    }

    @Test("a store that has gone away is skipped without error")
    func skipsDeadStores() {
        let center = VideoRemovalCenter()
        let kept = FakeStore()
        center.register(kept)
        do { center.register(FakeStore()) }
        center.removeEverywhere(id: "v2")
        #expect(kept.removed == ["v2"])
    }
}
