import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineDownloadQueue")
struct OfflineDownloadQueueTests {
    private func item(
        _ id: String,
        position: Int? = nil,
        savedAt: TimeInterval = 0,
        waitingForWiFi: Bool = false
    ) -> OfflineDownloadQueue.Item {
        OfflineDownloadQueue.Item(
            videoId: id,
            queuePosition: position,
            savedAt: Date(timeIntervalSince1970: savedAt),
            isWaitingForWiFi: waitingForWiFi
        )
    }

    // MARK: - Ordering

    @Test("runs oldest save first, not newest — the shelf's own sort is the other way round")
    func oldestFirst() {
        let order = OfflineDownloadQueue.order([
            item("newest", savedAt: 300),
            item("oldest", savedAt: 100),
            item("middle", savedAt: 200)
        ])
        #expect(order.map(\.videoId) == ["oldest", "middle", "newest"])
    }

    @Test("an explicit position beats savedAt")
    func explicitPositionWins() {
        let order = OfflineDownloadQueue.order([
            item("old", position: 1, savedAt: 100),
            item("new", position: 0, savedAt: 900)
        ])
        #expect(order.map(\.videoId) == ["new", "old"])
    }

    @Test("a video saved after a reorder joins the back, not the middle")
    func unpositionedSortsAfterPositioned() {
        let order = OfflineDownloadQueue.order([
            item("justSaved", savedAt: 1),
            item("dragged", position: 5, savedAt: 900)
        ])
        #expect(order.map(\.videoId) == ["dragged", "justSaved"])
    }

    @Test("videos saved in the same batch still get a total order")
    func identicalSavedAtIsStable() {
        let ids = ["c", "a", "b"].map { item($0, savedAt: 500) }
        #expect(OfflineDownloadQueue.order(ids).map(\.videoId) == ["a", "b", "c"])
        #expect(OfflineDownloadQueue.order(ids.reversed()).map(\.videoId) == ["a", "b", "c"])
    }

    // MARK: - What starts now

