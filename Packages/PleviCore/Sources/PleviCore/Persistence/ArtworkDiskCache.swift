// Thumbnails, avatars and channel art kept on the device, so they are there on a slow or absent connection.

import CryptoKit
import Foundation

public actor ArtworkDiskCache {
    struct Entry: Codable, Equatable, Sendable {
        var file: String
        var bytes: Int
        var contentHash: String
        var fetchedAt: Double
        var lastAccess: Double
    }

    public enum StoreOutcome: Equatable, Sendable { case added, replaced, unchanged }

    /// How long an image is trusted before it is quietly fetched again.
    public static let freshness: TimeInterval = 7 * 24 * 3600
    /// How long an image can go unused before it is dropped whatever the limit.
    public static let unusedLifetime: TimeInterval = 90 * 24 * 3600

    private let directory: URL
    private var limitBytes: Int
    private var index: [String: Entry] = [:]
    private var isLoaded = false
    private var isDirty = false
    private var lastIndexWrite = Date.distantPast

    public init(directory: URL, limitBytes: Int) {
        self.directory = directory
        self.limitBytes = limitBytes
    }

    /// `…/Application Support/PleviTA/Artwork/<digest of the login URL>`.
    public static func directory(forScope loginURL: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PleviTA", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
            .appendingPathComponent(ServerScope.digest(of: loginURL), isDirectory: true)
    }

    // MARK: - Reading

    /// The cached bytes for a server path, if any, and whether they are old enough to fetch again.
    public func lookup(path: String, now: Date = Date()) -> (data: Data, isStale: Bool)? {
        loadIndexIfNeeded()
        guard var entry = index[path] else { return nil }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(entry.file)) else {
            // The index says it is here and the file is gone: forget it.
            index.removeValue(forKey: path)
            isDirty = true
            return nil
        }
        entry.lastAccess = now.timeIntervalSince1970
        index[path] = entry
        isDirty = true
        writeIndexIfDue(now: now)
        return (data, now.timeIntervalSince1970 - entry.fetchedAt > Self.freshness)
    }

    // MARK: - Writing

    /// Keeps `data` as the image for `path`. If there was already one with different bytes, the old
    /// file is replaced rather than kept beside it. Then the cache is brought back under its limit.
    @discardableResult
    public func store(path: String, data: Data, now: Date = Date()) -> StoreOutcome {
        loadIndexIfNeeded()
        let hash = Self.hash(of: data)
        let stamp = now.timeIntervalSince1970

        if var existing = index[path], existing.contentHash == hash {
            // Same image: it is current again, nothing to write.
            existing.fetchedAt = stamp
            existing.lastAccess = stamp
            index[path] = existing
            isDirty = true
            writeIndexIfDue(now: now)
            return .unchanged
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var markExcluded = false
        if !FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent(".excluded").path) {
            markExcluded = true
        }
        let file = Self.fileName(for: path)
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            return .unchanged
        }
        let outcome: StoreOutcome = index[path] == nil ? .added : .replaced
        index[path] = Entry(file: file, bytes: data.count, contentHash: hash, fetchedAt: stamp, lastAccess: stamp)
        isDirty = true
        if markExcluded { excludeFromBackup() }
        prune(now: now)
        writeIndex(now: now)
        return outcome
    }

    // MARK: - Size, limit, clearing

    public var usedBytes: Int {
        loadIndexIfNeeded()
        return index.values.reduce(0) { $0 + $1.bytes }
    }

    public var count: Int {
        loadIndexIfNeeded()
        return index.count
    }

    public func setLimit(bytes: Int) {
        limitBytes = bytes
        loadIndexIfNeeded()
        prune(now: Date())
        writeIndex(now: Date())
    }

    /// Removes every image in this server's cache.
    public func clear() {
        loadIndexIfNeeded()
        for entry in index.values { try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file)) }
        index.removeAll()
        isDirty = true
        writeIndex(now: Date())
    }

    /// Drops what has gone unused too long, then the least recently used until under the limit.
    public func prune(now: Date = Date()) {
        loadIndexIfNeeded()
        let doomed = Self.keysToEvict(
            entries: index.mapValues { ($0.bytes, $0.lastAccess) },
            limitBytes: limitBytes,
            now: now.timeIntervalSince1970
        )
        guard !doomed.isEmpty else { return }
        for key in doomed {
            if let entry = index.removeValue(forKey: key) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
            }
        }
        isDirty = true
    }

    /// Which keys to remove, as a pure function so the rules can be tested: anything unused for
    /// `unusedLifetime`, then oldest-accessed first until the total fits the limit.
    nonisolated static func keysToEvict(entries: [String: (bytes: Int, lastAccess: Double)], limitBytes: Int, now: Double) -> [String] {
        var doomed: [String] = []
        var remaining = entries
        for (key, value) in entries where now - value.lastAccess > unusedLifetime {
            doomed.append(key)
            remaining.removeValue(forKey: key)
        }
        var total = remaining.values.reduce(0) { $0 + $1.bytes }
        for (key, value) in remaining.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard total > limitBytes else { break }
            doomed.append(key)
            total -= value.bytes
        }
        return doomed
    }

    // MARK: - Index

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func loadIndexIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            index = decoded
        }
    }

    private func writeIndexIfDue(now: Date) {
        guard isDirty, now.timeIntervalSince(lastIndexWrite) > 30 else { return }
        writeIndex(now: now)
    }

    private func writeIndex(now: Date) {
        guard isDirty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
        isDirty = false
        lastIndexWrite = now
    }

    /// An image cache is not worth backing up; it can be fetched again.
    private func excludeFromBackup() {
        var url = directory.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        FileManager.default.createFile(atPath: url.appendingPathComponent(".excluded").path, contents: nil)
    }

    nonisolated static func fileName(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".img"
    }

    nonisolated static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
