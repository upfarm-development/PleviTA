// `navigate` is threaded through so a video card's "Open Channel" action and a playlist tile both push further onto the section's own `NavigationStack`.

import SwiftUI
import PleviCore

struct ChannelDetailView: View {
    let channelId: String
    var navigate: (Route) -> Void = { _ in }

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(\.offlineDownloader) private var offlineDownloader
    @State private var saveAllResultMessage: String?
    /// Set once "Save All" has been tapped and is waiting for the user to agree — see
    /// `OfflineBatchSave.Plan`, which carries the count, the size and any shortfall.
    @State private var pendingSaveAll: OfflineBatchSave.Plan?
    #endif
    @State private var store: ChannelDetailStore?
    /// The video this screen last pushed, so coming back can refresh just that row rather
    /// than reloading the list — see `refreshLastOpenedVideo`.
    @State private var lastOpenedVideoId: String?

    /// Refreshes the one row the user just came back from — see
    /// `PlaylistDetailView.refreshLastOpenedVideo` for why this replaces a blanket reload.
    private func refreshLastOpenedVideo(store: ChannelDetailStore, client: TAClient) async {
        guard let videoId = lastOpenedVideoId else { return }
        lastOpenedVideoId = nil
        guard let fresh = try? await client.video(id: videoId) else { return }
        for tab in ChannelSubTab.allCases {
            gridStore(for: tab, store: store)?.apply(updated: fresh)
        }
    }

    private func gridStore(for tab: ChannelSubTab, store: ChannelDetailStore) -> ChannelVideoGridStore? {
        switch tab {
        case .videos: return store.videosGrid
        case .streams: return store.streamsGrid
        case .shorts: return store.shortsGrid
        case .playlists: return nil
        }
    }

