
import Foundation
import Observation

@Observable
@MainActor
public final class VideoCache {
    /// Enough to cover several screens of scrollback on any platform — a tvOS 4-up grid paging through a large channel is the heaviest case.
    public static let defaultLimit = 400

    private var byId: [String: Video] = [:]
    /// Insertion order, oldest first, so eviction has something to evict by. A plain array
    /// is right at this size: the only operations are append, and an occasional
    /// `removeFirst` when over the limit.
    private var order: [String] = []
    private let limit: Int

    public init(limit: Int = VideoCache.defaultLimit) {
        self.limit = max(1, limit)
    }

    /// Files one video, replacing any older copy of it. Re-filing an id already held
    /// refreshes the value but does not move it up the eviction order: the point is to
    /// bound memory, not to model recency precisely.
    public func store(_ video: Video) {
        let id = video.id
        if byId.updateValue(video, forKey: id) == nil {
            order.append(id)
            evictIfNeeded()
        }
    }

    public func store(_ videos: [Video]) {
        for video in videos { store(video) }
    }

    /// The last-seen copy, if this video has been on screen recently.
    public func video(id: String) -> Video? {
        byId[id]
    }

    public var count: Int { byId.count }

    private func evictIfNeeded() {
        while order.count > limit {
            let evicted = order.removeFirst()
            byId.removeValue(forKey: evicted)
        }
    }
}
