
import Foundation

public struct PinnedItem: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case playlist, channel
    }

    public let kind: Kind
    /// `playlistId` / `channelId`.
    public let targetId: String
    /// Snapshot of the title at the moment of pinning (or the last successful refresh), so Home
    /// can draw the shelf before any fetch completes, and while offline.
    public var title: String?
    /// A playlist's channel name. Always `nil` for a channel.
    public var subtitle: String?
    /// `playlistThumbnail` / `channelThumbUrl` — a server-relative path, same as the live model.
    public var thumbnail: String?
    /// Seconds since 1970.
    public var pinnedAt: Double
    /// A tombstone: set when unpinned, so a merge from another device's older copy can't bring
    /// the pin back (see `PinnedItems.merge`'s own doc comment).
    public var unpinnedAt: Double?

    /// The kind is part of the key: a custom playlist's id is a UUID, not a YouTube id, while a
    /// channel id and a regular playlist's id both derive from the same YouTube id space — kind
    /// alone is what keeps the two from colliding.
    public var id: String { Self.id(kind: kind, targetId: targetId) }

    public static func id(kind: Kind, targetId: String) -> String {
        "\(kind.rawValue):\(targetId)"
    }

    public init(
        kind: Kind,
        targetId: String,
        title: String? = nil,
        subtitle: String? = nil,
        thumbnail: String? = nil,
        pinnedAt: Double,
        unpinnedAt: Double? = nil
    ) {
        self.kind = kind
        self.targetId = targetId
        self.title = title
        self.subtitle = subtitle
        self.thumbnail = thumbnail
        self.pinnedAt = pinnedAt
        self.unpinnedAt = unpinnedAt
    }
}

@MainActor
@Observable
public final class PinnedItems {
    /// Live pins only (no tombstones), newest `pinnedAt` first.
    public private(set) var items: [PinnedItem] = []

