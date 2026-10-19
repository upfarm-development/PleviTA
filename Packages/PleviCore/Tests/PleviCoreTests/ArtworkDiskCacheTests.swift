import Foundation
import Testing
@testable import PleviCore

@Suite("ArtworkDiskCache")
struct ArtworkDiskCacheTests {
    private func makeCache(limit: Int = 1_000_000) -> ArtworkDiskCache {
        ArtworkDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)"), limitBytes: limit)
    }

    private func bytes(_ count: Int, fill: UInt8 = 1) -> Data { Data(repeating: fill, count: count) }

    @Test("a stored image comes back, fresh")
    func storeAndLookup() async {
        let cache = makeCache()
        let now = Date(timeIntervalSince1970: 1_000_000)
        await cache.store(path: "/cache/a.jpg", data: bytes(10), now: now)
        let hit = await cache.lookup(path: "/cache/a.jpg", now: now.addingTimeInterval(60))
        #expect(hit?.data == bytes(10))
        #expect(hit?.isStale == false)
        #expect(await cache.lookup(path: "/cache/missing.jpg") == nil)
    }

    @Test("an image older than the freshness window is still served, marked stale")
    func staleAfterAWeek() async {
        let cache = makeCache()
        let now = Date(timeIntervalSince1970: 1_000_000)
        await cache.store(path: "/a", data: bytes(10), now: now)
        let hit = await cache.lookup(path: "/a", now: now.addingTimeInterval(ArtworkDiskCache.freshness + 1))
        #expect(hit?.isStale == true)
        #expect(hit?.data.count == 10)
    }

    @Test("storing different bytes for the same path replaces the old image, same bytes change nothing")
    func newerReplacesOlder() async {
        let cache = makeCache()
        #expect(await cache.store(path: "/a", data: bytes(10, fill: 1)) == .added)
        #expect(await cache.store(path: "/a", data: bytes(10, fill: 1)) == .unchanged)
        #expect(await cache.store(path: "/a", data: bytes(20, fill: 2)) == .replaced)
        #expect(await cache.count == 1)
        #expect(await cache.usedBytes == 20)
        #expect(await cache.lookup(path: "/a")?.data == bytes(20, fill: 2))
    }

    @Test("a refetch of the same image makes it fresh again")
    func unchangedRefreshesTheClock() async {
        let cache = makeCache()
        let old = Date(timeIntervalSince1970: 1_000_000)
        await cache.store(path: "/a", data: bytes(10), now: old)
        let later = old.addingTimeInterval(ArtworkDiskCache.freshness * 2)
        await cache.store(path: "/a", data: bytes(10), now: later)
        #expect(await cache.lookup(path: "/a", now: later.addingTimeInterval(10))?.isStale == false)
    }

    @Test("over the limit, the least recently used go first")
    func evictsLeastRecentlyUsed() async {
        let cache = makeCache(limit: 25)
        let t = Date(timeIntervalSince1970: 1_000_000)
        await cache.store(path: "/old", data: bytes(10, fill: 1), now: t)
        await cache.store(path: "/mid", data: bytes(10, fill: 2), now: t.addingTimeInterval(10))
        // Asking for /old makes /mid the least recently used.
        _ = await cache.lookup(path: "/old", now: t.addingTimeInterval(20))
        await cache.store(path: "/new", data: bytes(10, fill: 3), now: t.addingTimeInterval(30))
        #expect(await cache.lookup(path: "/mid", now: t.addingTimeInterval(40)) == nil)
        #expect(await cache.lookup(path: "/old", now: t.addingTimeInterval(40)) != nil)
        #expect(await cache.lookup(path: "/new", now: t.addingTimeInterval(40)) != nil)
    }

    @Test("lowering the limit trims the cache at once")
    func loweringTheLimit() async {
        let cache = makeCache(limit: 1000)
        for i in 0..<5 { await cache.store(path: "/\(i)", data: bytes(100, fill: UInt8(i)), now: Date(timeIntervalSince1970: 1_000_000 + Double(i))) }
        #expect(await cache.usedBytes == 500)
        await cache.setLimit(bytes: 250)
        #expect(await cache.usedBytes <= 250)
    }

    @Test("clearing removes everything")
    func clearing() async {
        let cache = makeCache()
        await cache.store(path: "/a", data: bytes(10))
        await cache.clear()
        #expect(await cache.count == 0)
        #expect(await cache.lookup(path: "/a") == nil)
    }

    @Test("an image unused for a quarter of a year is dropped whatever the limit")
    func unusedLifetime() {
        let now = 10_000_000.0
        let doomed = ArtworkDiskCache.keysToEvict(
            entries: ["stale": (bytes: 1, lastAccess: now - ArtworkDiskCache.unusedLifetime - 1), "recent": (bytes: 1, lastAccess: now - 10)],
            limitBytes: 1_000_000,
            now: now
        )
        #expect(doomed == ["stale"])
    }

    @Test("the cache survives a relaunch")
    func persistsAcrossInstances() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)")
        let first = ArtworkDiskCache(directory: directory, limitBytes: 1_000_000)
        await first.store(path: "/a", data: bytes(10))
        let second = ArtworkDiskCache(directory: directory, limitBytes: 1_000_000)
        #expect(await second.lookup(path: "/a")?.data == bytes(10))
    }
}
