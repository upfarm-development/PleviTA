
import SwiftUI
import OSLog
import PleviCore

@MainActor
@Observable
final class VideoActionsCoordinator {
    struct PendingConfirmation: Identifiable {
        /// No standalone `ignore`.
        enum Kind { case delete, deleteAndIgnore, redownload }
        let id = UUID()
        let kind: Kind
        let video: Video
        let list: (any VideoMutating)?
        let onRemoved: (() -> Void)?
        let anchor: UUID?
    }
    struct ActionFailure: Identifiable { let id = UUID(); let title: String; let message: String }

    var pendingConfirmation: PendingConfirmation?
    var playlistPick: PlaylistPick?
    var failure: ActionFailure?
    /// An outcome worth telling the user that is not a failure. Shown in the same alert.
    var notice: ActionFailure?
    /// What a running bulk action is doing, shown over the whole app while it runs.
    private(set) var bulkMessage: String?
    /// Guards re-entry, which is the whole reason it exists — every `perform…` method below bails while one is in flight.
    private(set) var isBusy = false

    private var client: TAClient?
    private var playbackHistory: PlaybackHistory?

    func adopt(client: TAClient?, playbackHistory: PlaybackHistory?) {
        self.client = client
        self.playbackHistory = playbackHistory
        // A server swap must not leave a dialog on screen that would fire at the new one.
        pendingConfirmation = nil; playlistPick = nil; failure = nil; notice = nil
    }

    // MARK: - Ignore / Delete / Delete and Ignore

