import SwiftUI
import PleviCore

struct HomeView: View {
    var navigate: (Route) -> Void
    var refreshToken: Int = 0
    /// Whether this section is the one currently shown.
    var isActive: Bool = true

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(PlaybackHistory.self) private var playbackHistory
    @Environment(PinnedItems.self) private var pinnedItems
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(OfflineLibrary.self) private var offlineLibrary
    #endif
    @State private var store: HomeStore?
    #if os(iOS)
    @State private var contentWidth: CGFloat = 0
    #endif

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        if isActive {
            mainContent
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        } else {
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if let store {
                homeContent(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .tint(palette.accent)
        #if os(iOS)
        .navigationTitle("Home")
        #endif
        .task {
            if store == nil, let client = authStore.client {
                store = HomeStore(
                    client: client, appSettings: appSettings, playbackHistory: playbackHistory, pinnedItems: pinnedItems,
                    snapshots: HomeSnapshotStore(), snapshotScope: authStore.loginServerURL()?.absoluteString
                )
            }
            await store?.loadInitial()
        }
        // Plays arriving from another device through iCloud: re-sort the row already on screen.
        .onChange(of: playbackHistory.playedAt) { _, _ in
            store?.reapplyHistoryOrdering()
        }
        // A pin made on another screen shows up here with fresh data the next time Home is on screen.
        .task(id: pinnedItems.items.map(\.id)) {
            await store?.loadPinned()
        }
        // Re-derives the query whenever a Home-relevant setting changes.
        .task(id: settingsKey) {
            await store?.reloadGrid()
        }
        .task(id: refreshToken) {
            // Skip the initial (0) value — the `.task {}` above already
            // covers first load; only react to a real "returned to root"
            // bump.
            guard refreshToken > 0 else { return }
            await store?.refresh()
        }
    }

    private var settingsKey: String {
        "\(appSettings.homeSortField.rawValue)|\(appSettings.homeSortOrder.rawValue)|\(appSettings.hideWatched(in: .home))|\(appSettings.videoTypeFilter?.rawValue ?? "all")"
    }

    @ViewBuilder
    private func homeContent(store: HomeStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                #if os(iOS)
                screenHeader
                #endif
                continueWatchingSection(store: store)
                pinnedSection(store: store)
                // No "Saved for offline" shelf here any more.
                newlyAddedSection(store: store)
            }
            .padding(.top, topInset)
            .padding(.bottom, 20)
            #if os(iOS)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            #endif
        }
        #if os(iOS)
        .refreshable {
            await store.refresh()
        }
        #endif
    }

    // MARK: - Continue Watching

