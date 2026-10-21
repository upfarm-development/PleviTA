// Tapping a row pushes `VideoDetailView`, exactly like every other video link in the app (description, comments, playlist navigation all live there).
import Foundation
import SwiftUI
import PleviCore

struct PlaylistDetailView: View {
    let playlistId: String
    var navigate: (Route) -> Void = { _ in }

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.offlineDownloader) private var offlineDownloader
    @State private var saveAllResultMessage: String?
    /// Set once "Save All" has been tapped and is waiting for the user to agree — see
    /// `OfflineBatchSave.Plan`, which carries the count, the size and any shortfall.
    @State private var pendingSaveAll: OfflineBatchSave.Plan?
    #endif
    @State private var store: PlaylistDetailStore?
    /// The video this screen last pushed, so coming back can refresh just that row rather
    /// than reloading the list — see `refreshLastOpenedVideo`.
    @State private var lastOpenedVideoId: String?
    @State private var isConfirmingMarkAllWatched = false

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if let store {
                content(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.canvas)
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                @Bindable var appSettings = appSettings
                WatchedFilterToggleButton(hideWatched: appSettings.watchedFilterBinding(.playlistEntries))
            }
            ToolbarItem(placement: .topBarTrailing) {
                @Bindable var appSettings = appSettings
                SortMenuButton(field: $appSettings.playlistDetailSortField, order: $appSettings.playlistDetailSortOrder, fieldTitle: \.menuTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let playlist = store?.playlist {
                        PinToHomeMenuItem(target: .playlist(playlist))
                        Divider()
                    }
                    Button {
                        isConfirmingMarkAllWatched = true
                    } label: {
                        Label("Mark All Watched", systemImage: "checkmark.circle")
                    }
                    Button {
                        Task { await store?.load() }
                    } label: {
                        Label("Refresh Playlist", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await prepareSaveAll(store: store) }
                    } label: {
                        Label("Save All to iPhone", systemImage: "arrow.down.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                // On the menu both are chosen from, so each dialog opens from this button.
                // Attached to the whole screen, they pointed at nothing in particular. The
                // menu is always in the toolbar, so the dialogs can't vanish with it.
                .markAllWatchedConfirmation(
                    Self.markAllWatchedPrompt(count: store?.downloadedEntries.count),
                    isPresented: $isConfirmingMarkAllWatched
                ) {
                    Task { await store?.markAllWatched() }
                }
                .saveAllConfirmation($pendingSaveAll) { plan in
                    Task { await performSaveAll(plan) }
                }
            }
        }
        #endif
        #if os(tvOS)
        // Apple TV's own trigger sits in the controls row, and a dialog there fills the screen
        // with no arrow, so it stays up here where it can't vanish with that row. iPhone and
        // iPad attach it to the toolbar menu instead.
        .markAllWatchedConfirmation(
            Self.markAllWatchedPrompt(count: store?.downloadedEntries.count),
            isPresented: $isConfirmingMarkAllWatched
        ) {
            Task { await store?.markAllWatched() }
        }
        #endif
        #if os(iOS)
        .alert(
            "Save All to iPhone",
            isPresented: Binding(
                get: { saveAllResultMessage != nil },
                set: { if !$0 { saveAllResultMessage = nil } }
            ),
            presenting: saveAllResultMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        #endif
        .task(id: playlistId) {
            guard let client = authStore.client else { return }
            if let existing = store, existing.playlistId == playlistId {
                if case .loaded = existing.entriesState {
                    await refreshLastOpenedVideo(into: existing, client: client)
                    return
                }
                await existing.load()
                return
            }
            let newStore = PlaylistDetailStore(client: client, playlistId: playlistId)
            store = newStore
            await newStore.load()
        }
    }

    /// Refreshes the one row the user just came back from.
    private func refreshLastOpenedVideo(into store: PlaylistDetailStore, client: TAClient) async {
        guard let videoId = lastOpenedVideoId else { return }
        lastOpenedVideoId = nil
        guard let fresh = try? await client.video(id: videoId) else { return }
        store.apply(updated: fresh)
    }

    /// The playlist counterpart of `ChannelDetailView.markAllWatchedPrompt` — see it for why the count is omitted rather than guessed when it isn't known.
    static func markAllWatchedPrompt(count: Int?) -> String {
        guard let count, count > 1 else {
            return "Mark every video in this playlist as watched?"
        }
        return "Mark all \(count) videos in this playlist as watched?"
    }

    #if os(iOS)
    /// Works out what "Save All" would do and asks first.
    private func prepareSaveAll(store: PlaylistDetailStore?) async {
        let videos = await saveAllCandidates(store: store)
        guard !videos.isEmpty else {
            saveAllResultMessage = "There are no videos here to save."
            return
        }
        let plan = OfflineBatchSave.plan(videos, library: offlineLibrary)
        guard plan.count > 0 else {
            saveAllResultMessage = "Every video in this playlist is already saved to this iPhone."
            return
        }
        pendingSaveAll = plan
    }

    /// The playlist's downloaded entries — cheap here, unlike a channel's paged walk, but
    /// kept symmetrical so both screens confirm the same way.
    private func saveAllCandidates(store: PlaylistDetailStore?) async -> [Video] {
        guard let store else { return [] }
        return store.downloadedEntries.compactMap(\.video)
    }

    private func performSaveAll(_ plan: OfflineBatchSave.Plan) async {
        guard let offlineDownloader, let client = authStore.client else { return }
        let saved = await OfflineBatchSave.saveAll(
            plan.videos, client: client, library: offlineLibrary, downloader: offlineDownloader,
            allowsCellular: appSettings.allowCellularDownloads
        )
        saveAllResultMessage = saved == 0
            ? "Every downloaded video in this playlist is already saved to this iPhone."
            : "Saving \(saved) video\(saved == 1 ? "" : "s") to this iPhone."
    }
    #endif

    @ViewBuilder
    private func content(store: PlaylistDetailStore) -> some View {
        switch store.playlistState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Load Playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "Something went wrong.")
            } actions: {
                Button("Retry") { Task { await store.retryPlaylist() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.canvas)
        case .loaded(let playlist):
            // Derived once, here: the row list's sort/hideWatched-filtered
            // view of the entries.
            let visible = store.downloadedEntries(
                sortedBy: appSettings.playlistDetailSortField,
                order: appSettings.playlistDetailSortOrder,
                hideWatched: appSettings.hideWatched(in: .playlistEntries)
            )
            ScrollView {
                TVOSEagerStack(alignment: .leading, spacing: 20) {
                    heroCard(store: store, playlist: playlist)
                    #if os(tvOS)
                    tvControlsRow(store: store)
                    #endif
                    entriesSection(store: store, entries: visible)
                }
                .pleviRootHorizontalInset(horizontalInset)
                .padding(.vertical, 20)
            }
            .background(palette.canvas)
            #if os(iOS)
            .refreshable {
                await store.load()
            }
            #endif
        }
    }

    #if os(tvOS)
    /// The sort and overflow controls, in the content and hard against the leading edge.
    private var tvSortCaption: String {
        let direction = appSettings.playlistDetailSortOrder == .asc ? "Ascending" : "Descending"
        return "\(appSettings.playlistDetailSortField.menuTitle) · \(direction)"
    }

    @ViewBuilder
    private func tvControlsRow(store: PlaylistDetailStore) -> some View {
        @Bindable var appSettings = appSettings
        HStack(spacing: 16) {
            TVWatchedFilterToggle(hideWatched: appSettings.watchedFilterBinding(.playlistEntries), palette: palette)

            Menu {
                Picker("Sort By", selection: $appSettings.playlistDetailSortField) {
                    ForEach(PlaylistEntrySortField.allCases, id: \.self) { field in
                        Text(field.menuTitle).tag(field)
                    }
                }
                Picker("Order", selection: $appSettings.playlistDetailSortOrder) {
                    Label("Ascending", systemImage: "arrow.up").tag(HomeSortOrder.asc)
                    Label("Descending", systemImage: "arrow.down").tag(HomeSortOrder.desc)
                }
            } label: {
                Text(tvSortCaption)
                    .tvControlChip(palette)
            }
            .pleviSelectableStyle()

            Menu {
                if let playlist = store.playlist {
                    PinToHomeMenuItem(target: .playlist(playlist))
                    Divider()
                }
                Button {
                    isConfirmingMarkAllWatched = true
                } label: {
                    Label("Mark All Watched", systemImage: "checkmark.circle")
                }
                Button {
                    Task { await store.load() }
                } label: {
                    Label("Refresh Playlist", systemImage: "arrow.clockwise")
                }
            } label: {
                Text("More")
                    .tvControlChip(palette)
            }
            .pleviSelectableStyle()

            Spacer(minLength: 0)
        }
    }
    #endif

    // MARK: - Shared metrics

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.horizontal
        #else
        isRegularWidth ? PleviMetrics.insetPad : PleviMetrics.insetPhone
        #endif
    }

    /// A single cross-platform-safe stand-in for `horizontalSizeClass == .regular`.
    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    // MARK: - Cover thumbnail

    private var thumbnailWidth: CGFloat {
        #if os(tvOS)
        440
        #else
        isRegularWidth ? 240 : 120
        #endif
    }

    private var thumbnailHeight: CGFloat { (thumbnailWidth * 9 / 16).rounded() }

    private var thumbnailCornerRadius: CGFloat {
        #if os(tvOS)
        12
        #else
        10
        #endif
    }

    private var thumbnailPixelSize: CGFloat {
        #if os(tvOS)
        900
        #else
        480
        #endif
    }

    @ViewBuilder
    private func headerThumbnail(playlist: Playlist, fullWidth: Bool = false) -> some View {
        if fullWidth {
            RemoteImage(path: playlist.playlistThumbnail, maxPixelSize: thumbnailPixelSize)
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        } else {
            RemoteImage(path: playlist.playlistThumbnail, maxPixelSize: thumbnailPixelSize)
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
        }
    }

    // MARK: - Hero card (iPhone/iPad)

    private var headerColumnSpacing: CGFloat { 12 }

    /// Vertical spacing inside `headerDetails`'s own `VStack`.
    private let headerDetailsSpacing: CGFloat = 14

    private var stacksHeaderVertically: Bool {
        #if os(tvOS)
        false
        #else
        dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var titleLineLimit: Int {
        isRegularWidth ? 2 : 3
    }

    @ViewBuilder
    private func heroCard(store: PlaylistDetailStore, playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if stacksHeaderVertically {
                headerThumbnail(playlist: playlist, fullWidth: true)
                headerDetails(store: store, playlist: playlist, titleLineLimit: nil)
            } else {
                HStack(alignment: .top, spacing: headerColumnSpacing) {
                    headerThumbnail(playlist: playlist)
                    headerDetails(store: store, playlist: playlist, titleLineLimit: titleLineLimit)
                        .frame(minHeight: thumbnailHeight, alignment: .top)
                }
            }

            if !isRegularWidth {
                compactInfoRow(store: store, playlist: playlist)
            }

            if let description = playlist.playlistDescription, !description.isEmpty {
                DescriptionText(text: description, onSeek: { _ in })
            }

            if let error = store.markAllWatchedError {
                Text(error.errorDescription ?? "Couldn't mark all watched.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .pleviCard()
    }

    /// The title + owner/info column beside (or above) the cover — shared by iPhone, iPad, tvOS, and the accessibility-size stack.
    @ViewBuilder
    private func headerDetails(store: PlaylistDetailStore, playlist: Playlist, titleLineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: headerDetailsSpacing) {
            Group {
                if isRegularWidth {
                    Text(playlist.playlistName ?? "Untitled playlist")
                        #if os(tvOS)
                        .font(.system(size: 56, weight: .bold))
                        #else
                        .pleviScreenTitle()
                        #endif
                } else {
                    Text(playlist.playlistName ?? "Untitled playlist")
                        .font(.title2.bold())
                }
            }
            .foregroundStyle(palette.ink)
            .lineLimit(titleLineLimit)
            .fixedSize(horizontal: false, vertical: true)

            // iPad only now: owner + stats stay in this column, beside the thumbnail.
            if isRegularWidth {
                Spacer(minLength: 0)

                ownerRow(playlist: playlist)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    let statsLine = playlistStatsLine(store: store, playlist: playlist)
                    if !statsLine.isEmpty {
                        Text(statsLine)
                            .pleviMono()
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    badgesRow(playlist: playlist)
                }
            }
        }
        // Load-bearing: without this the column shrinks to fit its content
        // instead of claiming the width left beside the thumbnail.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// iPhone-only: owner + video count + Subscribed/Custom badges folded onto one line — see `headerDetails`'s own doc comment.
    @ViewBuilder
    private func compactInfoRow(store: PlaylistDetailStore, playlist: Playlist) -> some View {
        HStack(spacing: 8) {
            if let channelName = playlist.playlistChannel {
                let content = HStack(spacing: 6) {
                    ownerAvatar()
                    Text(channelName)
                        .pleviItemTitle()
                        .foregroundStyle(palette.body)
                        .lineLimit(1)
                }
                if let channelId = playlist.playlistChannelId {
                    Button { navigate(.channel(channelId)) } label: { content }
                        .buttonStyle(.plain)
                } else {
                    content
                }
            }

            if let countText = videoCountText(store: store) {
                Text("· \(countText)")
                    .pleviMono()
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }

            Spacer(minLength: 8)

            compactBadges(playlist: playlist)
        }
    }

    @ViewBuilder
    private func compactBadges(playlist: Playlist) -> some View {
        if playlist.playlistType == "custom" || playlist.playlistSubscribed == true {
            HStack(spacing: 8) {
                if playlist.playlistType == "custom" {
                    Image(systemName: "star.fill")
                        .foregroundStyle(palette.secondary)
                        .accessibilityLabel("Custom playlist")
                }
                if playlist.playlistSubscribed == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Subscribed")
                }
            }
            .font(.system(size: 15))
            .fixedSize()
        }
    }

    // MARK: - Owner row (shared: iPhone/iPad/tvOS)

    @ViewBuilder
    private func ownerRow(playlist: Playlist) -> some View {
        if let channelName = playlist.playlistChannel {
            if let channelId = playlist.playlistChannelId {
                Button {
                    navigate(.channel(channelId))
                } label: {
                    ownerContent(name: channelName)
                        // Inside the label: `tvFocusRing` reads `\.isFocused`,
                        // only set within the focusable's own subtree.
                        .tvFocusRing(cornerRadius: ownerAvatarSize / 2)
                }
                .pleviSelectableStyle()
            } else {
                ownerContent(name: channelName)
            }
        }
    }

    private func ownerContent(name: String) -> some View {
        HStack(spacing: 8) {
            ownerAvatar()
            Text(name)
                .pleviItemTitle()
                .foregroundStyle(palette.body)
                .lineLimit(2)
        }
    }

    /// See this file's own top-of-file doc comment: `Playlist` has no avatar image URL for its owning channel, only a name/id.
    private func ownerAvatar() -> some View {
        Circle()
            .fill(palette.metadata.opacity(0.16))
            .frame(width: ownerAvatarSize, height: ownerAvatarSize)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: ownerAvatarSize * 0.5))
                    .foregroundStyle(palette.metadata)
            )
    }

    private var ownerAvatarSize: CGFloat {
        #if os(tvOS)
        44
        #else
        22
        #endif
    }

    @ViewBuilder
    private func badgesRow(playlist: Playlist) -> some View {
        if playlist.playlistType == "custom" || playlist.playlistSubscribed == true {
            HStack(spacing: 14) {
                if playlist.playlistType == "custom" {
                    Label("Custom", systemImage: "star.fill")
                }
                if playlist.playlistSubscribed == true {
                    Label("Subscribed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(palette.accent)
                }
            }
            .pleviEyebrow()
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .fixedSize()
        }
    }

    // MARK: - Mono stats line

    private func videoCountText(store: PlaylistDetailStore) -> String? {
        guard case .loaded = store.entriesState else { return nil }
        let onServer = store.downloadedEntries.count
        let showing = store.downloadedEntries(
            sortedBy: appSettings.playlistDetailSortField,
            order: appSettings.playlistDetailSortOrder,
            hideWatched: appSettings.hideWatched(in: .playlistEntries)
        ).count
        return PleviFormatting.videoCountText(onServer: onServer, showing: showing)
    }

    private func playlistStatsLine(store: PlaylistDetailStore, playlist: Playlist) -> String {
        var parts: [String] = []
        if let countText = videoCountText(store: store) {
            parts.append(countText)
        }

        let downloadedVideos = store.entries.compactMap(\.video)
        let totalBytes = downloadedVideos.compactMap(\.mediaSize).reduce(0, +)
        if totalBytes > 0 {
            parts.append(PleviFormatting.byteCount(totalBytes))
        }
        if let mostRecent = downloadedVideos.compactMap(\.dateDownloaded).max() {
            let date = Date(timeIntervalSince1970: mostRecent)
            parts.append("last added \(date.formatted(date: .abbreviated, time: .omitted))")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Entries (iPhone: one card / iPad & tvOS: two-column grid of cards)

    private let entryDividerLeadingInset: CGFloat = 142

    @ViewBuilder
    private func entriesSection(store: PlaylistDetailStore, entries: [PlaylistEntryDisplay]) -> some View {
        switch store.entriesState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .pleviCard()
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Couldn't load this playlist's videos.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") { Task { await store.retryEntries() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .pleviCard()
        case .loaded:
            if entries.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "list.bullet",
                    description: Text(emptyStateMessage)
                )
                .padding(.vertical, 20)
                .pleviCard()
            } else if isRegularWidth {
                twoColumnEntries(store: store, entries: entries)
            } else {
                singleColumnEntries(store: store, entries: entries)
            }
        }
    }

    /// iPhone: one continuous card, divider-separated rows — today's shape,
    /// retinted/refonted.
    private func singleColumnEntries(store: PlaylistDetailStore, entries: [PlaylistEntryDisplay]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { position, display in
                if let video = display.video {
                    entryRow(store: store, video: video, position: position + 1)
                }
                if position < entries.count - 1 {
                    Divider().padding(.leading, entryDividerLeadingInset)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pleviCard()
    }

    private func twoColumnEntries(store: PlaylistDetailStore, entries: [PlaylistEntryDisplay]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 16) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { position, display in
                if let video = display.video {
                    entryRow(store: store, video: video, position: position + 1)
                        .padding(12)
                        .pleviCard()
                }
            }
        }
    }

    /// One row: index + thumbnail (with duration badge) + title + `channel · date`, all via the consolidated `VideoRow`.
    private func entryRow(store: PlaylistDetailStore, video: Video, position: Int) -> some View {
        Button {
            // Every other screen opens a video's detail page (description, comments, playlist navigation) on tap; a playlist row does the same.
            lastOpenedVideoId = video.id
            navigate(.video(video.id, fromPlaylistId: playlistId))
        } label: {
            VideoRow(
                video: video,
                layout: .row,
                position: position,
                actions: videoActions(list: store)
            )
        }
        .pleviSelectableStyle()
        .videoActionsContextMenu(video: video, actions: videoActions(list: store))
    }

    private func videoActions(list: any VideoMutating) -> VideoActions {
        VideoActions(list: list, coordinator: videoActionsCoordinator, navigate: navigate)
    }

    /// With `hideWatched` on, a playlist whose entries are all watched shows an empty list.
    private var emptyStateTitle: String {
        appSettings.hideWatched(in: .playlistEntries) ? "Nothing Left to Watch" : "No Downloaded Entries"
    }

    private var emptyStateMessage: String {
        appSettings.hideWatched(in: .playlistEntries)
            ? "Every downloaded video in this playlist is marked watched. Turn off “Hide watched videos” in Settings to see them."
            : "None of this playlist's videos have been downloaded yet."
    }

}

#Preview {
    NavigationStack {
        PlaylistDetailView(playlistId: Playlist.previewPlaylist.id)
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(VideoActionsCoordinator())
    .environment(PinnedItems(scope: "", cloud: nil))
}