    func performDelete(_ p: PendingConfirmation) async {
        guard let client, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteVideo(id: p.video.id); remove(p) }
        catch { failure = Self.failure("Couldn't delete this video", error) }
    }

    func performDeleteAndIgnore(_ p: PendingConfirmation) async {
        guard let client, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        // The delete MUST come first, and not only because deleting is the point.
        do { try await client.deleteVideo(id: p.video.id) }
        catch { failure = Self.failure("Couldn't delete this video", error); return }
        // The delete succeeded, so the row must go regardless of what happens next — the
        // file really is gone, and leaving the row would be the bigger lie. Only the error
        // text changes.
        remove(p)
        do { try await client.ignoreDownload(id: p.video.id) }
        catch {
            failure = ActionFailure(
                title: "Deleted, but not ignored",
                message: "Deleted “\(Self.name(p.video) ?? "this video")”, but couldn't stop it from downloading again. \((error as? TAError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    /// Delete, then put the same video back on the download queue so Tube Archivist fetches it again in whatever format it is set to now.
    func performRedownload(_ p: PendingConfirmation) async {
        guard let client, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteVideo(id: p.video.id) }
        catch { failure = Self.failure("Couldn't delete this video", error); return }
        remove(p)
        do { try await client.addToDownloadQueue(id: p.video.id) }
        catch {
            failure = ActionFailure(
                title: "Deleted, but not queued",
                message: "Deleted “\(Self.name(p.video) ?? "this video")”, but couldn't add it to the download queue. \((error as? TAError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    // MARK: - Delete everything in a channel or playlist and download it again

    /// Finds the videos and returns a plan to confirm, or `nil` with an alert explaining why
    /// there is nothing to confirm. Walking a big channel pages the server, so it shows the
    /// progress overlay while it does.
    func prepareBulkRedownload(
        noun: String, name: String?, skipping: Set<VideoCodec>, videos: () async throws -> [Video]
    ) async -> BulkRedownloadPlan? {
        guard !isBusy else { return nil }
        isBusy = true; bulkMessage = "Finding videos…"
        defer { isBusy = false; bulkMessage = nil }
        do {
            let all = try await videos()
            guard !all.isEmpty else {
                notice = ActionFailure(title: "Nothing to download again",
                                       message: "There are no downloaded videos in this \(noun).")
                return nil
            }
            let selection = BulkRedownloadPolicy.select(all, skipping: skipping)
            guard !selection.redownloadIds.isEmpty else {
                notice = ActionFailure(
                    title: "Nothing to download again",
                    message: "Every video in this \(noun) is already in \(VideoCodec.list(selection.skippedCodecs)).")
                return nil
            }
            return BulkRedownloadPlan(
                noun: noun, name: name, videoIds: selection.redownloadIds,
                totalCount: all.count, skippedCodecs: selection.skippedCodecs)
        } catch {
            failure = Self.failure("Couldn't list the videos", error)
            return nil
        }
    }

    /// Deletes every video in the plan, then puts them on the download queue in one request.
    /// See `TAClient.redownload(videoIds:)` for the ordering and the stop-on-error rules.
    func performBulkRedownload(_ plan: BulkRedownloadPlan) async {
        guard let client, !isBusy else { return }
        isBusy = true
        let total = plan.videoIds.count
        bulkMessage = "Deleting 0 of \(total)…"
        defer { isBusy = false; bulkMessage = nil }

        let result = await client.redownload(videoIds: plan.videoIds) { [weak self] done in
            self?.bulkMessage = "Deleting \(done) of \(total)…"
        }
        for id in result.deleted {
            VideoRemovalCenter.shared.removeEverywhere(id: id)
            playbackHistory?.forget(id)
        }

        let count = result.deleted.count
        let videos = "\(count) video\(count == 1 ? "" : "s")"
        let fullyDone = result.queued && result.stopError == nil && result.notAttempted.isEmpty
        if fullyDone {
            notice = ActionFailure(
                title: "Added to the download queue",
                message: "\(videos) from this \(plan.noun) \(count == 1 ? "is" : "are") on Tube Archivist's download queue. Start the download there.")
            return
        }
        var lines: [String] = []
        if count == 0 {
            lines.append("Nothing was deleted.")
        } else {
            lines.append("Deleted \(count) of \(total).")
        }
        if let stop = result.stopError {
            lines.append("It stopped because: \(stop.errorDescription ?? "an error")")
        }
        if result.queued {
            lines.append("The \(videos) deleted \(count == 1 ? "was" : "were") added to the download queue.")
        } else if let queueError = result.queueError {
            lines.append("They could not be added to the download queue: \(queueError.errorDescription ?? "an error")")
        }
        failure = ActionFailure(title: count == 0 ? "Couldn't delete these videos" : "Only partly done",
                                message: lines.joined(separator: " "))
    }

    private func remove(_ p: PendingConfirmation) {
        p.list?.removeVideoLocally(id: p.video.id)
        // Every other list in memory too, so the screen this was opened from loses the row
        // without reloading, and keeps its scroll position.
        VideoRemovalCenter.shared.removeEverywhere(id: p.video.id)
        playbackHistory?.forget(p.video.id)
        p.onRemoved?()
    }

    private static func failure(_ title: String, _ error: Error) -> ActionFailure {
        ActionFailure(title: title, message: (error as? TAError)?.errorDescription ?? error.localizedDescription)
    }

    // MARK: - Copy

    static func name(_ video: Video) -> String? {
        guard let t = video.title, !t.isEmpty else { return nil }
        return t
    }
    static func deletePrompt(_ v: Video) -> String {
        guard let n = name(v) else { return "Delete this video from the server?" }
        return "Delete “\(n)” from the server?"
    }
    static let deleteMessage = "The file is removed from Tube Archivist. This cannot be undone."
    static func deleteAndIgnorePrompt(_ v: Video) -> String {
        guard let n = name(v) else { return "Delete this video and stop downloading it?" }
        return "Delete “\(n)” and stop downloading it?"
    }
    static let deleteAndIgnoreMessage = "The file is removed from Tube Archivist and it will not be downloaded again. This cannot be undone."
    static func redownloadPrompt(_ v: Video) -> String {
        guard let n = name(v) else { return "Delete this video and download it again?" }
        return "Delete “\(n)” and download it again?"
    }
    static func redownloadMessage(_ v: Video) -> String {
        let current = VideoFileFacts.currentFormat(v).map { "It is \($0) now. " } ?? ""
        return current + "The file is removed from Tube Archivist and the video is added to its download queue. Start the download there. Watched status and position are reset."
    }
    static let noCustomPlaylistsTitle = "No custom playlists"
    static let noCustomPlaylistsMessage = "Create one in Tube Archivist first, then it will show up here."

    // MARK: - Add to Playlist

    func beginAddToPlaylist(_ video: Video) async { await beginAddToPlaylist(videos: [video]) }

    func beginAddToPlaylist(videos: [Video]) async {
        #if os(tvOS)
        // No sheet precedent on tvOS — every `.sheet` in Apps/ is `#if os(iOS)`. So the
        // picker is a confirmationDialog, which cannot host a loading state: load first,
        // then present.
        guard let client else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let customs = try await loadAllCustomPlaylists(client)
            guard !customs.isEmpty else {
                failure = ActionFailure(title: Self.noCustomPlaylistsTitle, message: Self.noCustomPlaylistsMessage)
                return
            }
            playlistPick = PlaylistPick(videos: videos, playlists: customs)
        } catch { failure = Self.failure("Couldn't load your playlists", error) }
        #else
        playlistPick = PlaylistPick(videos: videos)
        #endif
    }

    func add(_ videos: [Video], to playlist: Playlist) async {
        guard let client, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        var added = 0
        for video in videos {
            if videos.count > 1 { bulkMessage = "Adding \(added + 1) of \(videos.count)…" }
            do { try await client.addVideo(video.id, toPlaylist: playlist.playlistId) }
            catch {
                failure = Self.failure(
                    videos.count == 1 ? "Couldn't add this video to that playlist"
                        : "Added \(added) of \(videos.count) to that playlist", error)
                bulkMessage = nil
                return
            }
            added += 1
        }
        bulkMessage = nil
        if videos.count > 1 {
            notice = ActionFailure(title: "Added to playlist",
                                   message: "Added \(added) videos to “\(playlist.playlistName ?? "the playlist")”.")
        }
    }

    // MARK: - Several videos at once (selection)

    func bulkSetWatched(_ videos: [Video], isWatched: Bool, list: (any VideoMutating)?) async {
        guard let list, !isBusy else { return }
        isBusy = true; defer { isBusy = false; bulkMessage = nil }
        for (index, video) in videos.enumerated() {
            bulkMessage = "Marking \(index + 1) of \(videos.count)…"
            await list.setWatched(video, isWatched: isWatched)
        }
    }

    /// Delete, or delete and ignore, every video in the plan. Same stop-on-error rules as
    /// `TAClient.deleteVideos`; what was deleted before a stop is removed from the lists.
    func performBulkDelete(_ plan: BulkDeletePlan) async {
        guard let client, !isBusy else { return }
        isBusy = true
        let total = plan.videos.count
        bulkMessage = "Deleting 0 of \(total)…"
        defer { isBusy = false; bulkMessage = nil }

        let result = await client.deleteVideos(
            ids: plan.videos.map(\.id), ignoring: plan.kind == .deleteAndIgnore
        ) { [weak self] done in
            self?.bulkMessage = "Deleting \(done) of \(total)…"
        }
        for id in result.deleted {
            VideoRemovalCenter.shared.removeEverywhere(id: id)
            playbackHistory?.forget(id)
        }

        let count = result.deleted.count
        if result.stopError == nil, result.notAttempted.isEmpty, result.ignoreFailures == 0 { return }
        var lines = ["Deleted \(count) of \(total)."]
        if let stop = result.stopError {
            lines.append("It stopped because: \(stop.errorDescription ?? "an error")")
        }
        if result.ignoreFailures > 0 {
            lines.append("\(result.ignoreFailures) could not be set to not download again.")
        }
        failure = ActionFailure(title: count == 0 ? "Couldn't delete these videos" : "Only partly done",
                                message: lines.joined(separator: " "))
    }
}

/// A channel's or playlist's videos, found and waiting for the user to confirm deleting them
/// and downloading them again.
struct BulkRedownloadPlan: Identifiable {
    let id = UUID()
    /// "channel" or "playlist".
    let noun: String
    let name: String?
    /// Only the videos that will be deleted; ones left alone because of their codec are not here.
    let videoIds: [String]
    /// Every video found, so the prompt can say how many are being left alone.
    let totalCount: Int
    /// The codecs of the videos left alone.
    let skippedCodecs: [VideoCodec]

    private var skippedCount: Int { totalCount - videoIds.count }

    var prompt: String {
        if skippedCount > 0 {
            return "Delete \(videoIds.count) of \(totalCount) videos in this \(noun) and download them again?"
        }
        return videoIds.count == 1
            ? "Delete the video in this \(noun) and download it again?"
            : "Delete all \(videoIds.count) videos in this \(noun) and download them again?"
    }
    var message: String {
        var text = ""
        if skippedCount > 0 {
            text = "\(skippedCount) already in \(VideoCodec.list(skippedCodecs)) \(skippedCount == 1 ? "is" : "are") left alone. "
        }
        return text + "The files are removed from Tube Archivist and the videos are added to its download queue. Start the download there. Watched status and positions are reset.\(noun == "selection" ? "" : " The \(noun) itself is kept.")"
    }
}

/// Several selected videos waiting for the user to confirm deleting them.
struct BulkDeletePlan: Identifiable {
    enum Kind { case delete, deleteAndIgnore }
    let id = UUID()
    let kind: Kind
    let videos: [Video]

    private var count: String { videos.count == 1 ? "the selected video" : "the \(videos.count) selected videos" }

    var prompt: String {
        switch kind {
        case .delete: "Delete \(count) from the server?"
        case .deleteAndIgnore: "Delete \(count) and stop downloading \(videos.count == 1 ? "it" : "them")?"
        }
    }
    var message: String {
        switch kind {
        case .delete: "The files are removed from Tube Archivist. This cannot be undone."
        case .deleteAndIgnore: "The files are removed from Tube Archivist and \(videos.count == 1 ? "it" : "they") will not be downloaded again. This cannot be undone."
        }
    }
    var confirmTitle: String { kind == .delete ? "Delete" : "Delete and Ignore" }
}

struct PlaylistPick: Identifiable {
    let id = UUID()
    let videos: [Video]
    /// Pre-loaded on tvOS; empty on iOS, where `AddToPlaylistSheet` loads it itself.
    var playlists: [Playlist] = []
}

/// `/api/playlist/` is paginated (`PlaylistsStore` pages it the same way).
func loadAllCustomPlaylists(_ client: TAClient) async throws -> [Playlist] {
    var all: [Playlist] = []
    var page = 1
    let maxPages = 50
    while page <= maxPages {
        let response = try await client.playlists(page: page, type: .custom)
        // Belt-and-braces on top of `?type=custom`: `Playlist.playlistType` is an untyped
        // `String?` unconnected to `Endpoint.PlaylistType`.
        all.append(contentsOf: response.data.filter { $0.playlistType == "custom" })
        guard response.paginate?.hasNextPage == true else { return all }
        page += 1
    }
    // Falling out of the loop means the server still had more. Say so rather than returning a
    // short list as if it were the whole thing — a missing playlist in the picker otherwise
    // looks like a server bug, with nothing anywhere to contradict that.
    Logger(subsystem: "com.plevi.ta", category: "VideoActions")
        .warning("Stopped paging custom playlists at \(maxPages) pages; picker is showing the first \(all.count) only.")
    return all
}

@MainActor
extension VideoActionsCoordinator.PendingConfirmation {
    var promptTitle: String {
        switch kind {
        case .delete: VideoActionsCoordinator.deletePrompt(video)
        case .deleteAndIgnore: VideoActionsCoordinator.deleteAndIgnorePrompt(video)
        case .redownload: VideoActionsCoordinator.redownloadPrompt(video)
        }
    }
    var promptMessage: String {
        switch kind {
        case .delete: VideoActionsCoordinator.deleteMessage
        case .deleteAndIgnore: VideoActionsCoordinator.deleteAndIgnoreMessage
        case .redownload: VideoActionsCoordinator.redownloadMessage(video)
        }
    }
}

// MARK: - The one value a row takes

@MainActor
struct VideoActions {
    /// The store holding the list this video was drawn from. Asked to drop the row once
    /// a delete succeeds. `nil` only in previews.
    let list: (any VideoMutating)?
    let coordinator: VideoActionsCoordinator
    /// Route pushes — a store knows nothing about routes.
    let navigate: (Route) -> Void
    /// Extra work once the video is gone. The video screen passes teardown + dismiss;
    /// every list surface passes nil.
    var onRemoved: (() -> Void)? = nil

    static let preview = VideoActions(list: nil, coordinator: VideoActionsCoordinator(), navigate: { _ in })
}

// MARK: - The menu itself

/// The source of truth for the item list, so the long press and the "…" can never drift
/// apart. Labels read only `video`, never a coordinator property — `@Observable` tracking is
/// per-property-read per body, so a grid of many cards doesn't invalidate when a dialog opens.
struct VideoActionsMenu: View {
    let video: Video
    let actions: VideoActions
    /// Where Delete's confirmation should point from — see `PendingConfirmation.anchor`.
    var anchor: UUID? = nil
    private var isWatched: Bool { video.player?.watched == true }

    var body: some View {
        // Two groups, so it is plain which actions only touch this app and which change
        // the Tube Archivist server.
        Section("In the app") {
            Button {
                if let id = video.channel?.channelId { actions.navigate(.channel(id)) }
            } label: { Label("Open Channel", systemImage: "person.crop.square") }
            #if os(iOS)
            SaveToDeviceMenuItem(video: video)
            #endif
        }

        Section("On the server") {
            Button { Task { await actions.list?.setWatched(video, isWatched: !isWatched) } } label: {
                Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                      systemImage: isWatched ? "circle" : "checkmark.circle")
            }
            Button { Task { await actions.coordinator.beginAddToPlaylist(video) } } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }

            Divider()

            Button(role: .destructive) { present(.redownload) } label: { Label("Delete and Download Again", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) { present(.delete) } label: { Label("Delete", systemImage: "trash") }
            Button(role: .destructive) { present(.deleteAndIgnore) } label: { Label("Delete and Ignore", systemImage: "trash.slash") }
        }
    }

    private func present(_ kind: VideoActionsCoordinator.PendingConfirmation.Kind) {
        actions.coordinator.pendingConfirmation = .init(
            kind: kind, video: video, list: actions.list, onRemoved: actions.onRemoved, anchor: anchor)
    }
}

// MARK: - The long-press menu, and where its Delete confirmation points

private struct VideoActionsContextMenu: ViewModifier {
    let video: Video
    let actions: VideoActions
    @State private var anchor = UUID()
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            // An explicit preview. Left to itself the system lifts the whole cell, text and all,
            // from a frame that is bigger than the card: a stray rectangle showed first, and the
            // enlarged title ran over the neighbouring thumbnails.
            .contextMenuWithPreview {
                VideoActionsMenu(video: video, actions: actions, anchor: anchor)
            } preview: {
                VideoContextMenuPreview(video: video, actions: actions, palette: PleviTheme.palette(for: colorScheme))
            }
            .videoActionConfirmation(actions.coordinator, anchor: anchor)
            .modifier(VideoSelectionOverlay(video: video))
        #else
        content
            .contextMenu { VideoActionsMenu(video: video, actions: actions) }
        #endif
    }
}

#if os(iOS)
/// `.contextMenu(menuItems:preview:)` for a preview made of app views.
private struct ContextMenuWithPreview<Menu: View, Preview: View>: ViewModifier {
    @Environment(AuthStore.self) private var authStore
    @Environment(VideoCache.self) private var videoCache
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let menu: () -> Menu
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        content.contextMenu {
            menu()
        } preview: {
            preview()
                .environment(authStore)
                .environment(videoCache)
                .environment(offlineLibrary)
                .environment(\.colorScheme, colorScheme)
        }
    }
}

