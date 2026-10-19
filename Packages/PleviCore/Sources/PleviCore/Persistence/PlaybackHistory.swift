
import Foundation

@MainActor
@Observable
public final class PlaybackHistory {
    /// Video id → when it was last started, as seconds since 1970.
    public private(set) var playedAt: [String: Double] = [:]

    /// Enough to lead the row with, small enough to stay far inside iCloud's 1 MB / 1024-key
    /// budget even with several servers in play.
    private static let capacity = 50

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var storageKey: String
    /// When another device's history last arrived, and how many times it has. For the diagnostics
    /// line in Settings: "does this device ever hear from the other one" is otherwise invisible.
    public private(set) var lastExternalMergeAt: Date?
    public private(set) var externalMergeCount = 0
    /// `nonisolated(unsafe)` so `deinit` — which is never main-actor isolated, whatever the class says — can unregister.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    public init(
        scope: String,
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        // Hashed rather than raw: a server URL is not something to leave lying around in a defaults key, and the key only needs to be stable and distinct.
        self.storageKey = "playbackHistory.\(ServerScope.digest(of: scope))"
        playedAt = Self.read(from: defaults, key: storageKey)
        if let cloud {
            merge(Self.read(fromCloud: cloud, key: storageKey))
            // Captures nothing but `self`: `NSUbiquitousKeyValueStore` is not `Sendable`, so the
            // store is reached through the (main-actor) property inside instead of captured.
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let store = self.cloud else { return }
                    self.noteExternalChange()
                    self.merge(Self.read(fromCloud: store, key: self.storageKey))
                }
            }
            cloud.synchronize()
        }
    }

    /// Points this history at a (possibly different) server.
    public func adopt(scope: String, legacyScope: String? = nil) {
        let key = "playbackHistory.\(ServerScope.digest(of: scope))"
        guard key != storageKey else { return }
        storageKey = key
        playedAt = Self.read(from: defaults, key: key)
        if let cloud {
            merge(Self.read(fromCloud: cloud, key: key))
            cloud.synchronize()
        }
        importLegacy(legacyScope)
    }

    private func importLegacy(_ legacyScope: String?) {
        guard let legacyScope else { return }
        let legacyKey = "playbackHistory.\(ServerScope.digest(of: legacyScope))"
        guard legacyKey != storageKey else { return }
        var incoming = Self.read(from: defaults, key: legacyKey)
        if let cloud {
            for (id, time) in Self.read(fromCloud: cloud, key: legacyKey) where time > (incoming[id] ?? 0) { incoming[id] = time }
        }
        let before = playedAt
        merge(incoming)
        if playedAt != before { persist() }
    }

    /// Asks iCloud for anything newer and merges it. Called when the app comes back to the
    /// foreground: the system only pushes changes when it chooses to, and a device that has been
    /// suspended may not have heard the last one.
    public func refreshFromCloud() {
        guard let cloud else { return }
        cloud.synchronize()
        merge(Self.read(fromCloud: cloud, key: storageKey))
    }

    private func noteExternalChange() {
        lastExternalMergeAt = Date()
        externalMergeCount += 1
        PlaybackLog.shared.log("hist", "iCloud delivered a change (#\(externalMergeCount)); entries before merge=\(playedAt.count)")
    }

    /// One line for Settings, so the two devices can be compared: which server key this history is
    /// filed under (it differs if the devices signed in with different addresses), whether iCloud is
    /// available at all, how many videos it holds, and whether the other device ever got through.
    public var diagnosticsSummary: String {
        let key = String(storageKey.dropFirst("playbackHistory.".count))
        // `ubiquityIdentityToken` answers "is iCloud Drive available", which says nothing about the
        // key-value store this history uses, and Apple TV has no iCloud Drive at all, so it would
        // read "off" there while syncing fine. Only iPhone and iPad can say.
        #if os(tvOS)
        let account = "iCloud account not checkable on Apple TV"
        #else
        let account = FileManager.default.ubiquityIdentityToken != nil ? "iCloud Drive on" : "iCloud Drive off"
        #endif
        let received: String
        if let at = lastExternalMergeAt {
            received = "last from another device " + at.formatted(date: .abbreviated, time: .shortened)
        } else {
            received = "nothing from another device yet"
        }
        return "server \(key) · \(account) · \(playedAt.count) videos · \(received)"
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Records that this device has just started playing `videoId`.
    public func record(_ videoId: String, at date: Date = Date()) {
        PlaybackLog.shared.log("hist", "recorded start of \(videoId) cloud=\(cloud != nil)")
        playedAt[videoId] = date.timeIntervalSince1970
        trim()
        persist()
    }

    /// Drops a video that is no longer in progress — it was marked watched, or the server has
    /// stopped reporting it.
    public func forget(_ videoId: String) {
        guard playedAt.removeValue(forKey: videoId) != nil else { return }
        persist()
    }

    public func clear() {
        playedAt = [:]
        defaults.removeObject(forKey: storageKey)
        cloud?.removeObject(forKey: storageKey)
        cloud?.synchronize()
    }

    /// The ids this user played most recently, newest first.
    public func mostRecent(limit: Int) -> [String] {
        playedAt.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    /// Leads `videos` with what this user actually watched most recently, newest first, and leaves everything else in the order it was given.
    public func ordered(_ videos: [Video], recentlyPlayedFirst: Bool) -> [Video] {
        guard recentlyPlayedFirst else { return videos }
        let recent = mostRecent(limit: 10)
        guard !recent.isEmpty else { return videos }
        let byID = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = recent.compactMap { byID[$0] }
        guard !pinned.isEmpty else { return videos }
        let pinnedIDs = Set(pinned.map(\.id))
        return pinned + videos.filter { !pinnedIDs.contains($0.id) }
    }

    // MARK: - Merging

    /// Per-key newest-wins, never whole-dictionary last-writer-wins.
    internal func mergeForTesting(_ incoming: [String: Double]) {
        merge(incoming)
    }

    private func merge(_ incoming: [String: Double]) {
        guard !incoming.isEmpty else { return }
        var merged = playedAt
        for (id, timestamp) in incoming where timestamp > (merged[id] ?? 0) {
            merged[id] = timestamp
        }
        guard merged != playedAt else { return }
        playedAt = merged
        trim()
        // Written back locally only: whatever arrived is already in the cloud, and echoing it
        // straight back would be a write per device per change.
        defaults.set(playedAt, forKey: storageKey)
    }

    private func trim() {
        guard playedAt.count > Self.capacity else { return }
        let keep = playedAt.sorted { $0.value > $1.value }.prefix(Self.capacity)
        playedAt = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        defaults.set(playedAt, forKey: storageKey)
        cloud?.set(playedAt, forKey: storageKey)
        cloud?.synchronize()
    }

    private static func read(from defaults: UserDefaults, key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private static func read(fromCloud cloud: NSUbiquitousKeyValueStore, key: String) -> [String: Double] {
        cloud.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