    @Test("starts only up to the limit")
    func respectsLimit() {
        let items = (1...10).map { item("v\($0)", savedAt: TimeInterval($0)) }
        let next = OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 3)
        #expect(next == ["v1", "v2", "v3"])
    }

    @Test("live downloads fill slots and are never handed over twice")
    func liveFillSlots() {
        let items = (1...5).map { item("v\($0)", savedAt: TimeInterval($0)) }
        let next = OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: ["v1", "v2"], limit: 3)
        #expect(next == ["v3"])
    }

    @Test("nothing starts once the limit is reached")
    func fullMeansNothing() {
        let items = (1...5).map { item("v\($0)", savedAt: TimeInterval($0)) }
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: ["v1", "v2", "v3"], limit: 3).isEmpty)
    }

    @Test("a video waiting for Wi-Fi is skipped but does not block the one behind it")
    func waitingForWiFiSkipped() {
        let items = [
            item("blocked", savedAt: 1, waitingForWiFi: true),
            item("ready", savedAt: 2)
        ]
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 2) == ["ready"])
    }

    @Test("a non-positive limit starts nothing — unlimited is the bug, not a setting")
    func zeroLimitStartsNothing() {
        let items = [item("v1", savedAt: 1)]
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 0).isEmpty)
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: -1).isEmpty)
    }

    @Test("more live than the limit never yields a negative slot count")
    func overSubscribedIsEmptyNotCrashy() {
        let items = (1...5).map { item("v\($0)", savedAt: TimeInterval($0)) }
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: ["a", "b", "c", "d"], limit: 3).isEmpty)
    }

    @Test("a dragged order is what actually runs")
    func draggedOrderRuns() {
        let items = [
            item("first", position: 0, savedAt: 100),
            item("second", position: 1, savedAt: 50),
            item("third", position: 2, savedAt: 10)
        ]
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 2) == ["first", "second"])
    }

    @Test("a video refused this pump is skipped without holding a slot")
    func refusedIsSkippedWithoutASlot() {
        let items = (1...5).map { item("v\($0)", savedAt: TimeInterval($0)) }
        // v1 was refused (no disk space, say) and its failure did not stick on disk. It must
        // not be picked again, and the video behind it takes the slot in the same pass.
        let next = OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 2, excluding: ["v1"])
        #expect(next == ["v2", "v3"])
    }

    @Test("refusing everything that is left starts nothing, so the pump can stop")
    func allRefusedIsEmpty() {
        let items = (1...3).map { item("v\($0)", savedAt: TimeInterval($0)) }
        #expect(OfflineDownloadQueue.nextToStart(items: items, liveVideoIds: [], limit: 3, excluding: ["v1", "v2", "v3"]).isEmpty)
    }

    // MARK: - Taking the queue back from the system

    @Test("on return, transfers still waiting in the system beyond the next few are cancelled")
    func reclaimCancelsTheTail() {
        let items = (1...10).map { item("v\($0)", savedAt: TimeInterval($0)) }
        let cancel = OfflineDownloadQueue.toReclaim(
            items: items,
            inProgress: ["v1"],
            waitingInSystem: Set((2...10).map { "v\($0)" }),
            limit: 3
        )
        // v1 is running and v2, v3 would be started next anyway: keeping them avoids cancelling
        // a transfer only to recreate it a moment later.
        #expect(cancel == Set((4...10).map { "v\($0)" }))
    }

    @Test("a transfer that has received bytes is never cancelled, even over the limit")
    func reclaimKeepsInProgress() {
        let items = (1...6).map { item("v\($0)", savedAt: TimeInterval($0)) }
        let cancel = OfflineDownloadQueue.toReclaim(
            items: items,
            inProgress: ["v1", "v2", "v3", "v4"],
            waitingInSystem: ["v5", "v6"],
            limit: 3
        )
        #expect(cancel == ["v5", "v6"])
    }

    @Test("reclaiming follows the dragged order, not the order the system was handed")
    func reclaimFollowsDraggedOrder() {
        let items = [
            item("dragged", position: 0, savedAt: 900),
            item("a", position: 1, savedAt: 1),
            item("b", position: 2, savedAt: 2),
            item("c", position: 3, savedAt: 3)
        ]
        let cancel = OfflineDownloadQueue.toReclaim(
            items: items,
            inProgress: [],
            waitingInSystem: ["a", "b", "c", "dragged"],
            limit: 2
        )
        #expect(cancel == ["b", "c"])
    }

    @Test("nothing handed over means nothing to take back")
    func reclaimNothing() {
        let items = (1...3).map { item("v\($0)", savedAt: TimeInterval($0)) }
        #expect(OfflineDownloadQueue.toReclaim(items: items, inProgress: [], waitingInSystem: [], limit: 3).isEmpty)
    }

    // MARK: - Reordering

    @Test("positions are written for every video, not just the moved one")
    func positionsCoverEverything() {
        let positions = OfflineDownloadQueue.positions(forOrder: ["a", "b", "c"])
        #expect(positions == ["a": 0, "b": 1, "c": 2])
    }

    @Test("dragging a row upwards")
    func moveUp() {
        #expect(OfflineDownloadQueue.moving(["a", "b", "c", "d"], fromOffsets: IndexSet(integer: 2), toOffset: 0) == ["c", "a", "b", "d"])
    }

    @Test("dragging a row downwards — toOffset indexes the list before removal")
    func moveDown() {
        // SwiftUI reports "move row 0 below row 2" as toOffset 3, not 2. Taking that literally
        // after removing the row inserts one place too far.
        #expect(OfflineDownloadQueue.moving(["a", "b", "c", "d"], fromOffsets: IndexSet(integer: 0), toOffset: 3) == ["b", "c", "a", "d"])
    }

    @Test("dragging to the very end")
    func moveToEnd() {
        #expect(OfflineDownloadQueue.moving(["a", "b", "c"], fromOffsets: IndexSet(integer: 0), toOffset: 3) == ["b", "c", "a"])
    }

    @Test("a move that changes nothing changes nothing")
    func moveInPlace() {
        #expect(OfflineDownloadQueue.moving(["a", "b", "c"], fromOffsets: IndexSet(integer: 1), toOffset: 1) == ["a", "b", "c"])
        #expect(OfflineDownloadQueue.moving(["a", "b", "c"], fromOffsets: IndexSet(integer: 1), toOffset: 2) == ["a", "b", "c"])
    }

    @Test("moving several rows at once keeps them together and in order")
    func moveMultiple() {
        #expect(OfflineDownloadQueue.moving(["a", "b", "c", "d"], fromOffsets: IndexSet([0, 2]), toOffset: 4) == ["b", "d", "a", "c"])
    }

    @Test("an out-of-range offset is ignored rather than trapping")
    func outOfRangeIsSafe() {
        #expect(OfflineDownloadQueue.moving(["a", "b"], fromOffsets: IndexSet(integer: 7), toOffset: 0) == ["a", "b"])
        #expect(OfflineDownloadQueue.moving(["a", "b"], fromOffsets: IndexSet(integer: 0), toOffset: 99) == ["b", "a"])
    }

    @Test("a drag then a round trip through positions reproduces the same order")
    func dragRoundTrips() {
        let dragged = OfflineDownloadQueue.moving(["a", "b", "c", "d"], fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(dragged == ["a", "d", "b", "c"])
        let positions = OfflineDownloadQueue.positions(forOrder: dragged)
        let items = ["a", "b", "c", "d"].map { item($0, position: positions[$0], savedAt: 0) }
        #expect(OfflineDownloadQueue.order(items).map(\.videoId) == dragged)
    }
}
