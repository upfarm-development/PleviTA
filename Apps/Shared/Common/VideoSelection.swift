// Picking several videos on a screen and acting on them together — iPhone and iPad.

import SwiftUI
import PleviCore

#if os(iOS)

/// Which videos are picked, and whether picking is on. One per app (owned by `RootView`).
@MainActor
@Observable
final class VideoSelection {
    private(set) var isActive = false
    private var order: [String] = []
    private var byId: [String: Video] = [:]

    var count: Int { order.count }
    /// In the order they were picked.
    var videos: [Video] { order.compactMap { byId[$0] } }

    func isSelected(_ id: String) -> Bool { byId[id] != nil }

    func begin() { isActive = true }

    func end() {
        isActive = false
        order = []
        byId = [:]
    }

    func toggle(_ video: Video) {
        if byId.removeValue(forKey: video.id) != nil {
            order.removeAll { $0 == video.id }
        } else {
            byId[video.id] = video
            order.append(video.id)
        }
    }

    func select(_ videos: [Video]) {
        for video in videos where byId[video.id] == nil {
            byId[video.id] = video
            order.append(video.id)
        }
    }

    func deselectAll() {
        order = []
        byId = [:]
    }
}

/// While picking is on: the tap on a video picks it instead of opening it, and a tick shows
/// whether it is picked. Laid over the row, so it also keeps the long-press menu out of the way.
/// Off, it draws nothing and takes no touches.
struct VideoSelectionOverlay: ViewModifier {
    let video: Video
    @Environment(VideoSelection.self) private var selection: VideoSelection?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            if let selection, selection.isActive {
                let isSelected = selection.isSelected(video.id)
                let palette = PleviTheme.palette(for: colorScheme)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selection.toggle(video) }
                    if isSelected {
                        RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous)
                            .strokeBorder(palette.accent, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(isSelected ? .palette : .monochrome)
                        .foregroundStyle(Color.white, isSelected ? palette.accent : Color.white.opacity(0.0))
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .padding(10)
                        .allowsHitTesting(false)
                }
                .accessibilityElement()
                .accessibilityLabel(video.title ?? "Video")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// The bar that sits above the tab bar while picking is on: how many are picked, Select All,
/// Done, and the actions menu — the same actions a single video has, split the same way into
/// "In the app" and "On the server".
private struct VideoSelectionBar: ViewModifier {
    let actions: VideoActions?
    let allVideos: () -> [Video]

    @Environment(VideoSelection.self) private var selection: VideoSelection?
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.offlineDownloader) private var offlineDownloader
    @Environment(\.colorScheme) private var colorScheme

    @State private var pendingRedownload: BulkRedownloadPlan?
    @State private var pendingDelete: BulkDeletePlan?
    @State private var pendingSave: OfflineBatchSave.Plan?

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let selection, selection.isActive, let actions {
                    bar(selection: selection, actions: actions)
                }
            }
            // Leaving the screen — another tab, going back — ends picking, so it cannot be left
            // on with nothing to show for it.
            .onDisappear { selection?.end() }
    }

    private func bar(selection: VideoSelection, actions: VideoActions) -> some View {
        let all = allVideos()
        let everythingPicked = !all.isEmpty && all.allSatisfy { selection.isSelected($0.id) }
        return HStack(spacing: 14) {
            Button("Done") { selection.end() }
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            Text(selection.count == 0 ? "Select videos" : "\(selection.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            Button(everythingPicked ? "Select None" : "Select All") {
                if everythingPicked { selection.deselectAll() } else { selection.select(all) }
            }
            Menu {
                actionsMenu(selection: selection, actions: actions)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
            }
            .disabled(selection.count == 0)
            .accessibilityLabel("Actions for the selected videos")
            .bulkRedownloadConfirmation($pendingRedownload) { plan in
                Task {
                    await actions.coordinator.performBulkRedownload(plan)
                    selection.end()
                }
            }
            .bulkDeleteConfirmation($pendingDelete) { plan in
                Task {
                    await actions.coordinator.performBulkDelete(plan)
                    selection.end()
                }
            }
            .saveAllConfirmation($pendingSave) { plan in
                Task { await save(plan, selection: selection, actions: actions) }
            }
        }
        .tint(palette.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func actionsMenu(selection: VideoSelection, actions: VideoActions) -> some View {
        Section("In the app") {
            Button { prepareSave(selection: selection, actions: actions) } label: {
                Label("Save to Device…", systemImage: "arrow.down.circle")
            }
        }

        Section("On the server") {
            Button {
                let videos = selection.videos
                Task {
                    await actions.coordinator.bulkSetWatched(videos, isWatched: true, list: actions.list)
                    selection.end()
                }
            } label: { Label("Mark Watched", systemImage: "checkmark.circle") }
            Button {
                let videos = selection.videos
                Task {
                    await actions.coordinator.bulkSetWatched(videos, isWatched: false, list: actions.list)
                    selection.end()
                }
            } label: { Label("Mark Unwatched", systemImage: "circle") }
            Button {
                let videos = selection.videos
                Task { await actions.coordinator.beginAddToPlaylist(videos: videos) }
            } label: { Label("Add to Playlist…", systemImage: "text.badge.plus") }

            Divider()

            Button(role: .destructive) {
                let videos = selection.videos
                Task {
                    // The same codec filter a channel or playlist uses: videos already in a
                    // codec chosen under Settings > Server > Download again are left out, and
                    // the rest of the selection goes ahead.
                    pendingRedownload = await actions.coordinator.prepareBulkRedownload(
                        noun: "selection", name: nil, skipping: appSettings.redownloadSkipCodecs
                    ) { videos }
                }
            } label: { Label("Delete and Download Again", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) {
                pendingDelete = BulkDeletePlan(kind: .delete, videos: selection.videos)
            } label: { Label("Delete", systemImage: "trash") }
            Button(role: .destructive) {
                pendingDelete = BulkDeletePlan(kind: .deleteAndIgnore, videos: selection.videos)
            } label: { Label("Delete and Ignore", systemImage: "trash.slash") }
        }
    }

    private func prepareSave(selection: VideoSelection, actions: VideoActions) {
        let plan = OfflineBatchSave.plan(selection.videos, library: offlineLibrary)
        guard plan.count > 0 else {
            actions.coordinator.notice = .init(
                title: "Save to Device", message: "Every selected video is already saved to this device.")
            return
        }
        pendingSave = plan
    }

    private func save(_ plan: OfflineBatchSave.Plan, selection: VideoSelection, actions: VideoActions) async {
        guard let offlineDownloader, let client = authStore.client else { return }
        let saved = await OfflineBatchSave.saveAll(
            plan.videos, client: client, library: offlineLibrary, downloader: offlineDownloader,
            allowsCellular: appSettings.allowCellularDownloads
        )
        actions.coordinator.notice = .init(
            title: "Save to Device",
            message: saved == 0
                ? "Every selected video is already saved to this device."
                : "Saving \(saved) video\(saved == 1 ? "" : "s") to this device.")
        selection.end()
    }
}

extension View {
    /// The selection bar for a screen. `actions` is the screen's own, for the list that
    /// "Mark Watched" updates (nil hides the bar); `allVideos` is what "Select All" picks.
    func videoSelectionBar(actions: VideoActions?, allVideos: @escaping () -> [Video]) -> some View {
        modifier(VideoSelectionBar(actions: actions, allVideos: allVideos))
    }
}

#else

extension View {
    func videoSelectionBar(actions: VideoActions?, allVideos: @escaping () -> [Video]) -> some View { self }
}

#endif
