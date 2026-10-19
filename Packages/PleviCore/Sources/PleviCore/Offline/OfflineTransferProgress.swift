// Live byte counts and speed for transfers in flight, held apart from `OfflineLibrary.entries`.

import Foundation
import Observation

@MainActor
@Observable
public final class OfflineTransferProgress {
    public struct Sample: Equatable, Sendable {
        public var receivedByteCount: Int
        public var expectedByteCount: Int?
        /// Smoothed, so the figure on screen does not jitter with every chunk. `nil` until two
        /// ticks have been seen.
        public var bytesPerSecond: Double?
    }

    public private(set) var samples: [String: Sample] = [:]
    private var sampledAt: [String: Date] = [:]

    public init() {}

    public func update(videoId: String, receivedByteCount: Int, expectedByteCount: Int?, at date: Date = Date()) {
        let previous = samples[videoId]
        var speed = previous?.bytesPerSecond
        if let previous, let before = sampledAt[videoId] {
            speed = Self.smoothedSpeed(
                previous: previous.bytesPerSecond,
                byteDelta: receivedByteCount - previous.receivedByteCount,
                elapsed: date.timeIntervalSince(before)
            )
        }
        samples[videoId] = Sample(
            receivedByteCount: receivedByteCount,
            expectedByteCount: expectedByteCount ?? previous?.expectedByteCount,
            bytesPerSecond: speed
        )
        sampledAt[videoId] = date
    }

    public func remove(videoId: String) {
        samples.removeValue(forKey: videoId)
        sampledAt.removeValue(forKey: videoId)
    }

    /// Drops the samples of anything that is no longer transferring, after a reload.
    public func prune(keeping videoIds: Set<String>) {
        for id in samples.keys where !videoIds.contains(id) { remove(videoId: id) }
    }

    /// Exponential moving average of the instantaneous rate. A tick too close to the last one to
    /// measure, or one that went backwards (a restarted transfer), leaves the figure as it was.
    nonisolated static func smoothedSpeed(previous: Double?, byteDelta: Int, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0.05, byteDelta >= 0 else { return previous }
        let instantaneous = Double(byteDelta) / elapsed
        guard let previous else { return instantaneous }
        return previous * 0.6 + instantaneous * 0.4
    }
}
