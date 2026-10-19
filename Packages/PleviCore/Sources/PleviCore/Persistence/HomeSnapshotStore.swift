// A copy of what Home last showed, kept on the device: the Continue Watching row and the first page of Newly Added, per server.

import Foundation

public struct HomeSnapshot: Codable, Sendable, Equatable {
    public var continueWatching: [Video]
    public var newlyAdded: [Video]
    /// The sort/filter query `newlyAdded` was fetched with. A snapshot taken under different
    /// settings is not Home's current list, so its grid half is ignored (Continue Watching does
    /// not depend on those settings).
    public var queryKey: String
    public var savedAt: Date

    public init(continueWatching: [Video], newlyAdded: [Video], queryKey: String, savedAt: Date = Date()) {
        self.continueWatching = continueWatching
        self.newlyAdded = newlyAdded
        self.queryKey = queryKey
        self.savedAt = savedAt
    }
}

public struct HomeSnapshotStore: Sendable {
    /// How many videos of the grid's first page are kept.
    public static let gridLimit = 24

    private let directory: URL

    public init(directory: URL = HomeSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PleviTA", isDirectory: true).appendingPathComponent("HomeSnapshots", isDirectory: true)
    }

    private func fileURL(scope: String) -> URL {
        directory.appendingPathComponent("\(ServerScope.digest(of: scope)).json")
    }

    public func load(scope: String) -> HomeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(scope: scope)) else { return nil }
        return try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }

    public func save(_ snapshot: HomeSnapshot, scope: String) {
        var trimmed = snapshot
        trimmed.newlyAdded = Array(snapshot.newlyAdded.prefix(Self.gridLimit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(scope: scope), options: .atomic)
    }

    public func remove(scope: String) {
        try? FileManager.default.removeItem(at: fileURL(scope: scope))
    }
}