    @State private var selectedTab: ChannelSubTab = .videos
    @State private var isConfirmingMarkAllWatched = false
    /// Set when `RemoteImage` reports the banner path (a real, non-nil URL Tube Archivist sent) actually failed to load.
    @State private var bannerLoadFailed = false

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if let store {
                content(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .toolbar {
            // Watched, sort, overflow — `.topBarTrailing` renders in declaration order left to right.
            ToolbarItem(placement: .topBarTrailing) {
                @Bindable var appSettings = appSettings
                WatchedFilterToggleButton(hideWatched: appSettings.watchedFilterBinding(.channelVideos))
            }
            ToolbarItem(placement: .topBarTrailing) {
                @Bindable var appSettings = appSettings
                SortMenuButton(field: $appSettings.channelVideoSortField, order: $appSettings.channelVideoSortOrder, fieldTitle: \.title)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let channel = store?.channel {
                        PinToHomeMenuItem(target: .channel(channel))
                        Divider()
                    }
                    Button {
                        isConfirmingMarkAllWatched = true
                    } label: {
                        Label("Mark All Watched", systemImage: "checkmark.circle")
                    }
                    Button {
                        Task {
                            await store?.loadHeader()
                            await loadSelectedTab(store: store)
                        }
                    } label: {
                        Label("Refresh Channel", systemImage: "arrow.clockwise")
                    }
                    if selectedTab != .playlists {
                        Button {
                            Task { await prepareSaveAll(store: store) }
                        } label: {
                            Label("Save All to iPhone", systemImage: "arrow.down.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                // On the menu both are chosen from, so each dialog opens from this button.
                // Attached to the whole screen, they pointed at nothing in particular. The
                // menu is always in the toolbar, so the dialogs can't vanish with it.
                .markAllWatchedConfirmation(
                    Self.markAllWatchedPrompt(count: store?.aggsState.value?.totalItems),
                    isPresented: $isConfirmingMarkAllWatched
                ) {
                    if let store { Task { await store.markAllWatched() } }
                }
                .saveAllConfirmation($pendingSaveAll) { plan in
                    Task { await performSaveAll(plan) }
                }
            }
        }
        #endif
        #if os(tvOS)
        // Apple TV's own trigger is `tvMoreMenu`, and a dialog there fills the screen with no
        // arrow, so it stays up here where it can't vanish with the row that holds it. iPhone
        // and iPad attach it to the toolbar menu instead.
        .markAllWatchedConfirmation(
            Self.markAllWatchedPrompt(count: store?.aggsState.value?.totalItems),
            isPresented: $isConfirmingMarkAllWatched
        ) {
            if let store { Task { await store.markAllWatched() } }
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
        .task(id: channelId) {
            guard let client = authStore.client else { return }
            // Same guard, same reason as `PlaylistDetailView`'s — see it for the full story.
            if let existing = store, existing.channelId == channelId {
                if case .loaded = existing.channelState {
                    await refreshLastOpenedVideo(store: existing, client: client)
                    return
                }
                await existing.loadHeader()
                return
            }
            let newStore = ChannelDetailStore(client: client, appSettings: appSettings, channelId: channelId)
            store = newStore
            await newStore.loadHeader()
        }
        // Re-fetches the selected tab's grid whenever the tab changes or
        // this channel's own sort/hide-watched setting changes — each grid
        // store's own query-key dedup makes this safe to call redundantly.
        .task(id: gridTaskKey) {
            await loadSelectedTab(store: store)
        }
    }

    private var gridTaskKey: String {
        "\(selectedTab.rawValue)|\(appSettings.channelVideoSortField.rawValue)|\(appSettings.channelVideoSortOrder.rawValue)|\(appSettings.hideWatched(in: .channelVideos))"
    }

    private func loadSelectedTab(store: ChannelDetailStore?) async {
        guard let store else { return }
        switch selectedTab {
        case .videos: await store.videosGrid.loadFirstPageIfNeeded()
        case .streams: await store.streamsGrid.loadFirstPageIfNeeded()
        case .shorts: await store.shortsGrid.loadFirstPageIfNeeded()
        case .playlists: await store.loadPlaylistsIfNeeded()
        }
    }

    #if os(iOS)
    private func currentTabGridStore(_ store: ChannelDetailStore?) -> ChannelVideoGridStore? {
        switch selectedTab {
        case .videos: return store?.videosGrid
        case .streams: return store?.streamsGrid
        case .shorts: return store?.shortsGrid
        case .playlists: return nil
        }
    }

    /// Works out what "Save All" would do and asks first.
    private func prepareSaveAll(store: ChannelDetailStore?) async {
        let videos = await saveAllCandidates(store: store)
        guard !videos.isEmpty else {
            saveAllResultMessage = "There are no videos here to save."
            return
        }
        let plan = OfflineBatchSave.plan(videos, library: offlineLibrary)
        guard plan.count > 0 else {
            saveAllResultMessage = "Every video in this tab is already saved to this iPhone."
            return
        }
        pendingSaveAll = plan
    }

    /// Every video the current sub-tab holds — the slow half, so `prepareSaveAll` does it
    /// once and the confirmed action reuses the result.
    private func saveAllCandidates(store: ChannelDetailStore?) async -> [Video] {
        guard let gridStore = currentTabGridStore(store) else { return [] }
        return (try? await gridStore.allVideos()) ?? []
    }

    private func performSaveAll(_ plan: OfflineBatchSave.Plan) async {
        guard let offlineDownloader, let client = authStore.client else { return }
        let saved = await OfflineBatchSave.saveAll(
            plan.videos, client: client, library: offlineLibrary, downloader: offlineDownloader,
            allowsCellular: appSettings.allowCellularDownloads
        )
        saveAllResultMessage = saved == 0
            ? "Every video in this tab is already saved to this iPhone."
            : "Saving \(saved) video\(saved == 1 ? "" : "s") to this iPhone."
    }
    #endif

    @ViewBuilder
    private func content(store: ChannelDetailStore) -> some View {
        ScrollView {
            TVOSEagerStack(alignment: .leading, spacing: 20) {
                heroSection(store: store)
                tabPicker(store: store)
                tabContent(store: store)
            }
            .padding(.bottom, 24)
        }
        #if os(iOS)
        .refreshable {
            bannerLoadFailed = false
            await store.loadHeader()
            await loadSelectedTab(store: store)
        }
        #endif
    }

    // MARK: - Layout metrics

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.horizontal
        #elseif os(iOS)
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
        #endif
    }

    /// The left edge on its own, for the one thing positioned from it alone (the avatar over the
    /// banner). On Apple TV the sidebar's rail sits over that edge on every screen, so it is the
    /// wider root inset there, like `pleviRootHorizontalInset` gives everything else.
    private var leadingInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTVLeadingRoot
        #else
        horizontalInset
        #endif
    }

    private var avatarDiameter: CGFloat {
        #if os(tvOS)
        132
        #elseif os(iOS)
        horizontalSizeClass == .regular ? 104 : 88
        #endif
    }

    /// Gap between the avatar's own protruding bottom half and the name
    /// below it.
    private let heroToHeaderSpacing: CGFloat = 14

    // MARK: - Hero (banner + overlapping avatar)

    @ViewBuilder
    private func heroSection(store: ChannelDetailStore) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                banner(store: store)

                if let channel = store.channel {
                    avatarBadge(channel: channel)
                        .padding(.leading, leadingInset)
                        // Half the avatar's own height, so it sits centred
                        // on the banner's bottom edge rather than fully
                        // above or below it — "the avatar card overlaps it."
                        .offset(y: avatarDiameter / 2)
                }
            }
            // Reserves layout space for the avatar's protruding bottom
            // half so `header` below never overlaps it.
            .padding(.bottom, avatarDiameter / 2 + heroToHeaderSpacing)

            header(store: store)
        }
    }

