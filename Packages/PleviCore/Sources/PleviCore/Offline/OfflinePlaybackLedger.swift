
import Foundation
import Observation

/// One video's outstanding playback report — the merge of whatever `ProgressReporter` couldn't deliver.
public struct OfflineLedgerEntry: Codable, Sendable, Equatable {
    public var position: Double?
    public var watched: Bool
    /// Seconds since 1970 — when this entry was last written, so `OfflineProgressPolicy` can
    /// drop one that's aged out rather than flush stale data years later.
    public var stampedAt: Double
    /// Whether the server still needs telling, as opposed to this being a local note of where playback got to.
    public var needsFlush: Bool

    public init(position: Double?, watched: Bool, stampedAt: Double, needsFlush: Bool = true) {
        self.position = position
        self.watched = watched
        self.stampedAt = stampedAt
        self.needsFlush = needsFlush
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Double.self, forKey: .position)
        watched = (try? c.decode(Bool.self, forKey: .watched)) ?? false
        stampedAt = (try? c.decode(Double.self, forKey: .stampedAt)) ?? 0
        // Absent in anything written before this field existed, and everything written then
        // was a failure — so the old meaning is `true`.
        needsFlush = ((try? c.decodeIfPresent(Bool.self, forKey: .needsFlush)) ?? nil) ?? true
    }
}

extension Video {
    /// This video with the ledger's local watch state laid over it.
    public func applyingOfflineLedger(_ entry: OfflineLedgerEntry?) -> Video {
        guard let entry else { return self }
        var video = self
        var player = video.player ?? VideoPlayerState(
            duration: nil, durationStr: nil, watched: nil, position: nil, progress: nil
        )
        if player.position == nil { player.position = entry.position }
        if entry.watched { player.watched = true }
        if player.progress == nil, player.watched != true,
           let position = player.position, position > 0,
           let duration = player.duration, duration > 0 {
            player.progress = min(position / duration * 100, 100)
        }
        video.player = player
        return video
    }
}

@MainActor
@Observable
public final class OfflinePlaybackLedger {
    /// Far more headroom than any real offline shelf needs, while still bounding a `UserDefaults` dictionary that only ever grows on a POST failure.
    private static let capacity = 200

    public private(set) var entries: [String: OfflineLedgerEntry] = [:]
    private let defaults: UserDefaults
    private var storageKey: String

    public init(scope: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storageKey = "offlinePlaybackLedger.\(ServerScope.digest(of: scope))"
        entries = Self.read(from: defaults, key: storageKey)
    }

    /// Points this ledger at a (possibly different) server — same deferred-scoping pattern as
    /// `PlaybackHistory.adopt(scope:)`, for the same reason: the scope isn't known until
    /// someone signs in.
    public func adopt(scope: String) {
        let key = "offlinePlaybackLedger.\(ServerScope.digest(of: scope))"
        guard key != storageKey else { return }
        storageKey = key
        entries = Self.read(from: defaults, key: key)
    }

    /// A failed `reportProgress` — merged in, never overwriting an already-recorded `watched`.
    public func recordFailedProgress(videoId: String, position: Double, at date: Date = Date()) {
        if let existing = entries[videoId], existing.watched { return }
        entries[videoId] = OfflineLedgerEntry(position: position, watched: false, stampedAt: date.timeIntervalSince1970)
        trim()
        persist()
    }

    public func recordFailedWatched(videoId: String, at date: Date = Date()) {
        entries[videoId] = OfflineLedgerEntry(position: nil, watched: true, stampedAt: date.timeIntervalSince1970)
        trim()
        persist()
    }

    /// A later report for the same video succeeded, or a flush delivered this entry — either way there is nothing left to retry.
    public func noteLocalPosition(videoId: String, position: Double, at date: Date = Date()) {
        let existing = entries[videoId]
        entries[videoId] = OfflineLedgerEntry(
            position: position,
            watched: false,
            stampedAt: date.timeIntervalSince1970,
            needsFlush: false
        )
        if existing?.watched == true, existing?.needsFlush == true {
            // A watched flag still owed to the server outranks a position note.
            entries[videoId] = existing
        }
        persist()
        trim()
    }

    /// Remembers what the server says about a saved video — how far through it is, or that it is watched.
    public func noteServerState(videoId: String, position: Double?, watched: Bool, at date: Date = Date()) {
        if entries[videoId]?.needsFlush == true { return }
        if !watched, position == nil {
            guard entries.removeValue(forKey: videoId) != nil else { return }
            persist()
            return
        }
        let entry = OfflineLedgerEntry(position: watched ? nil : position, watched: watched, stampedAt: date.timeIntervalSince1970, needsFlush: false)
        guard entries[videoId] != entry else { return }
        entries[videoId] = entry
        persist()
        trim()
    }

    public func clear(videoId: String) {
        guard entries.removeValue(forKey: videoId) != nil else { return }
        persist()
    }

    public func entry(for videoId: String) -> OfflineLedgerEntry? {
        entries[videoId]
    }

    private func trim() {
        guard entries.count > Self.capacity else { return }
        let keep = entries.sorted { $0.value.stampedAt > $1.value.stampedAt }.prefix(Self.capacity)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func read(from defaults: UserDefaults, key: String) -> [String: OfflineLedgerEntry] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: OfflineLedgerEntry].self, from: data)) ?? [:]
    }
}
