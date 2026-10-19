
#if os(iOS)
import PleviCore
import SwiftUI

enum OfflineBatchSave {
    /// How many videos are prepared at once. Enough to keep the background session fed
    /// without turning "Save all" into several hundred simultaneous metadata requests — see
    /// the window in `saveAll`.
    static let maximumConcurrentSaves = 5

    /// How often, in prepared videos, the batch makes what it has prepared so far visible and
    /// pumps the queue — see `saveAll`.
    static let pumpInterval = 20

    /// Total bytes `videos` would add, for a free-space check and for telling the user what they are about to start.
    @MainActor
    static func estimatedBytes(_ videos: [Video], library: OfflineLibrary) -> Int {
        videos
            .filter { !library.isSaved(videoId: $0.id) }
            .reduce(into: 0) { $0 += ($1.mediaSize ?? 0) }
    }

    /// How many of `videos` are not already saved — what a confirmation should quote.
    @MainActor
    static func pendingCount(_ videos: [Video], library: OfflineLibrary) -> Int {
        videos.filter { !library.isSaved(videoId: $0.id) }.count
    }

    /// What a "Save All" is about to do, so the user can agree to it knowingly.
    struct Plan: Identifiable {
        let id = UUID()
        let videos: [Video]
        let count: Int
        let bytes: Int
        /// Nil when there is room. Otherwise why there is not.
        let shortfall: String?

        var message: String {
            let size = PleviFormatting.byteCount(bytes)
            if let shortfall { return shortfall }
            return "\(count) video\(count == 1 ? "" : "s"), about \(size)."
        }
    }

    @MainActor
    static func plan(_ videos: [Video], library: OfflineLibrary) -> Plan {
        let pending = videos.filter { !library.isSaved(videoId: $0.id) }
        let bytes = pending.reduce(into: 0) { $0 += ($1.mediaSize ?? 0) }
        // One check for the whole batch. `OfflineDiskSpace` already guards a single download,
        // but a batch where every video fits individually can still be far larger than the
        // disk, and discovering that on video 40 of 200 helps nobody.
        var shortfall: String?
        if let free = OfflineDiskSpace.availableCapacity(), bytes > free {
            shortfall = "This needs about \(PleviFormatting.byteCount(bytes)) but only "
                + "\(PleviFormatting.byteCount(free)) is free. Free up space or save fewer videos."
        }
        return Plan(videos: pending, count: pending.count, bytes: bytes, shortfall: shortfall)
    }

    @MainActor
    @discardableResult
    static func saveAll(
        _ videos: [Video],
        client: TAClient,
        library: OfflineLibrary,
        downloader: OfflineDownloader,
        allowsCellular: Bool
    ) async -> Int {
        let toSave = videos.filter { !library.isSaved(videoId: $0.id) }
        guard !toSave.isEmpty else { return 0 }
        // Preparing a channel — a thumbnail and every subtitle sidecar per video, through the proxy.
        let assertion = BackgroundAssertion(name: "Prepare saved videos")
        defer { assertion.end() }
        // A sliding window rather than every video at once.
        await withTaskGroup(of: Void.self) { group in
            var started = 0
            var prepared = 0
            for video in toSave {
                if started >= maximumConcurrentSaves {
                    await group.next()
                    prepared += 1
                    // Start transfers while the batch is still being prepared: as soon as the first video is ready, and every `pumpInterval` after.
                    if prepared == 1 || prepared.isMultiple(of: pumpInterval) {
                        await library.reload()
                        await downloader.pumpQueue()
                    }
                }
                started += 1
                group.addTask {
                    _ = await library.beginSave(video: video, client: client, skipReload: true)
                    guard let mediaPath = video.mediaUrl else { return }
                    // Registers the video WITHOUT pumping — the pumps in the loop above and
                    // after it do that. See `OfflineDownloader.enqueue`.
                    downloader.enqueue(videoId: video.id, mediaPath: mediaPath, client: client, allowsCellular: allowsCellular)
                }
            }
        }
        // Once per batch, not once per video — `beginSave`'s own `skipReload` doc comment.
        await library.reload()
        // Always pump after a reload, never before one.
        await downloader.pumpQueue()
        return toSave.count
    }
}
extension View {
    /// Asks before a "Save All" starts, with the count and the size — see `OfflineBatchSave.Plan`.
    func saveAllConfirmation(
        _ pending: Binding<OfflineBatchSave.Plan?>,
        perform: @escaping (OfflineBatchSave.Plan) -> Void
    ) -> some View {
        confirmationDialog(
            "Save All to iPhone",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { plan in
            if plan.shortfall == nil {
                Button("Save \(plan.count) Video\(plan.count == 1 ? "" : "s")") {
                    pending.wrappedValue = nil
                    perform(plan)
                }
            }
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
        } message: { plan in
            Text(plan.message)
        }
    }
}
#endif
