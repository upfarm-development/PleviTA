// Segmented filter All / Regular / Custom (playlist_type).

import SwiftUI
import PleviCore

struct PlaylistsView: View {
    var navigate: (Route) -> Void
    var isActive: Bool = true

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var store: PlaylistsStore?
    #if os(tvOS)
    /// The playlist holding focus, so the first one can be made the page's default focus.
    @FocusState private var focusedPlaylist: Playlist.ID?
    @Environment(NavigationModel.self) private var navigation
    /// When the sidebar last asked this page to take focus, if it has not been able to yet.
    @State private var entryRequestedAt: Date?
    #endif

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        if isActive {
            mainContent
                #if os(iOS)
                // Headline and these controls share one line as
                // `screenHeader` in the content below, per the live request
                // — so no navigation bar here at all.
                .toolbar(.hidden, for: .navigationBar)
                #endif
        } else {
            mainContent
        }
    }

    #if os(iOS)
    #if os(iOS)
    /// Headline, count and the view/sort controls on one line.
    private func screenHeader(store: PlaylistsStore) -> some View {
        @Bindable var appSettings = appSettings
        return HStack(spacing: 12) {
            Text("Playlists")
                .pleviScreenTitle()
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            if let total = store.paginate?.totalHits {
                Text(playlistCountLabel(total))
                    .pleviMono()
                    .foregroundStyle(palette.secondary)
            }
            // Alongside the other header controls rather than out on its own at the left.
            #if os(iOS)
            OfflineDownloadsButton()
                .modifier(HeaderControlChip(palette: palette))
            #endif
            ViewStyleToggleButton(viewStyle: $appSettings.playlistsViewStyle)
                .modifier(HeaderControlChip(palette: palette))
            SortMenuButton(field: $appSettings.playlistsSortField, order: $appSettings.playlistsSortOrder, fieldTitle: \.title)
                .modifier(HeaderControlChip(palette: palette))
        }
    }
    #endif

    private func playlistCountLabel(_ total: Int) -> String {
        horizontalSizeClass == .regular ? "\(total) playlists" : "\(total)"
    }
    #endif

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
        #if os(iOS)
        .navigationTitle("Playlists")
        #endif
        .task {
            if store == nil, let client = authStore.client {
                store = PlaylistsStore(client: client, appSettings: appSettings)
            }
            await store?.loadFirstPage()
        }
        .task(id: appSettings.playlistsSubscribedOnly) {
            await store?.loadFirstPage()
        }
        .task(id: store?.typeFilter) {
            await store?.loadFirstPage()
        }
        // Sort field/order is a purely client-side re-sort of what's already loaded — `resort()` never hits the network, unlike the two `.task`s above.
        .task(id: sortKey) {
            store?.resort()
        }
    }

    private var sortKey: String {
        "\(appSettings.playlistsSortField.rawValue)|\(appSettings.playlistsSortOrder.rawValue)"
    }

    @ViewBuilder
    private func content(store: PlaylistsStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PleviMetrics.screenHeaderToControls) {
                #if os(iOS)
                screenHeader(store: store)
                    .pleviRootHorizontalInset(contentHorizontalPadding)
                #endif
                filterRow(store: store)

                if store.items.isEmpty {
                    emptyState(store: store)
                } else {
                    grid(store: store)
                }
            }
            .padding(.vertical, contentVerticalPadding)
        }
        .background(palette.canvas.ignoresSafeArea())
        #if os(iOS)
        .refreshable {
            await store.refresh()
        }
        #endif
        #if os(tvOS)
        // Entering the page puts focus on the first playlist, as Home does on its first video,
        // rather than on the filter row above the grid. At the default priority this only decides
        // when nothing else does, so returning from a pushed page still restores the card you left.
        .defaultFocus($focusedPlaylist, store.items.first?.id)
        // Select on the menu hands focus to the page: put it on the first playlist. A first visit
        // has no playlists yet, so the request waits (briefly) for them.
        .onChange(of: navigation.pageEntryRequest) { _, _ in
            guard isActive else { return }
            entryRequestedAt = Date()
            focusFirstPlaylist(store)
        }
        .onChange(of: store.items.first?.id) { _, _ in
            if entryRequestedAt != nil { focusFirstPlaylist(store) }
        }
        .scrollClipDisabled()
        #endif
    }

    #if os(tvOS)
    private func focusFirstPlaylist(_ store: PlaylistsStore) {
        guard let requested = entryRequestedAt else { return }
        if Date().timeIntervalSince(requested) > 5 {
            entryRequestedAt = nil
            return
        }
        guard let id = store.items.first?.id else { return }
        entryRequestedAt = nil
        // A beat after the sidebar lets go, so the focus engine is not mid-update.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            focusedPlaylist = id
        }
    }
    #endif

    // MARK: - Filter row (type chips + Subscribed)

    @ViewBuilder
    private func filterRow(store: PlaylistsStore) -> some View {
        #if os(tvOS)
        tvFilterRow(store: store)
            .pleviRootHorizontalInset(contentHorizontalPadding)
        #else
        // Four non-shrinking controls (three type chips + Subscribed) don't reliably fit one row at every width/Dynamic Type size.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                typeChips(store: store)
                Spacer(minLength: 12)
                subscribedControl
            }
        }
        // 12, not 14: `ChannelsView.chipsControlCard` is the card this one is meant to look identical to, and it pads by 12.
        .padding(12)
        .pleviCard()
        .pleviRootHorizontalInset(contentHorizontalPadding)
        #endif
    }

    private func typeChips(store: PlaylistsStore) -> some View {
        HStack(spacing: 12) {
            filterCapsule(title: "All", isSelected: store.typeFilter == nil) {
                store.typeFilter = nil
            }
            filterCapsule(title: "Regular", isSelected: store.typeFilter == .regular) {
                store.typeFilter = .regular
            }
            filterCapsule(title: "Custom", isSelected: store.typeFilter == .custom) {
                store.typeFilter = .custom
            }
        }
    }

    @ViewBuilder
    private var subscribedControl: some View {
        #if os(iOS)
        @Bindable var appSettings = appSettings
        if horizontalSizeClass == .regular {
            Toggle(isOn: $appSettings.playlistsSubscribedOnly) {
                Text("Subscribed only")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            .fixedSize()
        } else {
            subscribedChip(isOn: $appSettings.playlistsSubscribedOnly)
        }
        #endif
    }

    #if os(iOS)
    private func subscribedChip(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .foregroundStyle(isOn.wrappedValue ? Color.white : palette.secondary)
                .background(
                    Circle().fill(isOn.wrappedValue ? palette.accent : palette.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Subscribed only")
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
    #endif

    // MARK: - tvOS filter row (chips + mono sort/count caption)

    #if os(tvOS)
    @ViewBuilder
    private func tvFilterRow(store: PlaylistsStore) -> some View {
        @Bindable var appSettings = appSettings
        HStack(spacing: 16) {
            typeChips(store: store)
            filterCapsule(title: "Subscribed", isSelected: appSettings.playlistsSubscribedOnly) {
                appSettings.playlistsSubscribedOnly.toggle()
            }

            Spacer(minLength: 16)

            tvSortMenu(store: store)
        }
    }

    @ViewBuilder
    private func tvSortMenu(store: PlaylistsStore) -> some View {
        @Bindable var appSettings = appSettings
        Menu {
            Picker("Sort By", selection: $appSettings.playlistsSortField) {
                ForEach(PlaylistsSortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            Picker("Order", selection: $appSettings.playlistsSortOrder) {
                Label("Ascending", systemImage: "arrow.up").tag(HomeSortOrder.asc)
                Label("Descending", systemImage: "arrow.down").tag(HomeSortOrder.desc)
            }
        } label: {
            Text(tvSortCaption(store: store))
                .tvControlChip(palette)
        }
        .pleviSelectableStyle()
    }

    private func tvSortCaption(store: PlaylistsStore) -> String {
        // Falls back to how many are loaded so far if the server total isn't known yet (before the first page resolves).
        let count = store.paginate?.totalHits ?? store.items.count
        let direction = appSettings.playlistsSortOrder == .asc ? "A–Z" : "Z–A"
        return "\(count) playlist\(count == 1 ? "" : "s") · \(appSettings.playlistsSortField.title) \(direction)"
    }
    #endif

    private func filterCapsule(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? palette.accent : palette.secondary.opacity(0.15)))
                .foregroundStyle(isSelected ? Color.white : palette.ink)
                .tvFocusRing(cornerRadius: 18)
        }
        .pleviSelectableStyle()
    }

    // MARK: - Grid

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        // A focused card grows 10% downward from its top, and a card is about 340pt tall: the
        // spacing has to be more than that 34pt or the next row's cover paints over the focused
        // card's channel line.
        52
        #else
        24
        #endif
    }

    @ViewBuilder
    private func grid(store: PlaylistsStore) -> some View {
        switch appSettings.playlistsViewStyle {
        case .grid:
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridRowSpacing) {
                ForEach(store.items) { playlist in
                    Button {
                        navigate(.playlist(playlist.id))
                    } label: {
                        PlaylistCard(playlist: playlist)
                    }
                    .pleviSelectableStyle()
                    #if os(tvOS)
                    .focused($focusedPlaylist, equals: playlist.id)
                    #endif
                    .pinToHomeContextMenu(.playlist(playlist))
                    .task {
                        await store.loadNextPageIfNeeded(currentItem: playlist)
                    }
                }
            }
            .pleviRootHorizontalInset(contentHorizontalPadding)
        case .list:
            LazyVStack(spacing: 0) {
                ForEach(store.items) { playlist in
                    Button {
                        navigate(.playlist(playlist.id))
                    } label: {
                        PlaylistListRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .pinToHomeContextMenu(.playlist(playlist))
                    .task {
                        await store.loadNextPageIfNeeded(currentItem: playlist)
                    }
                    Divider()
                }
            }
            .pleviRootHorizontalInset(contentHorizontalPadding)
        }

        if store.isLoadingNextPage {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        if let error = store.pageError {
            Text(error.errorDescription ?? "Couldn't load more playlists.")
                .font(.footnote)
                .foregroundStyle(.red)
                .pleviRootHorizontalInset(contentHorizontalPadding)
        }
    }

    @ViewBuilder
    private func emptyState(store: PlaylistsStore) -> some View {
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
                "No Playlists",
                systemImage: "list.and.film",
                description: Text("Nothing matches the current filter.")
            )
            .padding(.top, 40)
        }
    }

    // MARK: - Metrics

    private var contentHorizontalPadding: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.horizontal
        #elseif os(iOS)
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
        #endif
    }

    private var contentVerticalPadding: CGFloat {
        #if os(tvOS)
        PleviMetrics.insetTV.vertical
        #else
        PleviMetrics.screenHeaderTop
        #endif
    }

    private var gridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 4)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        PlaylistsView(navigate: { _ in })
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(PinnedItems(scope: "", cloud: nil))
}
