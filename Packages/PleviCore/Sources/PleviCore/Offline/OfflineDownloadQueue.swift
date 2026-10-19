// Who downloads next, and how many at once.

import Foundation

public enum OfflineDownloadQueue {
    /// One unfinished download's place in line. Deliberately not `OfflineLibrary.Entry` — this
    /// type is the policy, and the policy needs four fields, none of which are a `Video`.
    public struct Item: Sendable, Equatable {
        public var videoId: String
        /// Set only once someone has dragged the queue into an order they chose. `nil` means
        /// "wherever `savedAt` puts me", which is every item until the first reorder.
        public var queuePosition: Int?
        public var savedAt: Date
        /// Deferred by the cellular gate. Skipped for starting, but kept in the order — it is
        /// still in the queue, and it must not silently jump the line when Wi-Fi returns.
        public var isWaitingForWiFi: Bool

        public init(videoId: String, queuePosition: Int? = nil, savedAt: Date, isWaitingForWiFi: Bool = false) {
            self.videoId = videoId
            self.queuePosition = queuePosition
            self.savedAt = savedAt
            self.isWaitingForWiFi = isWaitingForWiFi
        }
    }

    /// The queue in the order it will actually run.
    public static func order(_ items: [Item]) -> [Item] {
        items.sorted { first, second in
            switch (first.queuePosition, second.queuePosition) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
            if first.savedAt != second.savedAt { return first.savedAt < second.savedAt }
            return first.videoId < second.videoId
        }
    }

    public static func nextToStart(
        items: [Item],
        liveVideoIds: Set<String>,
        limit: Int,
        excluding refused: Set<String> = []
    ) -> [String] {
        let slots = limit - liveVideoIds.count
        guard slots > 0 else { return [] }
        return order(items)
            .lazy
            .filter { !liveVideoIds.contains($0.videoId) && !$0.isWaitingForWiFi && !refused.contains($0.videoId) }
            .prefix(slots)
            .map(\.videoId)
    }

    public static func toReclaim(
        items: [Item],
        inProgress: Set<String>,
        waitingInSystem: Set<String>,
        limit: Int
    ) -> Set<String> {
        let keep = inProgress.union(nextToStart(items: items, liveVideoIds: inProgress, limit: limit))
        return waitingInSystem.subtracting(keep)
    }

    /// The positions to persist after a drag, as `videoId: position`.
    public static func positions(forOrder videoIds: [String]) -> [String: Int] {
        var positions: [String: Int] = [:]
        for (index, videoId) in videoIds.enumerated() {
            positions[videoId] = index
        }
        return positions
    }

    /// Applies a SwiftUI `onMove` to an ordered list of ids.
    public static func moving(_ videoIds: [String], fromOffsets source: IndexSet, toOffset destination: Int) -> [String] {
        let moved = source.compactMap { videoIds.indices.contains($0) ? videoIds[$0] : nil }
        guard !moved.isEmpty else { return videoIds }
        var reordered = videoIds
        for index in source.sorted(by: >) where reordered.indices.contains(index) {
            reordered.remove(at: index)
        }
        let insertionIndex = min(max(destination - source.count(where: { $0 < destination }), 0), reordered.count)
        reordered.insert(contentsOf: moved, at: insertionIndex)
        return reordered
    }
}
