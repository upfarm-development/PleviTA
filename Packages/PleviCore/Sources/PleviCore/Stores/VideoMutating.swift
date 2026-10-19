
@MainActor
public protocol VideoMutating: AnyObject {
    func setWatched(_ video: Video, isWatched: Bool) async
    /// Drop every local copy of this video from the lists this store owns.
    func removeVideoLocally(id: String)
}

/// Every list screen's store, so a video deleted from anywhere leaves all of them at once.
@MainActor
public final class VideoRemovalCenter {
    public static let shared = VideoRemovalCenter()

    private final class Weak {
        weak var store: (any VideoMutating)?
        init(_ store: any VideoMutating) { self.store = store }
    }

    private var stores: [Weak] = []

    public func register(_ store: any VideoMutating) {
        stores.removeAll { $0.store == nil }
        stores.append(Weak(store))
    }

    public func removeEverywhere(id: String) {
        stores.removeAll { $0.store == nil }
        for entry in stores { entry.store?.removeVideoLocally(id: id) }
    }
}
