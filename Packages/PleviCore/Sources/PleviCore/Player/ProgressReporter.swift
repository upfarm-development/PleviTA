// Skip reporting in the first 10 s and the final 5% (match the web app).

import Foundation

@MainActor
public final class ProgressReporter {
    private let client: TAClient
    private let videoId: String
    private let duration: Double?
    private let outbox: OfflinePlaybackLedger?

    private(set) var lastReportedPosition: Double?
    private(set) var didMarkWatched = false

    public init(client: TAClient, videoId: String, duration: Double?, outbox: OfflinePlaybackLedger? = nil) {
        self.client = client
        self.videoId = videoId
        self.duration = duration
        self.outbox = outbox
    }

    @discardableResult
    public func reportProgress(position: Double, force: Bool = false) async -> Bool {
        guard isReportablePosition(position) else { return false }
        if !force, let lastReportedPosition, position >= lastReportedPosition, position - lastReportedPosition < 10 {
            return false
        }
        if let lastReportedPosition, abs(position - lastReportedPosition) < 0.5 {
            return false
        }
        lastReportedPosition = position
        do {
            _ = try await client.setProgress(videoId: videoId, position: position)
            // Noted rather than cleared. Clearing threw away the only local record of where
            // playback had got to, so a video watched ONLINE had no position to resume from
            // once the network went away — see `OfflineLedgerEntry.needsFlush`.
            outbox?.noteLocalPosition(videoId: videoId, position: position)
        } catch {
            // NOT restored, deliberately — see `previousPosition`'s own comment above.
            outbox?.recordFailedProgress(videoId: videoId, position: position)
        }
        return true
    }

    /// Call once when playback reaches `.ended`.
    public func markWatchedOnCompletion() async {
        guard !didMarkWatched else { return }
        didMarkWatched = true
        do {
            try await client.setWatched(id: videoId, isWatched: true)
            outbox?.clear(videoId: videoId)
        } catch {
            didMarkWatched = false
            outbox?.recordFailedWatched(videoId: videoId)
        }
    }

    func isReportablePosition(_ position: Double) -> Bool {
        guard position >= 10 else { return false }
        if let duration, duration > 0, position >= duration * 0.95 { return false }
        return true
    }
}