    /// D5: keeps the shelf a shelf, and stays far inside iCloud's 1 MB / 1024-key budget.
    private static let capacity = 30
    /// Tombstones older than this are trimmed on every persist, so the blob can't grow without
    /// bound on a device that pins and unpins things repeatedly.
    private static let tombstoneRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Every live pin AND every tombstone, keyed by `PinnedItem.id`. `items` is derived from this
    /// after every mutation; this is the thing that's actually persisted and merged.
    private var all: [String: PinnedItem] = [:]

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var storageKey: String
    /// See `PlaybackHistory`'s identical property for why this is `nonisolated(unsafe)`.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    public init(
        scope: String,
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.storageKey = "pinnedItems.\(ServerScope.digest(of: scope))"
        all = Self.read(from: defaults, key: storageKey)
        recomputeItems()
        if let cloud {
            merge(Self.read(fromCloud: cloud, key: storageKey))
            // Captures nothing but `self` — see `PlaybackHistory.init`'s identical comment.
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let store = self.cloud else { return }
                    self.merge(Self.read(fromCloud: store, key: self.storageKey))
                }
            }
            cloud.synchronize()
        }
    }

    public func adopt(scope: String, legacyScope: String? = nil) {
        let key = "pinnedItems.\(ServerScope.digest(of: scope))"
        guard key != storageKey else { return }
        storageKey = key
        all = Self.read(from: defaults, key: key)
        recomputeItems()
        if let cloud {
            merge(Self.read(fromCloud: cloud, key: key))
            cloud.synchronize()
        }
        importLegacy(legacyScope)
    }

    private func importLegacy(_ legacyScope: String?) {
        guard let legacyScope else { return }
        let legacyKey = "pinnedItems.\(ServerScope.digest(of: legacyScope))"
        guard legacyKey != storageKey else { return }
        var incoming = Self.read(from: defaults, key: legacyKey)
        if let cloud {
            for (id, entry) in Self.read(fromCloud: cloud, key: legacyKey) {
                if let existing = incoming[id], Self.lastEvent(existing) >= Self.lastEvent(entry) { continue }
                incoming[id] = entry
            }
        }
        let before = all
        merge(incoming)
        if all != before { persist() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func isPinned(_ kind: PinnedItem.Kind, id: String) -> Bool {
        // Deliberately not `all[key]?.unpinnedAt == nil` — optional chaining collapses "no such
        // entry" and "an entry with a nil `unpinnedAt`" to the same `nil == nil`, so that form
        // reports something that was never pinned as pinned.
        guard let entry = all[PinnedItem.id(kind: kind, targetId: id)] else { return false }
        return entry.unpinnedAt == nil
    }

    /// D5: the menu item disables itself at this point rather than letting a pin past the cap
    /// silently fail.
    public var isFull: Bool { items.count >= Self.capacity }

    public func pin(_ playlist: Playlist) {
        pin(
            kind: .playlist,
            targetId: playlist.id,
            title: playlist.playlistName,
            subtitle: playlist.playlistChannel,
            thumbnail: playlist.playlistThumbnail
        )
    }

    public func pin(_ channel: Channel) {
        pin(
            kind: .channel,
            targetId: channel.id,
            title: channel.channelName,
            subtitle: nil,
            thumbnail: channel.channelThumbUrl
        )
    }

    /// Keeps the entry rather than deleting it — see `merge`'s own doc comment for why a plain
    /// delete would let another device's older copy resurrect the pin.
    public func unpin(_ kind: PinnedItem.Kind, id: String) {
        let key = PinnedItem.id(kind: kind, targetId: id)
        guard var entry = all[key], entry.unpinnedAt == nil else { return }
        entry.unpinnedAt = Date().timeIntervalSince1970
        all[key] = entry
        recomputeItems()
        persist()
    }

    /// Updates a still-pinned target's snapshot from a fresh fetch. Never resurrects an unpinned
    /// target — an in-flight fetch started before the user unpinned something must not silently
    /// pin it back.
    public func refreshSnapshot(_ playlist: Playlist) {
        refreshSnapshot(kind: .playlist, targetId: playlist.id) {
            $0.title = playlist.playlistName
            $0.subtitle = playlist.playlistChannel
            $0.thumbnail = playlist.playlistThumbnail
        }
    }

    public func refreshSnapshot(_ channel: Channel) {
        refreshSnapshot(kind: .channel, targetId: channel.id) {
            $0.title = channel.channelName
            $0.thumbnail = channel.channelThumbUrl
        }
    }

    // MARK: - Merging

    /// The merge rule is the whole of sync correctness, and it can't be exercised through
    /// `NSUbiquitousKeyValueStore` in a host test run — this is how the tests reach it. See
    /// `PlaybackHistory.mergeForTesting`'s identical comment.
    internal func mergeForTesting(_ incoming: [String: PinnedItem]) {
        merge(incoming)
    }

    /// Test-only window onto the tombstones alongside the live pins — `items` deliberately hides
    /// them, so trimming can't otherwise be observed from outside.
    internal var allEntriesForTesting: [String: PinnedItem] { all }

    /// Per key, whichever side's most recent event — a pin or an unpin, whichever is later — wins.
    private func merge(_ incoming: [String: PinnedItem]) {
        guard !incoming.isEmpty else { return }
        var merged = all
        for (key, remote) in incoming {
            guard let local = merged[key] else {
                merged[key] = remote
                continue
            }
            if Self.lastEvent(remote) > Self.lastEvent(local) {
                merged[key] = remote
            }
        }
        guard merged != all else { return }
        all = merged
        trimTombstones()
        recomputeItems()
        // Written back locally only: whatever arrived is already in the cloud — see
        // `PlaybackHistory.merge`'s identical comment.
        defaults.set(Self.encode(all), forKey: storageKey)
    }

    private static func lastEvent(_ item: PinnedItem) -> Double {
        max(item.pinnedAt, item.unpinnedAt ?? 0)
    }

    // MARK: - Private

    private func pin(kind: PinnedItem.Kind, targetId: String, title: String?, subtitle: String?, thumbnail: String?) {
        // A re-pin of something already live just moves it to the front, which never grows
        // `items` — only a genuinely new pin needs the cap check.
        guard !isFull || isPinned(kind, id: targetId) else { return }
        let key = PinnedItem.id(kind: kind, targetId: targetId)
        all[key] = PinnedItem(
            kind: kind,
            targetId: targetId,
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            pinnedAt: Date().timeIntervalSince1970,
            unpinnedAt: nil
        )
        recomputeItems()
        persist()
    }

    private func refreshSnapshot(kind: PinnedItem.Kind, targetId: String, apply: (inout PinnedItem) -> Void) {
        let key = PinnedItem.id(kind: kind, targetId: targetId)
        guard var entry = all[key], entry.unpinnedAt == nil else { return }
        apply(&entry)
        all[key] = entry
        recomputeItems()
        persist()
    }

    private func recomputeItems() {
        items = all.values
            .filter { $0.unpinnedAt == nil }
            .sorted { $0.pinnedAt > $1.pinnedAt }
    }

    private func trimTombstones() {
        let cutoff = Date().timeIntervalSince1970 - Self.tombstoneRetention
        all = all.filter { entry in
            guard let unpinnedAt = entry.value.unpinnedAt else { return true }
            return unpinnedAt >= cutoff
        }
    }

    private func persist() {
        trimTombstones()
        let encoded = Self.encode(all)
        defaults.set(encoded, forKey: storageKey)
        cloud?.set(encoded, forKey: storageKey)
        cloud?.synchronize()
    }

    private static func encode(_ value: [String: PinnedItem]) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func read(from defaults: UserDefaults, key: String) -> [String: PinnedItem] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: PinnedItem].self, from: data)) ?? [:]
    }

    private static func read(fromCloud cloud: NSUbiquitousKeyValueStore, key: String) -> [String: PinnedItem] {
        guard let data = cloud.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: PinnedItem].self, from: data)) ?? [:]
    }
}
