
import Foundation

public enum OfflineProgressSync {
    /// Never throws — one video's failure (a timeout, a 5xx) must not stop the rest of the
    /// queue, and must leave that entry queued for the next flush attempt rather than losing it.
    @MainActor
    public static func flush(ledger: OfflinePlaybackLedger, client: TAClient, now: Date = Date()) async {
        // Only what the server has not been told. A `needsFlush == false` entry is a local
        // note of where playback reached, kept so an offline open can resume — see
        // `OfflineLedgerEntry.needsFlush`.
        for (videoId, entry) in ledger.entries where entry.needsFlush {
            let serverWatched: Bool?
            do {
                let video = try await client.video(id: videoId)
                serverWatched = video.player?.watched
            } catch TAError.notFound {
                ledger.clear(videoId: videoId)
                continue
            } catch {
                // Couldn't even check — leave the entry queued and try again on the next flush.
                continue
            }

            switch OfflineProgressPolicy.decide(entry: entry, serverWatched: serverWatched, now: now) {
            case .dropServerAlreadyWatched, .dropTooOld:
                ledger.clear(videoId: videoId)
            case .flush:
                do {
                    if entry.watched {
                        try await client.setWatched(id: videoId, isWatched: true)
                    } else if let position = entry.position {
                        _ = try await client.setProgress(videoId: videoId, position: position)
                    }
                    ledger.clear(videoId: videoId)
                } catch {
                    // Still couldn't deliver it — leave it queued.
                }
            }
        }
    }
}