extension View {
    func contextMenuWithPreview<Menu: View, Preview: View>(
        @ViewBuilder menu: @escaping () -> Menu,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(ContextMenuWithPreview(menu: menu, preview: preview))
    }
}

/// What a long-press on a video lifts: the card on its own surface, at a fixed width, so it never
/// depends on the size or layout of the cell it was pressed in.
struct VideoContextMenuPreview: View {
    let video: Video
    let actions: VideoActions
    let palette: PleviPalette

    var body: some View {
        VideoRow(video: video, layout: .card, actions: actions)
            .frame(width: 300)
            .padding(12)
            .background(palette.canvas)
    }
}
#endif

// MARK: - The presentations, attached once

private struct VideoActionsPresentations: ViewModifier {
    let coordinator: VideoActionsCoordinator

    private var alertItem: VideoActionsCoordinator.ActionFailure? { coordinator.failure ?? coordinator.notice }
    private var isAlertShown: Binding<Bool> {
        Binding(
            get: { coordinator.failure != nil || coordinator.notice != nil },
            set: { if !$0 { coordinator.failure = nil; coordinator.notice = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            // Nothing underneath can be used while a bulk delete is running.
            .disabled(coordinator.bulkMessage != nil)
            .overlay {
                if let message = coordinator.bulkMessage { BulkProgressOverlay(message: message) }
            }
            .videoActionConfirmation(coordinator, anchor: nil)
            #if os(iOS)
            // An alert, not a dialog, on iPhone and iPad: a dialog opens as a popover pointing
            // at whatever it's attached to, and a failure has no sensible source to point at —
            // after a delete, the row it came from may already be gone. An alert is centred.
            .alert(
                alertItem?.title ?? "",
                isPresented: isAlertShown,
                presenting: alertItem
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            #else
            .confirmationDialog(
                alertItem?.title ?? "",
                isPresented: isAlertShown,
                titleVisibility: .visible,
                presenting: alertItem
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            #endif
            #if os(tvOS)
            // No sheet precedent on tvOS (see `beginAddToPlaylist`'s own doc comment) — the
            // picker itself is a third confirmationDialog, one button per playlist.
            .confirmationDialog(
                "Add to Playlist",
                isPresented: Binding(
                    get: { coordinator.playlistPick != nil },
                    set: { if !$0 { coordinator.playlistPick = nil } }
                ),
                titleVisibility: .visible,
                presenting: coordinator.playlistPick
            ) { pick in
                ForEach(pick.playlists) { playlist in
                    Button(playlist.playlistName ?? "Untitled playlist") {
                        Task { await coordinator.add(pick.videos, to: playlist) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            #else
            .sheet(item: Binding(
                get: { coordinator.playlistPick },
                set: { if $0 == nil { coordinator.playlistPick = nil } }
            )) { pick in
                AddToPlaylistSheet(videos: pick.videos, coordinator: coordinator)
            }
            #endif
    }
}

/// Covers the app while a bulk delete runs, so it is clear something is happening and nothing
/// else gets tapped in the meantime.
private struct BulkProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                Text(message).font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

extension View {
    /// Attach to the `NavigationLink` or `Button` itself — **never** to its label.
    func videoActionsContextMenu(video: Video, actions: VideoActions) -> some View {
        modifier(VideoActionsContextMenu(video: video, actions: actions))
    }

    /// Delete / Delete and Ignore's confirmation, presented here only when the pending one
    /// names this `anchor`. One definition for every place that can present it.
    func videoActionConfirmation(_ coordinator: VideoActionsCoordinator, anchor: UUID?) -> some View {
        confirmationDialog(
            coordinator.pendingConfirmation?.promptTitle ?? "",
            isPresented: Binding(
                get: { coordinator.pendingConfirmation.map { $0.anchor == anchor } ?? false },
                set: { if !$0 { coordinator.pendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: coordinator.pendingConfirmation
        ) { pending in
            switch pending.kind {
            case .delete:
                Button("Delete", role: .destructive) { Task { await coordinator.performDelete(pending) } }
            case .deleteAndIgnore:
                Button("Delete and Ignore", role: .destructive) { Task { await coordinator.performDeleteAndIgnore(pending) } }
            case .redownload:
                Button("Delete and Download Again", role: .destructive) { Task { await coordinator.performRedownload(pending) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.promptMessage)
        }
    }

    /// Delete / Delete and Ignore for the videos selected on a screen.
    func bulkDeleteConfirmation(
        _ plan: Binding<BulkDeletePlan?>,
        perform: @escaping (BulkDeletePlan) -> Void
    ) -> some View {
        confirmationDialog(
            plan.wrappedValue?.prompt ?? "",
            isPresented: Binding(
                get: { plan.wrappedValue != nil },
                set: { if !$0 { plan.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: plan.wrappedValue
        ) { pending in
            Button(pending.confirmTitle, role: .destructive) { perform(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    /// "Delete All and Download Again" for a channel or playlist. Attach it to what the action is
    /// chosen from, for the same reason as `markAllWatchedConfirmation`.
    func bulkRedownloadConfirmation(
        _ plan: Binding<BulkRedownloadPlan?>,
        perform: @escaping (BulkRedownloadPlan) -> Void
    ) -> some View {
        confirmationDialog(
            plan.wrappedValue?.prompt ?? "",
            isPresented: Binding(
                get: { plan.wrappedValue != nil },
                set: { if !$0 { plan.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: plan.wrappedValue
        ) { pending in
            Button("Delete All and Download Again", role: .destructive) { perform(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    func videoActionsPresentations(_ coordinator: VideoActionsCoordinator) -> some View {
        modifier(VideoActionsPresentations(coordinator: coordinator))
    }
}
