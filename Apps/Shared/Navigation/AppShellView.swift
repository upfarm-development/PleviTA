
import SwiftUI
import PleviCore

struct AppShellView: View {
    /// Which tab is selected and how deep each one is — held outside this
    /// view on purpose, see NavigationModel.swift. Both platforms read it.
    @Environment(NavigationModel.self) private var navigation
    /// Both platforms see this — the one attachment point per platform is below, on each
    /// body's own `TabView` (see VideoActions.swift's own doc comment on why one place).
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        if horizontalSizeClass == .regular {
            tabView(searchRole: nil)
        } else {
            tabView(searchRole: .search)
                .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search videos, channels, playlists")
                .searchFocused($isSearchFieldFocused)
                .onChange(of: navigation.selectedSection, initial: true) { _, newValue in
                    if newValue == .search {
                        isSearchPresented = true
                    }
                }
                .onChange(of: isSearchPresented, initial: true) { _, newValue in
                    if newValue {
                        isSearchFieldFocused = true
                    }
                }
        }
    }

    private func tabView(searchRole: TabRole?) -> some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.selectedSection) {
            Tab(AppSection.home.title, systemImage: AppSection.home.systemImage, value: AppSection.home) {
                SectionStack(section: .home, path: navigation.binding(for: .home))
            }
            Tab(AppSection.channels.title, systemImage: AppSection.channels.systemImage, value: AppSection.channels) {
                SectionStack(section: .channels, path: navigation.binding(for: .channels))
            }
            Tab(AppSection.playlists.title, systemImage: AppSection.playlists.systemImage, value: AppSection.playlists) {
                SectionStack(section: .playlists, path: navigation.binding(for: .playlists))
            }
            Tab(AppSection.settings.title, systemImage: AppSection.settings.systemImage, value: AppSection.settings) {
                SectionStack(section: .settings, path: navigation.binding(for: .settings))
            }
            if searchRole == nil {
                // iPad: Search stays a tab, shown as just the magnifying glass with no text.
                Tab(value: AppSection.search) {
                    SectionStack(section: .search, searchText: $searchText, path: navigation.binding(for: .search))
                } label: {
                    Image(systemName: AppSection.search.systemImage)
                        .accessibilityLabel(AppSection.search.title)
                }
            } else {
                Tab(AppSection.search.title, systemImage: AppSection.search.systemImage, value: AppSection.search, role: searchRole) {
                    SectionStack(section: .search, searchText: $searchText, path: navigation.binding(for: .search))
                }
            }
        }
        .videoActionsPresentations(videoActionsCoordinator)
    }
    #elseif os(tvOS)
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    /// Which sidebar row has focus; `nil` when focus is on the page.
    @FocusState private var sidebarFocus: TVSidebarTarget?
    @State private var visitedSections: Set<AppSection> = [.home]
    /// Which item focus entered the sidebar from — see `TVSidebarFocusMemory`. Lives as long as
    /// the shell, so it is already watching when focus first crosses into the sidebar.
    @State private var sidebarFocusMemory = TVSidebarFocusMemory()

    private var isAtSectionRoot: Bool {
        navigation.path(for: navigation.selectedSection).isEmpty
    }

    var body: some View {
        @Bindable var navigation = navigation
        return ZStack(alignment: .leading) {
            ForEach(AppSection.allCases) { section in
                if visitedSections.contains(section) {
                    let isSelected = section == navigation.selectedSection
                    SectionStack(
                        section: section,
                        isActive: isSelected,
                        externalRoute: section == .home ? deepLinkRouter.pendingRoute : nil,
                        onConsumeExternalRoute: { deepLinkRouter.consumePendingRoute() },
                        path: navigation.binding(for: section)
                    )
                    // Every visited section stays mounted so switching back to it keeps its scroll position and pushed path — see this property's own doc comment.
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
                    .disabled(!isSelected)
                }
            }
            // Just right of the rail: pressing Right out of the sidebar meets this first
            // and is sent back to the item focus entered the sidebar from, instead of the top of
            // the page — see `TVSidebarFocusReturn`.
            if sidebarFocus != nil {
                TVSidebarFocusReturn(memory: sidebarFocusMemory)
                    .frame(width: 40)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 38 + PleviMetrics.tvSidebarRailWidth)
                    .accessibilityHidden(true)
            }
            TVSidebar(
                selection: $navigation.selectedSection,
                focus: $sidebarFocus,
                onReselect: { navigation.binding(for: $0).wrappedValue = [] }
            )
            .padding(.leading, 38)
        }
        .ignoresSafeArea()
        .videoActionsPresentations(videoActionsCoordinator)
        .onChange(of: navigation.selectedSection, initial: true) { _, newValue in
            visitedSections.insert(newValue)
        }
        // A Menu press with nothing focused (focus is returning to a button after a menu closed)
        // goes back a page instead of leaving the app; see `TVMenuWhenNothingFocused`.
        .background {
            TVMenuWhenNothingFocused {
                let section = navigation.selectedSection
                if navigation.path(for: section).isEmpty {
                    sidebarFocus = .section(section)
                } else {
                    var path = navigation.path(for: section)
                    path.removeLast()
                    navigation.binding(for: section).wrappedValue = path
                }
            }
        }
        .onExitCommand(perform: isAtSectionRoot && sidebarFocus == nil ? { sidebarFocus = .section(navigation.selectedSection) } : nil)
        .task(id: deepLinkRouter.pendingRoute) {
            guard deepLinkRouter.pendingRoute != nil else { return }
            navigation.selectedSection = .home
        }
    }
    #endif
}

/// One section's own `NavigationStack` + `Route` destinations.
private struct SectionStack: View {
    let section: AppSection
    /// Whether this section is the one currently shown.
    var isActive: Bool = true
    #if os(iOS)
    /// The search query text, owned by `AppShellView` and attached to its `TabView` itself — see that property's own doc comment for why.
    var searchText: Binding<String> = .constant("")
    #endif
    var externalRoute: Route? = nil
    var onConsumeExternalRoute: () -> Void = {}
    /// Owned by `NavigationModel`, not by this view — see that file's own
    /// doc comment. As `@State` here it was destroyed every time the
    /// size-class conditional in `AppShellView.body` swapped branches.
    @Binding var path: [Route]
    @State private var homeReturnToken = 0

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: Route.self) { route in
                    RouteDestinationView(route: route, navigate: { path.append($0) })
                }
        }
        .onChange(of: path) { oldValue, newValue in
            if section == .home, !oldValue.isEmpty, newValue.isEmpty {
                homeReturnToken += 1
            }
        }
        // `.task(id:)`, not `.onChange`, for the same reason as `AppShellView`'s own tvOS `body`.
        .task(id: externalRoute) {
            guard let externalRoute else { return }
            path.append(externalRoute)
            onConsumeExternalRoute()
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch section {
        case .home:
            HomeView(navigate: { path.append($0) }, refreshToken: homeReturnToken, isActive: isActive)
        case .channels:
            ChannelsView(navigate: { path.append($0) }, isActive: isActive)
        case .playlists:
            PlaylistsView(navigate: { path.append($0) }, isActive: isActive)
        case .search:
            #if os(iOS)
            SearchView(navigate: { path.append($0) }, isActive: isActive, queryText: searchText)
            #else
            SearchView(navigate: { path.append($0) }, isActive: isActive)
            #endif
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    AppShellView()
        .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
        .environment(AppSettings())
        // tvOS's branch reads this via `@Environment(DeepLinkRouter.self)`, which fatal-errors if nothing ever provided one.
        .environment(DeepLinkRouter())
}
