// Settings → Storage → Downloaded videos: what is on the phone, grouped by channel, with a way to remove any of it.

#if os(iOS)
import SwiftUI
import PleviCore

struct OfflineStorageBrowser: View {
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @State private var isConfirmingRemoveAll = false

    private var groups: [OfflineLibrary.ChannelGroup] { offlineLibrary.entriesByChannel() }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nothing Downloaded",
                    systemImage: "arrow.down.circle",
                    description: Text("Videos you save to this iPhone appear here.")
                )
            } else {
                List {
                    Section {
                        ForEach(groups) { group in
                            NavigationLink {
                                OfflineChannelStorageView(channelId: group.channelId, channelName: group.channelName)
                            } label: {
                                LabeledContent {
                                    Text(PleviFormatting.byteCount(group.byteCount))
                                        .foregroundStyle(.secondary)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.channelName)
                                        Text("\(group.entries.count) video\(group.entries.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            // Swiping a channel row removes that whole channel, which is what
                            // the row represents — the per-video swipe lives one level in.
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await offlineLibrary.delete(videoIds: group.videoIds) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Swipe a channel to remove everything saved from it.")
                    }

                    Section {
                        Button("Remove All Downloads", role: .destructive) {
                            isConfirmingRemoveAll = true
                        }
                        // On the button, not the screen: the dialog opens as a popover that
                        // points at whatever it is attached to, and attached to the screen it
                        // pointed into the channel list above.
                        .confirmationDialog(
                            "Remove All Downloads",
                            isPresented: $isConfirmingRemoveAll,
                            titleVisibility: .visible
                        ) {
                            Button("Remove \(offlineLibrary.entries.count) Video\(offlineLibrary.entries.count == 1 ? "" : "s")", role: .destructive) {
                                Task { await offlineLibrary.delete(videoIds: offlineLibrary.entries.map(\.id)) }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This frees \(PleviFormatting.byteCount(offlineLibrary.totalBytesUsed)). The videos stay on your server.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloaded Videos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One channel's saved videos. Reads the group fresh from the library on every pass rather
/// than capturing it, so deleting a row here updates the list underneath — and the whole
/// screen pops itself when the last one goes.
private struct OfflineChannelStorageView: View {
    let channelId: String
    let channelName: String

    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.dismiss) private var dismiss

    private var entries: [OfflineLibrary.Entry] {
        offlineLibrary.entriesByChannel().first { $0.channelId == channelId }?.entries ?? []
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                LabeledContent {
                    Text(PleviFormatting.byteCount(entry.record.receivedByteCount))
                        .foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.video.title ?? "Untitled")
                            .lineLimit(2)
                        if entry.record.state != .complete {
                            Text(entry.record.state == .failed ? "Failed" : "Downloading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await offlineLibrary.delete(videoId: entry.id) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: entries.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}
#endif