    @ViewBuilder
    private func continueWatchingSection(store: HomeStore) -> some View {
        if case .loaded(let items) = store.continueWatching, !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                #if os(tvOS)
                sectionHeader(title: "Continue watching") { tvHeaderControls }
                #else
                sectionHeader(title: "Continue watching")
                #endif
                #if os(tvOS)
                continueWatchingCarousel(items: items, store: store)
                #else
                switch appSettings.continueWatchingStyle {
                case .carousel:
                    continueWatchingCarousel(items: items, store: store)
                case .list:
                    continueWatchingList(items: items, store: store)
                }
                #endif
            }
        }
    }

    #if os(tvOS)
    private func continueWatchingHasItems(_ store: HomeStore) -> Bool {
        if case .loaded(let items) = store.continueWatching { return !items.isEmpty }
        return false
    }
    #endif

    // MARK: - Pinned

    /// Membership and order come straight from `pinnedItems.items`, which this view observes directly.
    @ViewBuilder
    private func pinnedSection(store: HomeStore) -> some View {
        if !pinnedItems.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                #if os(tvOS)
                if continueWatchingHasItems(store) {
                    sectionHeader(title: "Pinned")
                } else {
                    sectionHeader(title: "Pinned") { tvHeaderControls }
                }
                #else
                sectionHeader(title: "Pinned")
                #endif
                pinnedCarousel(store: store)
            }
        }
    }

    /// Same skeleton as `continueWatchingCarousel` — a plain (non-lazy) `HStack`, same spacing
    /// and focus inset — so the shelf reads as the same rhythm as the row above it.
    @ViewBuilder
    private func pinnedCarousel(store: HomeStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: carouselSpacing) {
                ForEach(pinnedItems.items) { pin in
                    pinnedCell(pin, store: store)
                }
            }
            .pleviRootHorizontalInset(horizontalInset)
            .padding(.vertical, carouselFocusInset)
            .padding(.bottom, 4)
        }
        #if os(tvOS)
        // Same skeleton, same clip — see `continueWatchingCarousel`'s identical fix.
        .scrollClipDisabled()
        #endif
    }

    @ViewBuilder
    private func pinnedCell(_ pin: PinnedItem, store: HomeStore) -> some View {
        switch pin.kind {
        case .playlist:
            // The fresh model once `loadPinned()` lands, or else one built from the snapshot.
            let playlist = store.pinnedPlaylists[pin.targetId] ?? Playlist(
                playlistId: pin.targetId,
                playlistName: pin.title,
                playlistChannel: pin.subtitle,
                playlistThumbnail: pin.thumbnail
            )
            NavigationLink(value: Route.playlist(pin.targetId)) {
                PlaylistCard(playlist: playlist)
                    .frame(width: pinnedPlaylistCardWidth)
            }
            #if os(tvOS)
            .pleviSelectableStyle()
            #else
            .buttonStyle(.plain)
            #endif
            .pinToHomeContextMenu(.playlist(playlist))
            // `PlaylistCard`/`ChannelCard` already supply a rich accessibility label (name,
            // subscribed state, count); this shelf's own cells just need the two things unique
            // to being pinned, not a full duplicate of that logic.
            .accessibilityLabel("\(playlist.playlistName ?? "Untitled playlist"), pinned")
            .accessibilityHint("Touch and hold to unpin.")
        case .channel:
            let channel = store.pinnedChannels[pin.targetId] ?? Channel(
                channelId: pin.targetId,
                channelName: pin.title,
                channelThumbUrl: pin.thumbnail
            )
            NavigationLink(value: Route.channel(pin.targetId)) {
                ChannelCard(channel: channel)
                    .frame(width: pinnedChannelCardWidth)
            }
            #if os(tvOS)
            .pleviSelectableStyle()
            #else
            .buttonStyle(.plain)
            #endif
            .pinToHomeContextMenu(.channel(channel))
            .accessibilityLabel("\(channel.channelName ?? "Unknown channel"), pinned")
            .accessibilityHint("Touch and hold to unpin.")
        }
    }

    private var pinnedPlaylistCardWidth: CGFloat {
        matchedCardWidth / Self.continueWatchingScaleFactor
    }

    private var pinnedChannelCardWidth: CGFloat {
        #if os(iOS)
        let available = contentWidth - 2 * horizontalInset
        guard available > 0 else { return 160 }
        if horizontalSizeClass == .regular {
            return (available - 5 * 20) / 6
        } else {
            return (available - 2 * 16) / 3
        }
        #else
        // D7: see `matchedCardWidth`'s identical note on why the leading and trailing insets are no longer the same number and so can't be doubled as one.
        let available = Self.tvScreenWidth - PleviMetrics.insetTVLeadingRoot - horizontalInset
        return (available - 5 * 32) / 6
        #endif
    }

    /// A plain `HStack`, not a `LazyHStack`, on both platforms. tvOS scrolls by moving
    /// focus, so a lazy row would have nothing built to move focus *to* — the same trap
    /// `content`'s `TVOSEagerStack` exists for one level up.
    @ViewBuilder
    private func continueWatchingCarousel(items: [Video], store: HomeStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: carouselSpacing) {
                ForEach(items) { video in
                    NavigationLink(value: Route.video(video.id)) {
                        continueWatchingCardContent(video: video, store: store)
                            .frame(width: matchedCardWidth)
                    }
                    #if os(tvOS)
                    .pleviSelectableStyle()
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                }
            }
            .pleviRootHorizontalInset(horizontalInset)
            // tvOS grows the focused card, and a `ScrollView` clips: without room around the
            // row the focused card's ring and shadow are cut off at the top and bottom.
            .padding(.vertical, carouselFocusInset)
            .padding(.bottom, 4)
        }
        #if os(tvOS)
        // Padding alone only moves where the clip happens, it does not stop it happening.
        .scrollClipDisabled()
        #endif
    }

    /// Matches the gap between grid cards on each platform, so the shelf reads as the same
    /// rhythm as the grid under it rather than a denser row.
    private var carouselSpacing: CGFloat {
        #if os(tvOS)
        32
        #else
        16
        #endif
    }

    private var carouselFocusInset: CGFloat {
        #if os(tvOS)
        16
        #else
        0
        #endif
    }
    #if os(iOS)

    @ViewBuilder
    private func continueWatchingList(items: [Video], store: HomeStore) -> some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(columns: continueWatchingListColumns, alignment: .leading, spacing: 20) {
                ForEach(items) { video in
                    NavigationLink(value: Route.video(video.id)) {
                        continueWatchingCardContent(video: video, store: store)
                    }
                    .buttonStyle(.plain)
                    .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                }
            }
            .pleviRootHorizontalInset(horizontalInset)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(items) { video in
                    NavigationLink(value: Route.video(video.id)) {
                        continueWatchingRowContent(video: video, store: store)
                    }
                    .buttonStyle(.plain)
                    .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                }
            }
            .pleviRootHorizontalInset(horizontalInset)
        }
    }

    /// Distinct from `gridColumns` (Newly Added's adaptive column count) — the spec calls for exactly 4-up here regardless of iPad size.
    private var continueWatchingListColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
    }

    @ViewBuilder
    private func continueWatchingRowContent(video: Video, store: HomeStore) -> some View {
        VideoRow(
            video: video,
            layout: .row,
            actions: videoActions(list: store)
        )
    }

    // MARK: - Saved for offline

    /// A horizontal shelf of every fully-downloaded video, same carousel shape as Continue Watching's own `.carousel` style.
    #endif

    private var matchedCardWidth: CGFloat {
        #if os(iOS)
        let available = contentWidth - 2 * horizontalInset
        guard available > 0 else { return 260 * Self.continueWatchingScaleFactor }
        let newlyAddedWidth: CGFloat
        if horizontalSizeClass == .regular {
            let minimum: CGFloat = 240
            let maximum: CGFloat = 300
            let spacing: CGFloat = 20
            let count = max(1, Int((available + spacing) / (minimum + spacing)))
            let raw = (available - CGFloat(count - 1) * spacing) / CGFloat(count)
            newlyAddedWidth = min(raw, maximum)
        } else {
            // Matches `gridColumns`' iPhone branch: two flexible columns,
            // 12pt spacing between them.
            newlyAddedWidth = (available - 12) / 2
        }
        return newlyAddedWidth * Self.continueWatchingScaleFactor
        #else
        let available = Self.tvScreenWidth - PleviMetrics.insetTVLeadingRoot - horizontalInset
        let newlyAddedWidth = (available - 3 * 32) / 4
        return newlyAddedWidth * Self.continueWatchingScaleFactor
        #endif
    }

    #if os(tvOS)
    /// tvOS's fixed logical width. Not the pixel resolution — a 4K Apple TV lays out in the
    /// same 1920x1080 points a 1080p one does.
    private static let tvScreenWidth: CGFloat = 1920
    #endif

    /// How much larger a Continue Watching card is than the Newly Added
    /// grid card it's otherwise matched to — see `matchedCardWidth`'s own
    /// doc comment for why this is 1.1 × 1.1, not 1.2.
    private static let continueWatchingScaleFactor: CGFloat = 1.1 * 1.1

    @ViewBuilder
    private func continueWatchingCardContent(video: Video, store: HomeStore) -> some View {
        VideoRow(
            video: video,
            layout: .card,
            actions: videoActions(list: store)
        )
    }

    #if os(tvOS)

    @ViewBuilder
    private func platformGrid(
        items: [Video],
        store: HomeStore,
        onAppearItem: ((Video) -> Void)? = nil
    ) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 40) {
            ForEach(items) { video in
                NavigationLink(value: Route.video(video.id)) {
                    VideoRow(
                        video: video,
                        layout: .card,
                        actions: videoActions(list: store)
                    )
                }
                .pleviSelectableStyle()
                .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                .task { onAppearItem?(video) }
            }
        }
        .pleviRootHorizontalInset(horizontalInset)
    }
    #endif

    // MARK: - Newly Added

    @ViewBuilder
    private func newlyAddedSection(store: HomeStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(tvOS)
            if continueWatchingHasItems(store) || !pinnedItems.items.isEmpty {
                sectionHeader(title: "Newly added")
            } else {
                sectionHeader(title: "Newly added") { tvHeaderControls }
            }
            #else
            sectionHeader(title: "Newly added")
            #endif

            if store.gridItems.isEmpty {
                emptyGridState(store: store)
            } else {
                #if os(tvOS)
                platformGrid(items: store.gridItems, store: store) { video in
                    Task { await store.loadNextPageIfNeeded(currentItem: video) }
                }
                #else
                switch appSettings.homeViewStyle {
                case .grid:
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                        ForEach(store.gridItems) { video in
                            NavigationLink(value: Route.video(video.id)) {
                                VideoRow(
                                    video: video,
                                    layout: .card,
                                    actions: videoActions(list: store)
                                )
                            }
                            .buttonStyle(.plain)
                            .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                            .task {
                                await store.loadNextPageIfNeeded(currentItem: video)
                            }
                        }
                    }
                    .pleviRootHorizontalInset(horizontalInset)
                case .list:
                    LazyVStack(spacing: 0) {
                        ForEach(store.gridItems) { video in
                            NavigationLink(value: Route.video(video.id)) {
                                VideoRow(
                                    video: video,
                                    layout: .row,
                                    actions: videoActions(list: store)
                                )
                            }
                            .buttonStyle(.plain)
                            .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                            .task {
                                await store.loadNextPageIfNeeded(currentItem: video)
                            }
                            if video.id != store.gridItems.last?.id {
                                Divider()
                                    .overlay(palette.secondary.opacity(0.25))
                            }
                        }
                    }
                    .pleviRootHorizontalInset(horizontalInset)
                }
                #endif

                if store.isLoadingNextPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                if let error = store.gridPageError {
                    Text(error.errorDescription ?? "Couldn't load more videos.")
                        .pleviBody()
                        .foregroundStyle(palette.secondary)
                        .pleviRootHorizontalInset(horizontalInset)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyGridState(store: HomeStore) -> some View {
        switch store.gridLoadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") {
                    Task { await store.reloadGrid(force: true) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .loaded:
            ContentUnavailableView(
                "No Videos",
                systemImage: "video.slash",
                description: Text("Nothing matches the current filters.")
            )
            .padding(.top, 20)
        }
    }

    private func videoActions(list: any VideoMutating) -> VideoActions {
        VideoActions(list: list, coordinator: videoActionsCoordinator, navigate: navigate)
    }

    // MARK: - Section header

    /// Shared by both sections.
    @ViewBuilder
    private func sectionHeader<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .pleviSectionHeading()
                .foregroundStyle(palette.ink)
            #if os(tvOS)
            // Leading, next to the heading, not out past a `Spacer` on the trailing edge.
            trailing()
            Spacer(minLength: 8)
            #else
            Spacer(minLength: 8)
            trailing()
            #endif
        }
        .pleviRootHorizontalInset(horizontalInset)
    }

    // MARK: - Layout metrics

    /// `PleviMetrics.insetPhone`/`insetPad`/`insetTV` — the screen-edge inset every section's content and header align to.
    #if os(iOS)
    /// Headline and the view/sort controls on one line, aligned to the same
    /// horizontal inset as every section below it.
    private var screenHeader: some View {
        @Bindable var appSettings = appSettings
        return HStack(spacing: 12) {
            Text("Home")
                .pleviScreenTitle()
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            #if os(iOS)
            OfflineDownloadsButton()
                .modifier(HeaderControlChip(palette: palette))
            #endif
            WatchedFilterToggleButton(hideWatched: appSettings.watchedFilterBinding(.home))
                .modifier(HeaderControlChip(palette: palette))
            SortMenuButton(field: $appSettings.homeSortField, order: $appSettings.homeSortOrder, fieldTitle: \.title)
                .modifier(HeaderControlChip(palette: palette))
            ViewStyleToggleButton(viewStyle: $appSettings.homeViewStyle)
                .modifier(HeaderControlChip(palette: palette))
        }
        .pleviRootHorizontalInset(horizontalInset)
    }
    #endif

    #if os(tvOS)
     /// Watched filter then sort, the order every other screen uses. Both section headers
    private var tvHeaderControls: some View {
        @Bindable var appSettings = appSettings
        return HStack(spacing: 16) {
            TVWatchedFilterToggle(hideWatched: appSettings.watchedFilterBinding(.home), palette: palette)
            tvSortCaptionMenu
        }
    }

   private var tvSortCaptionMenu: some View {
        @Bindable var appSettings = appSettings
        return Menu {
            Picker("Sort By", selection: $appSettings.homeSortField) {
                ForEach(HomeSortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            Picker("Order", selection: $appSettings.homeSortOrder) {
                Label("Ascending", systemImage: "arrow.up").tag(HomeSortOrder.asc)
                Label("Descending", systemImage: "arrow.down").tag(HomeSortOrder.desc)
            }
        } label: {
            Text(tvSortCaptionText)
                .tvControlChip(palette)
        }
        .pleviSelectableStyle()
    }

    private var tvSortCaptionText: String {
        let order = appSettings.homeSortOrder == .desc ? "Newest first" : "Oldest first"
        return "\(appSettings.homeSortField.title) · \(order)"
    }
    #endif

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.horizontal
        #elseif os(iOS)
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
        #endif
    }

    /// tvOS's own top safe-area inset — content must not sit flush under the top tab bar.
    private var topInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.vertical
        #else
        PleviMetrics.screenHeaderTop
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        48
        #else
        28
        #endif
    }

    /// Newly Added's own column count — adaptive on iPad (see its own comment below), fixed 2-up on iPhone.
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
}

#Preview {
    NavigationStack {
        HomeView(navigate: { _ in })
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(VideoActionsCoordinator())
    .environment(PinnedItems(scope: "", cloud: nil))
}
