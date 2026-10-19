
import Foundation
import Observation

// Not `public` — like `Route`/`AppShellView` it lives in `Apps/Shared`,
// compiled straight into both app targets rather than a separate module,
// so `internal` (the default) is all any of this needs.
@Observable
@MainActor
final class DeepLinkRouter {
    private(set) var pendingRoute: Route?

    init() {}

    /// Parses `plevita://video/<youtubeId>` — host `"video"`, one path component, the video's `id` (`Video.youtubeId`) — into `Route.video`.
    func handle(_ url: URL) {
        guard url.scheme == "plevita", url.host == "video" else { return }
        let id = url.pathComponents.first { $0 != "/" }
        guard let id, !id.isEmpty else { return }
        pendingRoute = .video(id)
    }

    /// Called once a host has actually pushed `pendingRoute` onto its own
    /// stack, so the same link doesn't get pushed a second time on some
    /// later, unrelated re-evaluation.
    func consumePendingRoute() {
        pendingRoute = nil
    }
}
