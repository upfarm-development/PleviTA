
import SwiftUI
import OSLog
import PleviCore

@MainActor
@Observable
final class VideoActionsCoordinator {
    struct PendingConfirmation: Identifiable {
        /// No standalone `ignore`.
        enum Kind { case delete, deleteAndIgnore }
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
    /// Guards re-entry, which is the whole reason it exists — every `perform…` method below bails while one is in flight.
    private(set) var isBusy = false

    private var client: TAClient?
    private var playbackHistory: PlaybackHistory?

    func adopt(client: TAClient?, playbackHistory: PlaybackHistory?) {
        self.client = client
        self.playbackHistory = playbackHistory
        // A server swap must not leave a dialog on screen that would fire at the new one.
        pendingConfirmation = nil; playlistPick = nil; failure = nil
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
    static let noCustomPlaylistsTitle = "No custom playlists"
    static let noCustomPlaylistsMessage = "Create one in Tube Archivist first, then it will show up here."

    // MARK: - Add to Playlist

    func beginAddToPlaylist(_ video: Video) async {
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
            playlistPick = PlaylistPick(video: video, playlists: customs)
        } catch { failure = Self.failure("Couldn't load your playlists", error) }
        #else
        playlistPick = PlaylistPick(video: video)
        #endif
    }

    func add(_ video: Video, to playlist: Playlist) async {
        guard let client, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await client.addVideo(video.id, toPlaylist: playlist.playlistId) }
        catch { failure = Self.failure("Couldn't add this video to that playlist", error) }
    }
}

struct PlaylistPick: Identifiable {
    let id = UUID()
    let video: Video
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
        }
    }
    var promptMessage: String {
        switch kind {
        case .delete: VideoActionsCoordinator.deleteMessage
        case .deleteAndIgnore: VideoActionsCoordinator.deleteAndIgnoreMessage
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
        Button { Task { await actions.list?.setWatched(video, isWatched: !isWatched) } } label: {
            Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                  systemImage: isWatched ? "circle" : "checkmark.circle")
        }
        Button { Task { await actions.coordinator.beginAddToPlaylist(video) } } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }
        #if os(iOS)
        SaveToDeviceMenuItem(video: video)
        #endif
        Button {
            if let id = video.channel?.channelId { actions.navigate(.channel(id)) }
        } label: { Label("Open Channel", systemImage: "person.crop.square") }

        Divider()

        Button(role: .destructive) { present(.delete) } label: { Label("Delete", systemImage: "trash") }
        Button(role: .destructive) { present(.deleteAndIgnore) } label: { Label("Delete and Ignore", systemImage: "trash.slash") }
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

    func body(content: Content) -> some View {
        content
            .videoActionConfirmation(coordinator, anchor: nil)
            #if os(iOS)
            // An alert, not a dialog, on iPhone and iPad: a dialog opens as a popover pointing
            // at whatever it's attached to, and a failure has no sensible source to point at —
            // after a delete, the row it came from may already be gone. An alert is centred.
            .alert(
                coordinator.failure?.title ?? "",
                isPresented: Binding(
                    get: { coordinator.failure != nil },
                    set: { if !$0 { coordinator.failure = nil } }
                ),
                presenting: coordinator.failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            #else
            .confirmationDialog(
                coordinator.failure?.title ?? "",
                isPresented: Binding(
                    get: { coordinator.failure != nil },
                    set: { if !$0 { coordinator.failure = nil } }
                ),
                titleVisibility: .visible,
                presenting: coordinator.failure
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
                        Task { await coordinator.add(pick.video, to: playlist) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            #else
            .sheet(item: Binding(
                get: { coordinator.playlistPick },
                set: { if $0 == nil { coordinator.playlistPick = nil } }
            )) { pick in
                AddToPlaylistSheet(video: pick.video, coordinator: coordinator)
            }
            #endif
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
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.promptMessage)
        }
    }

    func videoActionsPresentations(_ coordinator: VideoActionsCoordinator) -> some View {
        modifier(VideoActionsPresentations(coordinator: coordinator))
    }
}