    @ViewBuilder
    private func banner(store: ChannelDetailStore) -> some View {
        switch store.channelState {
        case .idle, .loading:
            bannerFrame(Rectangle().fill(.quaternary))
                .overlay(ProgressView())
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Couldn't load this channel.")
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") { Task { await store.loadChannel() } }
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
            .background(palette.canvas)
        case .loaded(let channel):
            if bannerLoadFailed {
                blurredAvatarBanner(channel: channel)
            } else {
                bannerFrame(
                    RemoteImage(path: bannerPath(channel: channel), maxPixelSize: 1024, onLoadFailed: { bannerLoadFailed = true })
                )
            }
        }
    }

    @ViewBuilder
    private func blurredAvatarBanner(channel: Channel) -> some View {
        bannerFrame(RemoteImage(path: channel.channelThumbUrl, maxPixelSize: 480))
            .blur(radius: 28)
            .overlay(Color.black.opacity(0.18))
            .clipped()
    }

    private func bannerPath(channel: Channel) -> String? {
        #if os(tvOS)
        channel.channelTvartUrl ?? channel.channelBannerUrl
        #else
        channel.channelBannerUrl ?? channel.channelTvartUrl
        #endif
    }

    /// iOS/iPadOS only now — see `tvBannerHeight` for why tvOS can't size a
    /// banner by ratio at all. The redesign's spec'd "3:1 band."
    private var bannerAspectRatio: CGFloat {
        3.0 / 1.0
    }

    /// tvOS sizes the banner by height, never by aspect ratio.
    private var tvBannerHeight: CGFloat { 300 }

    /// Applies whichever of the two sizing rules above this platform uses, so
    /// the three banner states (loading, loaded, blurred-avatar fallback) can
    /// never drift apart and jump height as one replaces another.
    @ViewBuilder
    private func bannerFrame(_ content: some View) -> some View {
        #if os(tvOS)
        content
            .frame(maxWidth: .infinity)
            .frame(height: tvBannerHeight)
            .clipped()
        #else
        content
            .aspectRatio(bannerAspectRatio, contentMode: .fit)
        #endif
    }

    @ViewBuilder
    private func avatarBadge(channel: Channel) -> some View {
        RemoteImage(path: channel.channelThumbUrl, maxPixelSize: 240)
            .aspectRatio(1, contentMode: .fill)
            .frame(width: avatarDiameter, height: avatarDiameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(palette.card, lineWidth: 4))
            #if !os(tvOS)
            .shadow(color: palette.cardShadow, radius: 6, x: 0, y: 2)
            #endif
    }

    // MARK: - Header (name, aggregates, description, actions)

    @ViewBuilder
    private func header(store: ChannelDetailStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let channel = store.channel {
                Text(channel.channelName ?? "Unknown channel")
                    .pleviScreenTitle()
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aggregatesLine(store: store)

            if let description = store.channel?.channelDescription, !description.isEmpty {
                DescriptionText(text: description, onSeek: { _ in }, maxCollapsedLines: 2)
            }

            actionsRow(store: store)
        }
        .pleviRootHorizontalInset(horizontalInset)
    }

