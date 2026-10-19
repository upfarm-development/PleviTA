import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("OfflineTransferProgress")
struct OfflineTransferProgressTests {
    @Test("the first tick has no speed, the second measures it")
    func speedNeedsTwoTicks() {
        let progress = OfflineTransferProgress()
        let t0 = Date(timeIntervalSince1970: 1000)
        progress.update(videoId: "v1", receivedByteCount: 0, expectedByteCount: 10_000_000, at: t0)
        #expect(progress.samples["v1"]?.bytesPerSecond == nil)
        progress.update(videoId: "v1", receivedByteCount: 1_000_000, expectedByteCount: nil, at: t0.addingTimeInterval(0.5))
        #expect(progress.samples["v1"]?.bytesPerSecond == 2_000_000)
        #expect(progress.samples["v1"]?.expectedByteCount == 10_000_000)
    }

    @Test("speed is smoothed rather than following the last chunk")
    func speedIsSmoothed() {
        let speed = OfflineTransferProgress.smoothedSpeed(previous: 1_000_000, byteDelta: 2_000_000, elapsed: 1)
        #expect(speed == 1_400_000)
    }

    @Test("a tick too soon, or one that went backwards, leaves the speed alone")
    func ignoresUnmeasurableTicks() {
        #expect(OfflineTransferProgress.smoothedSpeed(previous: 500, byteDelta: 100, elapsed: 0.01) == 500)
        #expect(OfflineTransferProgress.smoothedSpeed(previous: 500, byteDelta: -100, elapsed: 1) == 500)
    }

    @Test("prune drops samples for transfers that are no longer running")
    func pruneDropsFinished() {
        let progress = OfflineTransferProgress()
        progress.update(videoId: "a", receivedByteCount: 1, expectedByteCount: 2)
        progress.update(videoId: "b", receivedByteCount: 1, expectedByteCount: 2)
        progress.prune(keeping: ["a"])
        #expect(progress.samples["a"] != nil)
        #expect(progress.samples["b"] == nil)
    }
}
