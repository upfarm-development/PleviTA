
#if os(iOS)
import SwiftUI
import PleviCore

struct OfflineVideosView: View {
    var navigate: (Route) -> Void = { _ in }

    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(OfflinePlaybackLedger.self) private var offlinePlaybackLedger
    @Environment(\.offlineDownloader) private var offlineDownloader
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved Videos")
                .pleviScreenTitle()
                .foregroundStyle(palette.ink)
                .padding(.horizontal, PleviMetrics.insetPhone)
                .padding(.bottom, 12)

            if offlineLibrary.entries.isEmpty {
                ContentUnavailableView(
                    "No Saved Videos",
                    systemImage: "arrow.down.circle",
                    description: Text("Save a video to watch it with no network — look for “Save to iPhone” on any video's menu.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(offlineLibrary.entries) { entry in
                        NavigationLink(value: Route.video(entry.video.id)) {
                            row(for: entry)
                        }
                        // Attached to the `NavigationLink` itself, never its label — see
                        // `VideoActions.swift`'s own doc comment on the tvOS double-activation
                        // bug this avoids repeating.
                        .contextMenuWithPreview {
                            SaveToDeviceMenuItem(video: entry.video)
                        } preview: {
                            VideoContextMenuPreview(
                                video: entry.video.applyingOfflineLedger(offlinePlaybackLedger.entry(for: entry.id)),
                                actions: VideoActions(list: nil, coordinator: videoActionsCoordinator, navigate: navigate),
                                palette: palette
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await offlineLibrary.delete(videoId: entry.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, PleviMetrics.screenHeaderTop)
        .background(palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Saved Videos")
    }

    @ViewBuilder
    private func row(for entry: OfflineLibrary.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VideoRow(
                video: entry.video.applyingOfflineLedger(offlinePlaybackLedger.entry(for: entry.id)),
                layout: .row,
                actions: VideoActions(list: nil, coordinator: videoActionsCoordinator, navigate: navigate)
            )
            statusLine(for: entry)
        }
    }

    @ViewBuilder
    private func statusLine(for entry: OfflineLibrary.Entry) -> some View {
        switch entry.record.state {
        case .complete:
            if entry.record.isOrphaned {
                Label("No longer on the server", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        case .downloading:
            if offlineLibrary.isWaitingForWiFi(videoId: entry.id) {
                Label("Waiting for Wi-Fi", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Downloading…", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 8) {
                Label(entry.record.lastError ?? "Couldn't save this video", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("Retry") {
                    Task { await retry(entry: entry) }
                }
                .font(.caption)
            }
        }
    }

    private func retry(entry: OfflineLibrary.Entry) async {
        guard let offlineDownloader, let mediaPath = entry.video.mediaUrl, let client = authStore.client else { return }
        _ = await offlineLibrary.beginSave(video: entry.video, client: client, reason: entry.record.reason)
        await offlineDownloader.start(videoId: entry.id, mediaPath: mediaPath, client: client, allowsCellular: appSettings.allowCellularDownloads)
    }
}
#endif
