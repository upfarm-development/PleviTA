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
    @State private var pendingRedownload: BulkRedownloadPlan?
    #if os(iOS)
    @Environment(VideoSelection.self) private var selection: VideoSelection?
    #endif

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
        .videoSelectionBar(
            actions: store.map { videoActions(list: $0) },
            allVideos: { store?.downloadedEntries.compactMap(\.video) ?? [] }
        )
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
                @Bindable var appSettings = appSettings
                Menu {
                    // Pin to Home is left out entirely, not shown disabled, while the playlist is
                    // still loading.
                    Section("In the app") {
                        Picker("Layout", selection: $appSettings.playlistDetailViewStyle) {
                            Label("Large", systemImage: "rectangle.grid.1x2").tag(ViewStyle.grid)
                            Label("List", systemImage: "list.bullet").tag(ViewStyle.list)
                        }
                        .pickerStyle(.inline)
                        if let playlist = store?.playlist {
                            PinToHomeMenuItem(target: .playlist(playlist))
                        }
                        Button {
                            selection?.begin()
                        } label: {
                            Label("Select Videos", systemImage: "checkmark.circle")
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
                    }

                    Section("On the server") {
                        Button {
                            isConfirmingMarkAllWatched = true
                        } label: {
                            Label("Mark All Watched", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await prepareRedownloadAll(store: store) }
                        } label: {
                            Label("Delete All and Download Again", systemImage: "arrow.triangle.2.circlepath")
                        }
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
                .bulkRedownloadConfirmation($pendingRedownload) { plan in
                    Task { await videoActionsCoordinator.performBulkRedownload(plan) }
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
        .bulkRedownloadConfirmation($pendingRedownload) { plan in
            Task { await videoActionsCoordinator.performBulkRedownload(plan) }
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

    /// The playlist's downloaded videos, confirmed before they are deleted and queued again.
    /// The playlist itself is not touched. Already loaded, so there is nothing to walk.
    private func prepareRedownloadAll(store: PlaylistDetailStore?) async {
        guard let store else { return }
        let videos = store.downloadedEntries.compactMap(\.video)
        pendingRedownload = await videoActionsCoordinator.prepareBulkRedownload(
            noun: "playlist", name: store.playlist?.playlistName, skipping: appSettings.redownloadSkipCodecs
        ) { videos }
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
            #if os(iOS)
            iOSContent(store: store, playlist: playlist, entries: visible)
                .background(palette.canvas)
            #else
            ScrollView {
                TVOSEagerStack(alignment: .leading, spacing: 20) {
                    heroCard(store: store, playlist: playlist)
                    tvControlsRow(store: store)
                    entriesSection(store: store, entries: visible)
                }
                .pleviRootHorizontalInset(horizontalInset)
                .padding(.vertical, 20)
            }
            .background(palette.canvas)
            #endif
        }
    }

    #if os(iOS)
    // MARK: - iPhone and iPad

    /// The real place of each downloaded video in the playlist, 1-based and unique, in the
    /// playlist's own order — whatever sort or filter is applied to what is shown. The index on
    /// a card says where the video sits in the playlist, not where it landed in the current view.
    private func playlistPositions(_ store: PlaylistDetailStore) -> [String: Int] {
        var positions: [String: Int] = [:]
        for (index, display) in store.downloadedEntries.enumerated() where positions[display.id] == nil {
            positions[display.id] = index + 1
        }
        return positions
    }

    /// iPhone: cover, title and owner line, the Continue button, then the videos, in one scroll.
    /// iPad: the same header pinned in a 300pt column beside a list that scrolls on its own.
    @ViewBuilder
    private func iOSContent(store: PlaylistDetailStore, playlist: Playlist, entries: [PlaylistEntryDisplay]) -> some View {
        if isRegularWidth {
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        iOSCover(playlist: playlist, cornerRadius: 14)
                        Text(playlist.playlistName ?? "Untitled playlist")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.65)
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        ownerLine(store: store, playlist: playlist)
                        playlistDescription(playlist: playlist)
                        continueButton(store: store)
                        markAllWatchedError(store: store)
                    }
                    .padding(.vertical, 18)
                }
                .frame(width: 300)
                .scrollIndicators(.hidden)

                // Told to take the rest of the width: left to itself the row sized to its content
                // and sat in the middle of the screen with empty bands either side.
                ScrollView {
                    iOSEntries(store: store, entries: entries)
                        .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity)
                .refreshable { await store.load() }
            }
            .padding(.horizontal, PleviMetrics.insetPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        iOSCover(playlist: playlist, cornerRadius: 10)
                            .frame(width: 96)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.playlistName ?? "Untitled playlist")
                                .font(.system(size: 24, weight: .bold))
                                .tracking(-0.6)
                                .foregroundStyle(palette.ink)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            ownerLine(store: store, playlist: playlist)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    playlistDescription(playlist: playlist)
                    continueButton(store: store)
                    markAllWatchedError(store: store)
                    iOSEntries(store: store, entries: entries)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                // Room for the floating tab bar, so the last video scrolls fully above it.
                .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
        }
    }

    private func iOSCover(playlist: Playlist, cornerRadius: CGFloat) -> some View {
        RemoteImage(path: playlist.playlistThumbnail, maxPixelSize: thumbnailPixelSize)
            .aspectRatio(16.0 / 9.0, contentMode: .fill)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// `Owner · 57 videos`, with the Custom and Subscribed marks after it. Tapping it opens the
    /// owner's channel, as the avatar row it replaces did.
    @ViewBuilder
    private func ownerLine(store: PlaylistDetailStore, playlist: Playlist) -> some View {
        let parts = [playlist.playlistChannel, videoCountText(store: store)].compactMap { $0 }
        HStack(spacing: 8) {
            if !parts.isEmpty {
                let line = Text(parts.joined(separator: " · "))
                    .pleviMono()
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let channelId = playlist.playlistChannelId {
                    Button { navigate(.channel(channelId)) } label: { line }
                        .buttonStyle(.plain)
                } else {
                    line
                }
            }
            compactBadges(playlist: playlist)
        }
    }

    @ViewBuilder
    private func playlistDescription(playlist: Playlist) -> some View {
        if let description = playlist.playlistDescription, !description.isEmpty {
            DescriptionText(text: description, onSeek: { _ in })
        }
    }

    @ViewBuilder
    private func markAllWatchedError(store: PlaylistDetailStore) -> some View {
        if let error = store.markAllWatchedError {
            Text(error.errorDescription ?? "Couldn't mark all watched.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    /// Opens the video at the top of the list that has not been watched — in the order the list is showing, so it follows the sort chosen for the playlist.
    @ViewBuilder
    private func continueButton(store: PlaylistDetailStore) -> some View {
        let target = continueTarget(store: store)
        if target != nil || !isEntriesLoaded(store) {
            Button {
                guard let target else { return }
                lastOpenedVideoId = target.video.id
                navigate(.video(target.video.id, fromPlaylistId: playlistId))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text(target?.title ?? "Continue")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(palette.accent.opacity(target == nil ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
        }
    }

    private func isEntriesLoaded(_ store: PlaylistDetailStore) -> Bool {
        if case .loaded = store.entriesState { return true }
        return false
    }

    private func continueTarget(store: PlaylistDetailStore) -> (video: Video, title: String)? {
        guard isEntriesLoaded(store) else { return nil }
        // Sorted but not filtered: with watched videos hidden the list may be empty, and the
        // button should still have somewhere to go.
        let all = store.downloadedEntries(
            sortedBy: appSettings.playlistDetailSortField,
            order: appSettings.playlistDetailSortOrder,
            hideWatched: false
        )
        let positions = playlistPositions(store)
        let unwatched = all.first { $0.video?.player?.watched != true }
        guard let entry = unwatched ?? all.first, let video = entry.video else { return nil }
        let number = positions[entry.id] ?? 1
        return (video, "\(unwatched == nil ? "Watch Again" : "Continue") · #\(number)")
    }

    /// Large: a card per video, one column on iPhone and two on iPad. List: one card of rows, one
    /// video per row on both. Chosen from the "…" menu.
    @ViewBuilder
    private func iOSEntries(store: PlaylistDetailStore, entries: [PlaylistEntryDisplay]) -> some View {
        switch store.entriesState {
        case .idle, .loading, .failed:
            entriesSection(store: store, entries: entries)
        case .loaded:
            if entries.isEmpty {
                entriesSection(store: store, entries: entries)
            } else {
                let positions = playlistPositions(store)
                let owner = store.playlist?.playlistChannel
                switch appSettings.playlistDetailViewStyle {
                case .grid:
                    largeEntries(store: store, entries: entries, positions: positions, owner: owner)
                case .list:
                    listEntries(store: store, entries: entries, positions: positions, owner: owner)
                }
            }
        }
    }

    private func largeEntries(
        store: PlaylistDetailStore, entries: [PlaylistEntryDisplay], positions: [String: Int], owner: String?
    ) -> some View {
        let spacing: CGFloat = isRegularWidth ? 14 : 12
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: isRegularWidth ? 2 : 1)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(entries) { display in
                if let video = display.video {
                    entryButton(store: store, video: video) {
                        VideoRow(
                            video: video, layout: .largeCard, position: positions[display.id],
                            ownerName: owner, actions: videoActions(list: store)
                        )
                        .padding(8)
                        .pleviCard()
                    }
                }
            }
        }
    }

    private func listEntries(
        store: PlaylistDetailStore, entries: [PlaylistEntryDisplay], positions: [String: Int], owner: String?
    ) -> some View {
        let rows = entries.compactMap { display in display.video.map { (id: display.id, video: $0) } }
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                entryButton(store: store, video: row.video) {
                    VideoRow(
                        video: row.video, layout: .wideRow, position: positions[row.id],
                        ownerName: owner, actions: videoActions(list: store)
                    )
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        // Nothing under the last row to separate it from.
                        if index < rows.count - 1 { Divider() }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .pleviCard()
    }

    /// A video's page opens on tap, as everywhere else in the app, with this playlist as the one
    /// its pager starts on.
    private func entryButton<Label: View>(
        store: PlaylistDetailStore, video: Video, @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            lastOpenedVideoId = video.id
            navigate(.video(video.id, fromPlaylistId: playlistId))
        } label: {
            label()
        }
        .pleviSelectableStyle()
        .videoActionsContextMenu(video: video, actions: videoActions(list: store))
    }
    #endif

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
                Section("In the app") {
                    if let playlist = store.playlist {
                        PinToHomeMenuItem(target: .playlist(playlist))
                    }
                    Button {
                        Task { await store.load() }
                    } label: {
                        Label("Refresh Playlist", systemImage: "arrow.clockwise")
                    }
                }
                Section("On the server") {
                    Button {
                        isConfirmingMarkAllWatched = true
                    } label: {
                        Label("Mark All Watched", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await prepareRedownloadAll(store: store) }
                    } label: {
                        Label("Delete All and Download Again", systemImage: "arrow.triangle.2.circlepath")
                    }
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
            } else {
                twoColumnEntries(store: store, entries: entries)
            }
        }
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
