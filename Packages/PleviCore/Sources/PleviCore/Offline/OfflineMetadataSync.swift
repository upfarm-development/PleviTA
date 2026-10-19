
import Foundation

public enum OfflineMetadataSync {
    @MainActor
    public static func refresh(library: OfflineLibrary, client: TAClient) async {
        for entry in library.entries where entry.record.state == .complete {
            do {
                let video = try await client.video(id: entry.id)
                await library.updateVideoMetadata(videoId: entry.id, video: video, skipReload: true)
                if entry.record.isOrphaned {
                    await library.setOrphaned(videoId: entry.id, isOrphaned: false, skipReload: true)
                }
            } catch TAError.notFound {
                if !entry.record.isOrphaned {
                    await library.setOrphaned(videoId: entry.id, isOrphaned: true, skipReload: true)
                }
            } catch {
                // Couldn't even check — leave it as is and try again on the next reconnect.
            }
        }
        await library.reload()
    }
}
