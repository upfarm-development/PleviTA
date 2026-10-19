
#if os(iOS)
import SwiftUI
import PleviCore

struct SaveToDeviceMenuItem: View {
    let video: Video

    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.offlineDownloader) private var offlineDownloader
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        if let entry = offlineLibrary.entry(for: video.id) {
            switch entry.record.state {
            case .complete:
                Button {
                    offlineLibrary.requestExport(videoId: video.id)
                } label: {
                    Label("Save a Copy…", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    Task { await offlineLibrary.delete(videoId: video.id) }
                } label: {
                    Label("Remove from iPhone", systemImage: "arrow.down.circle.fill")
                }
            case .downloading:
                Button {
                    // Deleting is enough: the library tells the downloader, which stops the
                    // transfer and moves the queue up — see `OfflineDownloader.handleDeleted`.
                    Task { await offlineLibrary.delete(videoId: video.id) }
                } label: {
                    if offlineLibrary.isWaitingForWiFi(videoId: video.id) {
                        Label("Cancel (Waiting for Wi-Fi)", systemImage: "wifi.slash")
                    } else {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                }
            case .failed:
                Button {
                    Task { await save() }
                } label: {
                    Label("Retry Save to iPhone", systemImage: "arrow.down.circle")
                }
            }
        } else {
            Button {
                Task { await save() }
            } label: {
                Label("Save to iPhone", systemImage: "arrow.down.circle")
            }
        }
    }

    private func save() async {
        guard let offlineDownloader, let mediaPath = video.mediaUrl, let client = authStore.client else { return }
        // The bundle's thumbnail and subtitles are fetched before the transfer is queued; held
        // so a phone locked straight after tapping still gets the transfer into the session.
        let assertion = BackgroundAssertion(name: "Save video")
        defer { assertion.end() }
        _ = await offlineLibrary.beginSave(video: video, client: client)
        await offlineDownloader.start(videoId: video.id, mediaPath: mediaPath, client: client, allowsCellular: appSettings.allowCellularDownloads)
    }
}
#endif
