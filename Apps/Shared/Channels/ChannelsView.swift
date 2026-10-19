// List/grid of channels: thumbnail, name, subscribed indicator.

import SwiftUI
import PleviCore

struct ChannelsView: View {
    var navigate: (Route) -> Void
    var isActive: Bool = true

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var store: ChannelsStore?
    #if os(tvOS)
    /// The channel holding focus, so the first one can be made the page's default focus.
    @FocusState private var focusedChannel: Channel.ID?
    @Environment(NavigationModel.self) private var navigation
    /// When the sidebar last asked this page to take focus, if it has not been able to yet.
    @State private var entryRequestedAt: Date?
    #endif

    /// The 3-way chip selection — see this file's own doc comment (point 1).
    @State private var activityFilter: ChannelActivityFilter = .all
    /// A–Z / Z–A — see this file's own doc comment (point 2).
    @State private var nameSortOrder: HomeSortOrder = .asc

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        if isActive {
            #if os(tvOS)
            // See `tvControlsRow(channels:)` below for where these two controls actually live on tvOS instead.
            mainContent
            #else
            mainContent
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
                content(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        #if os(iOS)
        .navigationTitle("Channels")
        #endif
        .task {
            if store == nil, let client = authStore.client {
                store = ChannelsStore(client: client, appSettings: appSettings)
                activityFilter = appSettings.channelsSubscribedOnly ? .subscribed : .all
            }
            await store?.loadFirstPage()
        }
        // Re-derives the query whenever "Subscribed only" flips.
        .task(id: appSettings.channelsSubscribedOnly) {
            await store?.loadFirstPage()
        }
    }

    @ViewBuilder
    private func content(store: ChannelsStore) -> some View {
        let channels = displayedChannels(from: store.items)
        ScrollView {
            VStack(alignment: .leading, spacing: PleviMetrics.screenHeaderToControls) {
                #if os(iOS)
                screenHeader
                    .pleviRootHorizontalInset(horizontalInset)
                #endif
                #if os(tvOS)
                tvControlsRow(channels: channels)
                    .pleviRootHorizontalInset(horizontalInset)
                #else
                chipsControlCard
                    .pleviRootHorizontalInset(horizontalInset)
                #endif

                if channels.isEmpty {
                    emptyState(store: store)
                } else {
                    grid(store: store, channels: channels)
                }
            }
            .padding(.vertical, verticalInset)
        }
        #if os(iOS)
        .refreshable {
            await store.refresh()
        }
        #endif
        #if os(tvOS)
        // Entering the page puts focus on the first channel, as Home does on its first video,
        // rather than on the filter chips above the grid. See PlaylistsView for why it only
        // decides when nothing else does.
        .defaultFocus($focusedChannel, channels.first?.id)
        // Select on the menu hands focus to the page: put it on the first channel. A first visit
        // has no channels yet, so the request waits (briefly) for them.
        .onChange(of: navigation.pageEntryRequest) { _, _ in
            guard isActive else { return }
            entryRequestedAt = Date()
            focusFirstChannel(channels)
        }
        .onChange(of: channels.first?.id) { _, _ in
            if entryRequestedAt != nil { focusFirstChannel(channels) }
        }
        // Same bug, same fix, as PlaylistsView's identical grid — see that file's own comment
        // on this line: a focused ChannelCard's bottom line grows past the card's original
        // bounds (tvFocusRing's scale anchors at the top) and gets clipped by the ScrollView.
        .scrollClipDisabled()
        #endif
    }

    #if os(tvOS)
    private func focusFirstChannel(_ channels: [Channel]) {
        guard let requested = entryRequestedAt else { return }
        if Date().timeIntervalSince(requested) > 5 {
            entryRequestedAt = nil
            return
        }
        guard let id = channels.first?.id else { return }
        entryRequestedAt = nil
        // A beat after the sidebar lets go, so the focus engine is not mid-update.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            focusedChannel = id
        }
    }
    #endif

    // MARK: - Filter chips (All / Subscribed / Recently active)

    private func select(_ filter: ChannelActivityFilter) {
        activityFilter = filter
        appSettings.channelsSubscribedOnly = (filter == .subscribed)
    }

