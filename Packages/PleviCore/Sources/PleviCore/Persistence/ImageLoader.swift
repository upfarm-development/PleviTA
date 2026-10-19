
import Foundation
import CoreGraphics
import ImageIO

public actor ImageLoader {
    private let client: TAClient
    private let cache = NSCache<NSString, CachedImage>()
    private var inFlight: [String: Task<CGImage, Error>] = [:]
    private let localBytesProvider: (@Sendable (String) -> Data?)?
    /// Images kept on disk between launches and while offline. See `ArtworkDiskCache`.
    private let diskCache: ArtworkDiskCache?

    public init(
        client: TAClient,
        localBytesProvider: (@Sendable (String) -> Data?)? = nil,
        diskCache: ArtworkDiskCache? = nil
    ) {
        self.client = client
        self.localBytesProvider = localBytesProvider
        self.diskCache = diskCache
    }

    public func image(forPath path: String, maxPixelSize: CGFloat) async throws -> CGImage {
        let key = cacheKey(path: path, maxPixelSize: maxPixelSize)

        if let cached = cache.object(forKey: key as NSString) {
            return cached.image
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let client = client
        let localBytesProvider = localBytesProvider
        let diskCache = diskCache
        let task = Task<CGImage, Error> {
            let data: Data
            if let localBytesProvider, let localData = localBytesProvider(path) {
                data = localData
            } else if let diskCache, let hit = await diskCache.lookup(path: path) {
                data = hit.data
                if hit.isStale {
                    // Shown now, checked in the background: if the server's copy differs, the
                    // cache keeps the new one and drops the old.
                    Task.detached(priority: .utility) {
                        if let fresh = try? await client.fetchMedia(path: path) {
                            await diskCache.store(path: path, data: fresh)
                        }
                    }
                }
            } else {
                data = try await client.fetchMedia(path: path)
                if let diskCache { await diskCache.store(path: path, data: data) }
            }
            guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                throw TAError.decoding("Could not decode image data at \(path)")
            }
            return image
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let image = try await task.value
        cache.setObject(CachedImage(image: image), forKey: key as NSString)
        return image
    }

    /// Drops every cached decoded image (e.g. on sign-out, so a later login
    /// to a different server never shows a stale thumbnail from this run).
    public func clearCache() {
        cache.removeAllObjects()
    }

    private func cacheKey(path: String, maxPixelSize: CGFloat) -> String {
        "\(path)#\(Int(maxPixelSize))"
    }

    nonisolated private static func downsample(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }
}

/// `NSCache` needs an `AnyObject` value; boxing `CGImage` this way sidesteps
/// any doubt about its own bridging rather than relying on it.
private final class CachedImage {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}
