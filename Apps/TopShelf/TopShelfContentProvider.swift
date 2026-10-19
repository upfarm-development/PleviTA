import Foundation
// TVServices predates Swift concurrency and carries no Sendable audit at all (its completion-handler block type included).
@preconcurrency import TVServices
import PleviCore

final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in
            completionHandler(await Self.buildContent())
        }
    }

    /// Bounded and best-effort throughout: no stored credential yet, the server unreachable from wherever tvOS happens to run this process, a decode error.
    @MainActor
    private static func buildContent() async -> TVTopShelfContent? {
        let credentialStore = KeychainCredentialStore.platformDefault
        guard let serverURL = credentialStore.serverURL(),
              credentialStore.token() != nil || credentialStore.sessionCredential() != nil
        else {
            return nil
        }

        let client = TAClient(serverURL: serverURL, credentialStore: credentialStore)
        let fetchedVideos: [Video]
        do {
            let page = try await client.videos(VideoListQuery(watch: .continue))
            fetchedVideos = page.data
        } catch {
            return nil
        }
        guard !fetchedVideos.isEmpty else { return nil }

        // Same "recently played first" ordering `HomeStore` applies to this row on the main app, scoped by server the same way `RootView` does it.
        let appSettings = AppSettings(defaults: KeychainCredentialStore.sharedDefaults)
        let playbackHistory = PlaybackHistory(
            // The same key the main app files it under: see `ServerScope.syncScope`.
            scope: credentialStore.syncScope() ?? serverURL.absoluteString,
            defaults: KeychainCredentialStore.sharedDefaults,
            cloud: nil
        )
        let orderedVideos = playbackHistory.ordered(fetchedVideos, recentlyPlayedFirst: appSettings.recentlyPlayedFirst)

        var items: [TVTopShelfSectionedItem] = []
        for video in orderedVideos.prefix(5) {
            let item = TVTopShelfSectionedItem(identifier: video.id)
            item.title = video.title
            item.imageShape = .hdtv
            if let thumbPath = video.vidThumbUrl,
               let imageURL = await cachedThumbnailURL(client: client, path: thumbPath, videoId: video.id) {
                item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            }
            // `player.progress` is a 0...100 percentage on this model (see `VideoRow.swift`'s identical `progress / 100` conversion for its own progress bar).
            if let progress = video.player?.progress {
                item.playbackProgress = min(max(progress / 100, 0), 1)
            }
            if let linkURL = URL(string: "plevita://video/\(video.id)") {
                let action = TVTopShelfAction(url: linkURL)
                item.displayAction = action
                item.playAction = action
            }
            items.append(item)
        }

        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "Continue Watching"
        return TVTopShelfSectionedContent(sections: [collection])
    }

    private static func cachedThumbnailURL(client: TAClient, path: String, videoId: String) async -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: KeychainCredentialStore.appGroupIdentifier
        ) else {
            return nil
        }
        let directory = containerURL.appendingPathComponent("TopShelfThumbnails", isDirectory: true)
        let fileURL = directory.appendingPathComponent("\(videoId).jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try await client.fetchMedia(path: path)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
}
