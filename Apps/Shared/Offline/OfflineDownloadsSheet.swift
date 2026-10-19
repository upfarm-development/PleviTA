
#if os(iOS)
import SwiftUI
import PleviCore

struct OfflineDownloadsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.offlineDownloader) private var offlineDownloader

    @Environment(NavigationModel.self) private var navigation

    @State private var editMode: EditMode = .inactive

    private enum Tab: Hashable { case queue, saved }
    /// Which half is showing. Starts on the queue while anything is still downloading, and on the
    /// saved videos otherwise; see `chooseInitialTab()`.
    @State private var tab: Tab = .queue
    @State private var hasChosenTab = false

    /// The whole sheet's contents, computed ONCE per render rather than per section.
    private struct Sections {
        var active: [OfflineLibrary.Entry] = []
        var waiting: [OfflineLibrary.Entry] = []
        var failed: [OfflineLibrary.Entry] = []
        var isEmpty: Bool { active.isEmpty && waiting.isEmpty && failed.isEmpty }
    }

    private var sections: Sections {
        var result = Sections()
        // One pass over the shelf to index it, then one pass over the queue in its real order.
        var byId: [String: OfflineLibrary.Entry] = [:]
        for entry in offlineLibrary.entries {
            byId[entry.id] = entry
            if entry.record.state == .failed { result.failed.append(entry) }
        }
        let active = offlineLibrary.activeDownloadVideoIds
        for item in offlineLibrary.queueItems() {
            guard let entry = byId[item.videoId] else { continue }
            if active.contains(item.videoId) {
                result.active.append(entry)
            } else {
                result.waiting.append(entry)
            }
        }
        return result
    }

    var body: some View {
        let sections = sections
        let savedCount = offlineLibrary.entries.filter { $0.record.state == .complete }.count
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("Downloads", selection: $tab) {
                    Text(queueTitle(sections)).tag(Tab.queue)
                    Text(savedCount > 0 ? "Saved (\(savedCount))" : "Saved").tag(Tab.saved)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch tab {
                case .queue:
                    queueContent(sections)
                case .saved:
                    OfflineSavedLibraryView(onOpen: open)
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                if tab == .queue, sections.waiting.count > 1 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The root's own exporter sits behind this sheet; see `offlineCopyExporter`.
        .offlineCopyExporter(offlineLibrary)
        .onAppear(perform: chooseInitialTab)
        .onChange(of: sections.isEmpty) { _, isEmpty in
            // The last download finished: show what it produced rather than an empty queue.
            if isEmpty, tab == .queue { tab = .saved }
        }
        .onChange(of: offlineLibrary.entries.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .saved, editMode.isEditing { editMode = .inactive }
        }
        .onChange(of: sections.waiting.count) { _, count in
            if count <= 1, editMode.isEditing { editMode = .inactive }
        }
    }

    private func queueTitle(_ sections: Sections) -> String {
        let count = sections.active.count + sections.waiting.count + sections.failed.count
        return count > 0 ? "Downloading (\(count))" : "Downloading"
    }

    private func queueFooter(_ sections: Sections) -> String {
        let limit = OfflineDownloader.maximumConcurrentTransfers
        var text = "\(limit) download\(limit == 1 ? "" : "s") run at a time."
        if sections.waiting.count > 1 { text += " Tap Reorder to change what comes next." }
        return text
    }

    private func chooseInitialTab() {
        guard !hasChosenTab else { return }
        hasChosenTab = true
        tab = sections.isEmpty ? .saved : .queue
    }

    /// Leaves the sheet and brings the video's page up in whichever section is showing.
    private func open(_ video: Video) {
        dismiss()
        navigation.reveal(.video(video.id), in: navigation.selectedSection)
    }

    @ViewBuilder
    private func queueContent(_ sections: Sections) -> some View {
        if sections.isEmpty {
            ContentUnavailableView(
                "Nothing Downloading",
                systemImage: "arrow.down.circle",
                description: Text("Videos you save appear here while they download.")
            )
        } else {
            List {
                if !sections.active.isEmpty {
                    Section("Downloading") {
                        ForEach(sections.active) { entry in
                            row(entry)
                        }
                    }
                }

                if !sections.waiting.isEmpty {
                    Section {
                        ForEach(sections.waiting) { entry in
                            row(entry)
                        }
                        .onMove { source, destination in
                            move(sections: sections, fromOffsets: source, toOffset: destination)
                        }
                    } header: {
                        Text("Up Next")
                    } footer: {
                        Text(queueFooter(sections))
                    }
                }

                if !sections.failed.isEmpty {
                    Section("Failed") {
                        ForEach(sections.failed) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: OfflineLibrary.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.video.title ?? "Untitled")
                .font(.subheadline)
                .lineLimit(2)

            status(entry)

            // Hidden while reordering: the drag handles need the width, and a stray tap on
            // Cancel during a drag is exactly the kind of mistake that loses a download.
            if !editMode.isEditing {
                HStack(spacing: 16) {
                    if entry.record.state == .failed {
                        Button("Retry") { retry(entry) }
                            .buttonStyle(.bordered)
                    }
                    Button("Cancel", role: .destructive) { cancel(entry) }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    /// " · 2.4 MB/s" once a speed has been measured, nothing before.
    private func speedSuffix(_ sample: OfflineTransferProgress.Sample?) -> String {
        guard let speed = sample?.bytesPerSecond, speed >= 1 else { return "" }
        return " · \(PleviFormatting.byteCount(Int(speed)))/s"
    }

    @ViewBuilder
    private func status(_ entry: OfflineLibrary.Entry) -> some View {
        switch entry.record.state {
        case .downloading:
            if offlineLibrary.isWaitingForWiFi(videoId: entry.id) {
                Label("Waiting for Wi-Fi", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if offlineLibrary.activeDownloadVideoIds.contains(entry.id) {
                let sample = offlineLibrary.transfers.samples[entry.id]
                let received = sample?.receivedByteCount ?? entry.record.receivedByteCount
                if let expected = sample?.expectedByteCount ?? entry.record.expectedByteCount, expected > 0 {
                    ProgressView(value: Double(received), total: Double(expected))
                    Text("\(PleviFormatting.byteCount(received)) of \(PleviFormatting.byteCount(expected))\(speedSuffix(sample))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("\(PleviFormatting.byteCount(received))\(speedSuffix(sample))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Says "waiting" rather than showing a spinner that would be lying about work
                // nothing is doing — this was the original complaint about the sheet ("it just
                // spins and shows 0b"), and a queued video must not reintroduce it.
                Label("Waiting", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label(entry.record.lastError ?? "Download failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .complete:
            EmptyView()
        }
    }

    /// Writes the dragged order back, with the transfers already in flight kept at the front.
    private func move(sections: Sections, fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = OfflineDownloadQueue.moving(sections.waiting.map(\.id), fromOffsets: source, toOffset: destination)
        let wholeQueue = sections.active.map(\.id) + reordered
        Task { await offlineLibrary.reorderQueue(videoIds: wholeQueue) }
    }

    /// Deleting is enough: the library tells the downloader, which stops the transfer and
    /// moves the queue up — see `OfflineDownloader.handleDeleted`.
    private func cancel(_ entry: OfflineLibrary.Entry) {
        Task { await offlineLibrary.delete(videoId: entry.video.id) }
    }

    /// Puts a failed video back in the queue. The record has to go back to `.downloading`
    /// first, or the pump will not consider it — `queueItems()` excludes failures on purpose,
    /// so that a video which cannot download never holds a slot open.
    private func retry(_ entry: OfflineLibrary.Entry) {
        guard let client = authStore.client,
              let downloader = offlineDownloader,
              let mediaPath = entry.video.mediaUrl
        else { return }
        Task {
            await offlineLibrary.requeue(videoId: entry.video.id)
            await downloader.start(
                videoId: entry.video.id,
                mediaPath: mediaPath,
                client: client,
                allowsCellular: appSettings.allowCellularDownloads
            )
        }
    }
}

// MARK: - Saved videos

struct OfflineSavedLibraryView: View {
    /// Called with the video tapped. The caller decides what opening it means (the sheet dismisses
    /// itself and reveals the video's page).
    var onOpen: (Video) -> Void

    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(OfflinePlaybackLedger.self) private var offlinePlaybackLedger
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(AppSettings.self) private var appSettings
    @Environment(AuthStore.self) private var authStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    private var saved: [OfflineLibrary.Entry] {
        offlineLibrary.entries.filter { $0.record.state == .complete }
    }

    var body: some View {
        let saved = saved
        Group {
            if saved.isEmpty {
                ContentUnavailableView(
                    "No Saved Videos",
                    systemImage: "arrow.down.circle",
                    description: Text("Save a video to watch it with no network. Look for “Save to iPhone” on any video's menu.")
                )
            } else {
                ScrollView {
                    switch appSettings.homeViewStyle {
                    case .grid:
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                            ForEach(saved) { entry in cell(entry, layout: .card) }
                        }
                        .padding(.horizontal, inset)
                        .padding(.vertical, 12)
                    case .list:
                        LazyVStack(spacing: 0) {
                            ForEach(saved) { entry in
                                cell(entry, layout: .row)
                                if entry.id != saved.last?.id {
                                    Divider().overlay(palette.secondary.opacity(0.25))
                                }
                            }
                        }
                        .padding(.horizontal, inset)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .task(id: saved.map(\.id)) { await refreshWatchState(of: saved.map(\.id)) }
    }

    /// A saved copy carries no watch state, so the checkmarks and progress bars here come from the
    /// server when it can be reached, and are kept in the ledger for when it cannot. Failures are
    /// ignored: offline, the ledger's last note is what shows.
    private func refreshWatchState(of ids: [String]) async {
        guard let client = authStore.client else { return }
        await withTaskGroup(of: (String, VideoPlayerState?).self) { group in
            for id in ids.prefix(60) {
                group.addTask { (id, try? await client.video(id: id).player) }
            }
            for await (id, player) in group {
                guard let player else { continue }
                offlinePlaybackLedger.noteServerState(videoId: id, position: player.position, watched: player.watched == true)
            }
        }
    }

    @ViewBuilder
    private func cell(_ entry: OfflineLibrary.Entry, layout: VideoRow.Layout) -> some View {
        Button {
            onOpen(entry.video)
        } label: {
            VideoRow(
                video: entry.video.applyingOfflineLedger(offlinePlaybackLedger.entry(for: entry.id)),
                layout: layout,
                actions: VideoActions(list: nil, coordinator: videoActionsCoordinator, navigate: { _ in })
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenuWithPreview {
            SaveToDeviceMenuItem(video: entry.video)
        } preview: {
            VideoContextMenuPreview(
                video: entry.video.applyingOfflineLedger(offlinePlaybackLedger.entry(for: entry.id)),
                actions: VideoActions(list: nil, coordinator: videoActionsCoordinator, navigate: { _ in }),
                palette: palette
            )
        }
    }

    private var inset: CGFloat {
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
    }

    /// The same columns as Home's Newly Added grid.
    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
    }
}
#endif