    private var chipsRow: some View {
        HStack(spacing: 12) {
            filterChip(title: "All", isSelected: activityFilter == .all) { select(.all) }
            filterChip(title: "Subscribed", isSelected: activityFilter == .subscribed) { select(.subscribed) }
            filterChip(title: recentlyActiveChipTitle, isSelected: activityFilter == .recentlyActive) { select(.recentlyActive) }
        }
    }

    private var recentlyActiveChipTitle: String {
        #if os(iOS)
        horizontalSizeClass == .compact ? "Active" : "Recently active"
        #else
        "Recently active"
        #endif
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(chipFont)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? palette.accent : chipUnselectedFill))
                .foregroundStyle(isSelected ? Color.white : palette.ink)
                .tvFocusRing(cornerRadius: 18)
        }
        .pleviSelectableStyle()
    }

    private var chipFont: Font {
        #if os(tvOS)
        // The same face as PlaylistsView's chips, so the two filter rows match.
        .subheadline.weight(.semibold)
        #else
        .system(size: 15, weight: .semibold)
        #endif
    }

    private var chipUnselectedFill: Color {
        #if os(tvOS)
        palette.secondary.opacity(0.15)
        #else
        palette.canvas
        #endif
    }

    #if os(iOS)
    private var chipsControlCard: some View {
        HStack(spacing: 12) {
            chipsRow
            Spacer(minLength: 0)
        }
        .padding(12)
        .pleviCard()
    }
    #endif

    #if os(tvOS)
    private func tvControlsRow(channels: [Channel]) -> some View {
        HStack(alignment: .center, spacing: 24) {
            chipsRow
            Spacer(minLength: 24)
            sortCaptionMenu(count: channels.count)
        }
    }
    #endif

    // MARK: - Sort (A–Z / Z–A)

    /// Shared by both the iOS/iPadOS header button and tvOS's content-row
    /// caption below — one `Menu` body, two different labels/entry points.
    @ViewBuilder
    private var sortPickerContent: some View {
        Picker("Sort", selection: $nameSortOrder) {
            Label("Name (A–Z)", systemImage: "arrow.up").tag(HomeSortOrder.asc)
            Label("Name (Z–A)", systemImage: "arrow.down").tag(HomeSortOrder.desc)
        }
    }

    #if os(iOS)
    #if os(iOS)
    /// Headline, count and the view/sort controls on one line.
    private var screenHeader: some View {
        @Bindable var appSettings = appSettings
        return HStack(spacing: 12) {
            Text("Channels")
                .pleviScreenTitle()
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            headerCountLabel
            // Alongside the other header controls rather than out on its own at the left.
            #if os(iOS)
            OfflineDownloadsButton()
                .modifier(HeaderControlChip(palette: palette))
            #endif
            ViewStyleToggleButton(viewStyle: $appSettings.channelsViewStyle)
                .modifier(HeaderControlChip(palette: palette))
            sortToolbarButton
                .modifier(HeaderControlChip(palette: palette))
        }
    }
    #endif

    private var sortToolbarButton: some View {
        Menu {
            sortPickerContent
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var headerCountLabel: some View {
        Text(headerCountText)
            .pleviMono()
            .foregroundStyle(palette.secondary)
    }

    private var headerCountText: String {
        let count = displayedChannels(from: store?.items ?? []).count
        return horizontalSizeClass == .regular ? "\(count) channels" : "\(count)"
    }
    #endif

    #if os(tvOS)
    private func sortCaptionMenu(count: Int) -> some View {
        Menu {
            sortPickerContent
        } label: {
            // The same capsule chip PlaylistsView's sort caption is.
            Text(sortCaptionText(count: count))
                .tvControlChip(palette)
        }
        .pleviSelectableStyle()
    }

    private func sortCaptionText(count: Int) -> String {
        let noun = "channel" + (count == 1 ? "" : "s")
        let order = activityFilter == .recentlyActive ? "Recent" : (nameSortOrder == .asc ? "A–Z" : "Z–A")
        return "\(count) \(noun) · \(order)"
    }
    #endif

    // MARK: - Client-side filter/sort

    /// The view of `store.items` this screen actually renders.
    private func displayedChannels(from items: [Channel]) -> [Channel] {
        switch activityFilter {
        case .recentlyActive:
            return items
                .compactMap { channel in Self.lastRefreshDate(for: channel).map { (channel, $0) } }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .all, .subscribed:
            return items.sorted { lhs, rhs in
                let order = (lhs.channelName ?? "").localizedStandardCompare(rhs.channelName ?? "")
                return nameSortOrder == .asc ? order == .orderedAscending : order == .orderedDescending
            }
        }
    }

    private static func lastRefreshDate(for channel: Channel) -> Date? {
        guard let raw = channel.channelLastRefresh else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    // MARK: - Grid / list

    @ViewBuilder
    private func grid(store: ChannelsStore, channels: [Channel]) -> some View {
        #if os(tvOS)
        gridBody(store: store, channels: channels)
        #else
        switch appSettings.channelsViewStyle {
        case .grid:
            gridBody(store: store, channels: channels)
        case .list:
            listBody(store: store, channels: channels)
        }
        #endif

        if store.isLoadingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        if let error = store.pageError {
            Text(error.errorDescription ?? "Couldn't load more channels.")
                .font(.footnote)
                .foregroundStyle(.red)
                .pleviRootHorizontalInset(horizontalInset)
        }
    }

    private func gridBody(store: ChannelsStore, channels: [Channel]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
            ForEach(channels) { channel in
                Button {
                    navigate(.channel(channel.id))
                } label: {
                    ChannelCard(channel: channel)
                }
                .pleviSelectableStyle()
                #if os(tvOS)
                .focused($focusedChannel, equals: channel.id)
                #endif
                .pinToHomeContextMenu(.channel(channel))
                .task {
                    await store.loadNextPageIfNeeded(currentItem: channel)
                }
            }
        }
        .pleviRootHorizontalInset(horizontalInset)
    }

    #if os(iOS)
    /// Unlike the grid (one card per cell), the list sits "inside a single
    /// card" — same idiom `PlaylistDetailView`'s entry list already uses —
    /// rather than each row carrying its own background.
    private func listBody(store: ChannelsStore, channels: [Channel]) -> some View {
        VStack(spacing: 0) {
            ForEach(channels) { channel in
                Button {
                    navigate(.channel(channel.id))
                } label: {
                    ChannelListRow(channel: channel)
                }
                .buttonStyle(.plain)
                .pinToHomeContextMenu(.channel(channel))
                .task {
                    await store.loadNextPageIfNeeded(currentItem: channel)
                }
                Divider()
            }
        }
        .padding(12)
        .pleviCard()
        .pleviRootHorizontalInset(horizontalInset)
    }
    #endif

    @ViewBuilder
    private func emptyState(store: ChannelsStore) -> some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Something went wrong.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await store.loadFirstPage(force: true) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        case .loaded:
            ContentUnavailableView(
                "No Channels",
                systemImage: "person.2.square.stack",
                description: Text("Nothing matches the current filter.")
            )
            .padding(.top, 40)
        }
    }

    // MARK: - Metrics

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.horizontal
        #elseif os(iOS)
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
        #endif
    }

    private var verticalInset: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.vertical
        #else
        PleviMetrics.screenHeaderTop
        #endif
    }

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        32
        #elseif os(iOS)
        horizontalSizeClass == .regular ? 20 : 16
        #endif
    }

    private var gridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            // Fixed 6-up, not `.adaptive` — this task's own spec: "iPad
            // 6-up / iPhone 3-up / tvOS 6-up."
            Array(repeating: GridItem(.flexible(), spacing: 20), count: 6)
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        }
        #endif
    }
}

/// Local, non-persisted filter over the already-loaded channel list — see
/// this file's own doc comment for why this isn't an `AppSettings` field.
private enum ChannelActivityFilter: Hashable {
    case all
    case subscribed
    case recentlyActive
}

#Preview {
    NavigationStack {
        ChannelsView(navigate: { _ in })
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(PinnedItems(scope: "", cloud: nil))
}