    @ViewBuilder
    private func aggregatesLine(store: ChannelDetailStore) -> some View {
        switch store.aggsState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            // Secondary info; a failed aggregates fetch shouldn't block the rest of the page.
            EmptyView()
        case .loaded(let aggs):
            if let text = aggregatesText(aggs) {
                Text(text)
                    .pleviMono()
                    .foregroundStyle(palette.metadata)
            }
        }
    }

    private func aggregatesText(_ aggs: ChannelAggs) -> String? {
        var parts: [String] = []
        if let totalItems = aggs.totalItems {
            parts.append("\(totalItems) video\(totalItems == 1 ? "" : "s")")
        }
        if let totalSize = aggs.totalSize {
            parts.append(PleviFormatting.byteCount(totalSize))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func actionsRow(store: ChannelDetailStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if store.channel?.channelSubscribed == true {
                    subscribedBadge
                }
                // `Mark All Watched` moved into the overflow menu, and its filled button took the spinner with it.
                if store.isMarkingAllWatched {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Marking all watched…")
                            .pleviMono()
                            .foregroundStyle(palette.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let error = store.markAllWatchedError {
                Text(error.errorDescription ?? "Couldn't mark all watched.")
                    .pleviMono()
                    .foregroundStyle(.red)
            }
        }
    }

    /// Names the number when the server has actually told us one, and says nothing about scale when it hasn't.
    static func markAllWatchedPrompt(count: Int?) -> String {
        guard let count, count > 1 else {
            return "Mark every video in this channel as watched?"
        }
        return "Mark all \(count) videos in this channel as watched?"
    }

    private var subscribedBadge: some View {
        Label("Subscribed", systemImage: "checkmark.seal.fill")
            .font(actionRowFont)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, actionChipPadding.h)
            .padding(.vertical, actionChipPadding.v)
            .background(palette.accentTint, in: Capsule())
    }

    private var actionRowFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold)
        #else
        .system(size: 14, weight: .semibold)
        #endif
    }

    private var actionChipPadding: (h: CGFloat, v: CGFloat) {
        #if os(tvOS)
        (24, 14)
        #else
        (16, 10)
        #endif
    }

    private var actionChipFocusRingRadius: CGFloat {
        #if os(tvOS)
        28
        #else
        20
        #endif
    }

    // MARK: - Sub-tabs

    @ViewBuilder
    private func tabPicker(store: ChannelDetailStore) -> some View {
        #if os(tvOS)
        tvTabAndControlsRow(store: store)
        #else
        if store.availableTabs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.availableTabs) { tab in
                        tabChip(tab)
                    }
                }
                .pleviRootHorizontalInset(horizontalInset)
            }
        }
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private func tvTabAndControlsRow(store: ChannelDetailStore) -> some View {
        @Bindable var appSettings = appSettings
        HStack(spacing: 16) {
            if store.availableTabs.count > 1 {
                // No horizontal `ScrollView` on tvOS: there are at most four chips and
                // 1740pt of usable width, so there is nothing to scroll, and a scroll view
                // here would let the trailing controls slide off the edge.
                ForEach(store.availableTabs) { tab in
                    tabChip(tab)
                }
            }
            // The same three controls `PlaylistDetailView.tvControlsRow` carries, in the same order: watched filter, sort, overflow.
            if selectedTab.isVideoGrid {
                TVWatchedFilterToggle(hideWatched: appSettings.watchedFilterBinding(.channelVideos), palette: palette)
                tvSortMenu
            }
            tvMoreMenu
            Spacer(minLength: 8)
        }
        .pleviRootHorizontalInset(horizontalInset)
    }
    #endif

    private func tabChip(_ tab: ChannelSubTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.title)
                .font(actionRowFont)
                .padding(.horizontal, actionChipPadding.h)
                .padding(.vertical, actionChipPadding.v - 2)
                .background(
                    Capsule().fill(selectedTab == tab ? palette.accent : tabChipBackground)
                )
                .foregroundStyle(selectedTab == tab ? Color.white : palette.ink)
                .tvFocusRing(cornerRadius: actionChipFocusRingRadius)
        }
        // `.plain` was the other half of it: on tvOS that style draws the system's opaque white focus plate behind the label — see `TVFocusRing.swift`.
        .pleviSelectableStyle()
    }

    #if os(tvOS)
    private var tvSortMenu: some View {
        @Bindable var appSettings = appSettings
        return Menu {
            Picker("Sort By", selection: $appSettings.channelVideoSortField) {
                ForEach(HomeSortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            Picker("Order", selection: $appSettings.channelVideoSortOrder) {
                Label("Ascending", systemImage: "arrow.up").tag(HomeSortOrder.asc)
                Label("Descending", systemImage: "arrow.down").tag(HomeSortOrder.desc)
            }
        } label: {
            Text(tvSortCaption)
                .tvControlChip(palette)
        }
        .pleviSelectableStyle()
    }

    /// `PlaylistDetailView.tvControlsRow`'s "More", item for item, with this screen's own
    /// refresh. Rendered on every tab, including Playlists: marking a channel watched and
    /// refreshing it are not about which sub-tab is open, unlike the sort beside it.
    private var tvMoreMenu: some View {
        Menu {
            if let channel = store?.channel {
                PinToHomeMenuItem(target: .channel(channel))
                Divider()
            }
            Button {
                isConfirmingMarkAllWatched = true
            } label: {
                Label("Mark All Watched", systemImage: "checkmark.circle")
            }
            Button {
                Task {
                    await store?.loadHeader()
                    await loadSelectedTab(store: store)
                }
            } label: {
                Label("Refresh Channel", systemImage: "arrow.clockwise")
            }
        } label: {
            Text("More")
                .tvControlChip(palette)
        }
        .pleviSelectableStyle()
    }

    private var tvSortCaption: String {
        let order = appSettings.channelVideoSortOrder == .desc ? "Newest first" : "Oldest first"
        return "\(appSettings.channelVideoSortField.title) · \(order)"
    }
    #endif

    private var tabChipBackground: Color {
        #if os(tvOS)
        palette.cardFillOnGrid
        #else
        palette.card
        #endif
    }

    @ViewBuilder
    private func tabContent(store: ChannelDetailStore) -> some View {
        switch selectedTab {
        case .videos:
            videoGrid(gridStore: store.videosGrid)
        case .streams:
            videoGrid(gridStore: store.streamsGrid)
        case .shorts:
            videoGrid(gridStore: store.shortsGrid)
        case .playlists:
            playlistsSection(store: store)
        }
    }

    // MARK: - Video grid
    // `VideoRow(layout: .card)` already draws its secondary line as `channel · published date` — never file size (`VideoRow.swift`'s own `cardBody`).

    @ViewBuilder
    private func videoGrid(gridStore: ChannelVideoGridStore) -> some View {
        if gridStore.items.isEmpty {
            emptyGridState(gridStore: gridStore)
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                ForEach(gridStore.items) { video in
                    // A `Button` rather than `NavigationLink(value:)` so the id can be noted
                    // on the way out — `refreshLastOpenedVideo` uses it to bring one row up to
                    // date on the way back instead of reloading the grid.
                    Button {
                        lastOpenedVideoId = video.id
                        navigate(.video(video.id))
                    } label: {
                        VideoRow(
                            video: video,
                            layout: .card,
                            actions: videoActions(list: gridStore)
                        )
                    }
                    .pleviSelectableStyle()
                    .videoActionsContextMenu(video: video, actions: videoActions(list: gridStore))
                    .task {
                        await gridStore.loadNextPageIfNeeded(currentItem: video)
                    }
                }
            }
            .pleviRootHorizontalInset(horizontalInset)

            if gridStore.isLoadingNextPage {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            if let error = gridStore.pageError {
                Text(error.errorDescription ?? "Couldn't load more videos.")
                    .pleviMono()
                    .foregroundStyle(.red)
                    .pleviRootHorizontalInset(horizontalInset)
            }
        }
    }

    private func videoActions(list: any VideoMutating) -> VideoActions {
        VideoActions(list: list, coordinator: videoActionsCoordinator, navigate: navigate)
    }

    @ViewBuilder
    private func emptyGridState(gridStore: ChannelVideoGridStore) -> some View {
        switch gridStore.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") {
                    Task { await gridStore.reload(force: true) }
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .loaded:
            ContentUnavailableView(
                "No Videos",
                systemImage: "video.slash",
                description: Text("Nothing here yet.")
            )
            .padding(.top, 20)
        }
    }

    // MARK: - Playlists sub-tab

    @ViewBuilder
    private func playlistsSection(store: ChannelDetailStore) -> some View {
        switch store.playlistsState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Couldn't load playlists.")
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") {
                    Task { await store.retryPlaylists() }
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .loaded(let playlists):
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "list.and.film",
                    description: Text("This channel has no playlists.")
                )
                .padding(.top, 20)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                    ForEach(playlists) { playlist in
                        Button {
                            navigate(.playlist(playlist.id))
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .pleviSelectableStyle()
                        .pinToHomeContextMenu(.playlist(playlist))
                    }
                }
                .pleviRootHorizontalInset(horizontalInset)
            }
        }
    }

    private var gridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 4)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        #endif
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
}

#Preview {
    NavigationStack {
        ChannelDetailView(channelId: Channel.previewChannel.id)
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(VideoActionsCoordinator())
    .environment(PinnedItems(scope: "", cloud: nil))
}
