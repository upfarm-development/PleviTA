// Debounce 300 ms, minimum 2 characters.

import SwiftUI
import PleviCore

struct SearchView: View {
    var navigate: (Route) -> Void
    /// Whether this section is the one currently shown.
    var isActive: Bool = true

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var store: SearchStore?

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    #if os(iOS)
    @Binding var queryText: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationModel.self) private var navigation
    /// iPad: the search box takes focus, and so the keyboard, when the Search tab is shown.
    @FocusState private var isSearchFieldFocused: Bool
    #else
    // tvOS has no shared `TabView`-level search field to plug into, and its
    // own remote-driven search affordance manages its own presentation/
    // focus — unchanged from before the iPad fix above.
    @State private var queryText: String = ""
    #endif

    var body: some View {
        #if os(iOS)
        mainContent
        #else
        if isActive {
            mainContent
                .searchable(text: $queryText, prompt: "Search videos, channels, playlists")
        } else {
            mainContent
        }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if horizontalSizeClass == .regular {
                customSearchBar
            }
            #endif

            Group {
                if let store {
                    content(store: store)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(iOS)
        .navigationTitle("Search")
        #endif
        .task {
            if store == nil, let client = authStore.client {
                store = SearchStore(client: client)
            }
        }
        .task(id: queryText) {
            store?.updateQuery(queryText)
        }
        #if os(iOS)
        // Opening the Search tab on iPad starts typing straight away.
        .onAppear { focusSearchFieldOnIPad() }
        .onChange(of: navigation.selectedSection) { _, section in
            if section == .search { focusSearchFieldOnIPad() }
        }
        #endif
    }

    #if os(iOS)
    private func focusSearchFieldOnIPad() {
        guard horizontalSizeClass == .regular else { return }
        // Asked for at once. Focus requested before the field is on screen is dropped, so it is
        // asked again shortly after, but only if the first request did not take.
        isSearchFieldFocused = true
        Task { @MainActor in
            for delay in [80, 120, 200] {
                try? await Task.sleep(for: .milliseconds(delay))
                if isSearchFieldFocused { return }
                isSearchFieldFocused = true
            }
        }
    }

    /// iPad's own search field, in place of the system one — see this file's own top doc comment for why.
    private var customSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondary)
            TextField("Search videos, channels, playlists", text: $queryText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
            if !queryText.isEmpty {
                Button {
                    queryText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.secondary.opacity(0.12), in: Capsule())
        .padding(.horizontal, PleviMetrics.insetPad)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    #endif

    @ViewBuilder
    private func content(store: SearchStore) -> some View {
        switch store.loadState {
        case .idle:
            hintState
        case .loading:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            errorState(error: error, store: store)
        case .loaded(let results):
            if results.isEmpty {
                ContentUnavailableView.search(text: store.lastSearchedQuery)
            } else {
                resultsList(results: results, store: store)
            }
        }
    }

    // MARK: Hint (pre-typing) state

    private var hintState: some View {
        ContentUnavailableView("Search Tube Archivist", systemImage: "magnifyingglass")
    }

    // MARK: Error state

    private func errorState(error: TAError, store: SearchStore) -> some View {
        VStack(spacing: 12) {
            Text(error.errorDescription ?? "Something went wrong.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await store.retry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Grouped results

    @ViewBuilder
    private func resultsList(results: SearchResults, store: SearchStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(appSettings.searchResultsOrder) { section in
                    switch section {
                    case .video:
                        videosSection(videos: results.videoResults, store: store)
                    case .channel:
                        channelsSection(channels: results.channelResults)
                    case .playlist:
                        playlistsSection(playlists: results.playlistResults)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func videosSection(videos: [Video]?, store: SearchStore) -> some View {
        if let videos, !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Videos")
                    .font(.title3.bold())
                    .pleviRootHorizontalInset()

                LazyVGrid(columns: videoGridColumns, alignment: .leading, spacing: 20) {
                    ForEach(videos) { video in
                        NavigationLink(value: Route.video(video.id)) {
                            VideoRow(
                                video: video,
                                layout: .card,
                                actions: videoActions(list: store)
                            )
                        }
                        .pleviSelectableStyle()
                        .videoActionsContextMenu(video: video, actions: videoActions(list: store))
                    }
                }
                .pleviRootHorizontalInset()
            }
        }
    }

    @ViewBuilder
    private func channelsSection(channels: [Channel]?) -> some View {
        if let channels, !channels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Channels")
                    .font(.title3.bold())
                    .pleviRootHorizontalInset()

                LazyVGrid(columns: channelGridColumns, spacing: 24) {
                    ForEach(channels) { channel in
                        Button {
                            navigate(.channel(channel.id))
                        } label: {
                            ChannelCard(channel: channel)
                        }
                        .pleviSelectableStyle()
                        .pinToHomeContextMenu(.channel(channel))
                    }
                }
                .pleviRootHorizontalInset()
            }
        }
    }

    @ViewBuilder
    private func playlistsSection(playlists: [Playlist]?) -> some View {
        if let playlists, !playlists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Playlists")
                    .font(.title3.bold())
                    .pleviRootHorizontalInset()

                LazyVGrid(columns: playlistGridColumns, alignment: .leading, spacing: 24) {
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
                .pleviRootHorizontalInset()
            }
        }
    }

    private func videoActions(list: any VideoMutating) -> VideoActions {
        VideoActions(list: list, coordinator: videoActionsCoordinator, navigate: navigate)
    }

    // MARK: Grid columns (mirror HomeView/ChannelsView/PlaylistsView)

    private var videoGridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 5)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 20)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        #endif
    }

    private var channelGridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 6)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        }
        #endif
    }

    private var playlistGridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 32), count: 5)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 20)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
        }
        #endif
    }
}

#if os(iOS)
#Preview {
    @Previewable @State var queryText = ""
    NavigationStack {
        SearchView(navigate: { _ in }, queryText: $queryText)
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(VideoActionsCoordinator())
    .environment(PinnedItems(scope: "", cloud: nil))
}
#else
#Preview {
    NavigationStack {
        SearchView(navigate: { _ in })
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
    .environment(VideoActionsCoordinator())
    .environment(PinnedItems(scope: "", cloud: nil))
}
#endif
