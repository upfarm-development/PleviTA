
import SwiftUI
import PleviCore
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @State private var isConfirmingSignOut = false
    @Environment(PlaybackHistory.self) private var playbackHistory
    /// What the artwork cache holds right now, refreshed when the screen appears and after a change.
    @State private var artworkCacheBytes = 0
    @State private var isConfirmingClearArtwork = false
    #if os(iOS)
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @State private var isConfirmingRemoveWatched = false
    @State private var isRemovingWatched = false
    /// Bytes held by shelves belonging to some other server — see `storageSection`.
    @State private var foreignBytes = 0
    @State private var storageNotice: String?
    @AppStorage(PlaybackLog.enabledKey) private var playbackLogging = true
    @State private var playbackLogSize: Int64 = 0
    @State private var isConfirmingClearLog = false
    #endif

    @State private var localServerURLText = ""
    @State private var remoteServerURLText = ""
    @State private var connectionMode: ConnectionMode = .automatic
    #if os(iOS)
    @State private var showSSOSheet = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        #if os(iOS)
        // Same in-content headline the other root sections draw, rather than a system large title.
        VStack(alignment: .leading, spacing: PleviMetrics.screenHeaderToControls) {
            Text("Settings")
                .pleviScreenTitle()
                .foregroundStyle(palette.ink)
                .padding(.horizontal, headerHorizontalInset)
                .padding(.top, PleviMetrics.screenHeaderTop)
            settingsForm
                .contentMargins(.top, 0, for: .scrollContent)
        }
        .background(palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #else
        settingsForm
            .padding(.leading, PleviMetrics.insetTVLeadingRoot - PleviMetrics.insetTV.horizontal)
        #endif
    }

    #if os(iOS)
    /// Matches the other root screens' own screen-edge inset so the five
    /// headlines line up horizontally as well as vertically.
    private var headerHorizontalInset: CGFloat {
        horizontalSizeClass == .regular ? PleviMetrics.insetPad : PleviMetrics.insetPhone
    }
    #endif

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            // One row per group, each pushing to its own screen, rather than every setting stacked on one page.
            #if os(iOS)
            themeSection
            #endif
            Section {
                groupRow("Server", systemImage: "server.rack") { serverSection }
                groupRow("Browsing", systemImage: "square.grid.2x2") { browsingSection }
                groupRow("Search", systemImage: "magnifyingglass") { searchSection }
                groupRow("Playback", systemImage: "play.circle") { playbackSection }
                groupRow("Integrations", systemImage: "puzzlepiece.extension") { integrationsSection }
                #if os(iOS)
                groupRow("Storage", systemImage: "internaldrive") { storageSection }
                groupRow("Diagnostics", systemImage: "waveform.path.ecg") { diagnosticsSection }
                #else
                groupRow("Storage", systemImage: "internaldrive") { artworkCacheSection }
                #endif
                groupRow("About", systemImage: "info.circle") { aboutSection }
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .background(palette.canvas.ignoresSafeArea())
        #endif
        .task {
            localServerURLText = authStore.localServerURL()?.absoluteString ?? ""
            remoteServerURLText = authStore.remoteServerURL()?.absoluteString ?? ""
            connectionMode = authStore.connectionMode()
        }
        #if os(iOS)
        .sheet(isPresented: $showSSOSheet) {
            if let target = ssoTargetURL {
                SSOLoginSheet(serverURL: target, probe: { await APIGateProbe()($0) }) {
                    // Getting through the gate can change whether the
                    // address is reachable at all, so re-resolve rather than
                    // waiting for the next network change to notice.
                    Task { await authStore.reresolveServerAddressIfNeeded(force: true) }
                }
            }
        }
        #endif
    }

    /// One root row and the screen behind it.
    private func groupRow<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationLink {
            SettingsGroupScreen(title: title, palette: palette, content: content)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    /// Settings → Storage → Artwork cache: how much of the disk the on-device copies of thumbnails,
    /// avatars and channel art may use, and a way to clear them. See `ArtworkDiskCache`.
    private var artworkCacheSection: some View {
        @Bindable var appSettings = appSettings
        return Section {
            LabeledContent("Artwork cache", value: PleviFormatting.byteCount(artworkCacheBytes))
            SettingsPicker("Maximum size", selection: $appSettings.artworkCacheLimitMB) {
                ForEach(AppSettings.artworkCacheLimitChoicesMB, id: \.self) { megabytes in
                    Text(megabytes >= 1000 ? "\(megabytes / 1000) GB" : "\(megabytes) MB").tag(megabytes)
                }
            }
            Button("Clear Artwork Cache", role: .destructive) {
                isConfirmingClearArtwork = true
            }
            .disabled(artworkCacheBytes == 0)
            .confirmationDialog("Clear the artwork cache?", isPresented: $isConfirmingClearArtwork, titleVisibility: .visible) {
                Button("Clear Artwork Cache", role: .destructive) {
                    Task {
                        await authStore.artworkCache?.clear()
                        await authStore.imageLoader?.clearCache()
                        await refreshArtworkCacheBytes()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Thumbnails and channel art are fetched again as you browse. Saved videos are not affected.")
            }
        }
        .task { await refreshArtworkCacheBytes() }
        .onChange(of: appSettings.artworkCacheLimitMB) { _, megabytes in
            Task {
                await authStore.artworkCache?.setLimit(bytes: megabytes * 1_000_000)
                await refreshArtworkCacheBytes()
            }
        }
    }

    private func refreshArtworkCacheBytes() async {
        artworkCacheBytes = await authStore.artworkCache?.usedBytes ?? 0
    }

    @ViewBuilder
    private var serverSection: some View {
        Section {
            if case .loggedIn(let session) = authStore.state {
                LabeledContent("Server", value: session.serverURL.absoluteString)
                LabeledContent("Signed in as", value: session.username ?? "Unknown user")
                LabeledContent("Tube Archivist version", value: session.version ?? "Unknown")
            }

            TextField("Local Server URL", text: $localServerURLText)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit(commitLocalServerURL)
                .onChange(of: localServerURLText) { _, newValue in
                    if newValue.isEmpty { commitLocalServerURL() }
                }

            TextField("Remote Server URL", text: $remoteServerURLText)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit(commitRemoteServerURL)
                .onChange(of: remoteServerURLText) { _, newValue in
                    if newValue.isEmpty { commitRemoteServerURL() }
                }

            SettingsPicker("Mode", selection: $connectionMode) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: connectionMode) { _, newMode in
                authStore.setConnectionMode(newMode)
                Task { await authStore.reresolveServerAddressIfNeeded(force: true) }
            }

            #if os(iOS)
            if let target = ssoTargetURL {
                Button {
                    showSSOSheet = true
                } label: {
                    Label("Sign in via browser", systemImage: "globe")
                }
                .accessibilityHint("Opens \(target.host ?? "the server") to sign in through its login page")
            }
            #endif

            if hasAnyConnectionAddress, case .loggedIn = authStore.state {
                LabeledContent("Connected via", value: connectionSourceLabel)
            }

            Button("Sign Out", role: .destructive) {
                isConfirmingSignOut = true
            }
            // On the button so the popover points at it — see `OfflineStorageBrowser`.
            .confirmationDialog(
                "Sign out of this server?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await authStore.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    #if os(iOS)
    /// The address the browser sign-in should open.
    private var ssoTargetURL: URL? {
        AuthStore.normalizedURL(from: remoteServerURLText)
            ?? AuthStore.normalizedURL(from: localServerURLText)
    }
    #endif

    private var hasAnyConnectionAddress: Bool {
        !localServerURLText.isEmpty || !remoteServerURLText.isEmpty
    }

    private var connectionSourceLabel: String {
        switch authStore.connectionSource {
        case .local: return "Local"
        case .remote: return "Remote"
        case .configured: return "Configured Server"
        }
    }

    private func commitLocalServerURL() {
        commitAddress(
            text: &localServerURLText,
            currentlyStored: authStore.localServerURL(),
            store: authStore.setLocalServerURL
        )
    }

    private func commitRemoteServerURL() {
        commitAddress(
            text: &remoteServerURLText,
            currentlyStored: authStore.remoteServerURL(),
            store: authStore.setRemoteServerURL
        )
    }

    /// Shared commit logic for both address fields: blank clears the stored address.
    private func commitAddress(text: inout String, currentlyStored: URL?, store: (URL?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard currentlyStored != nil else { return }
            store(nil)
        } else if let url = AuthStore.normalizedURL(from: trimmed) {
            guard url != currentlyStored else { return }
            store(url)
            text = url.absoluteString
        } else {
            text = currentlyStored?.absoluteString ?? ""
            return
        }
        Task { await authStore.reresolveServerAddressIfNeeded(force: true) }
    }

    @ViewBuilder
    private var browsingSection: some View {
        @Bindable var appSettings = appSettings
        Section {
            SettingsPicker("Sort Home by", selection: $appSettings.homeSortField) {
                Text("Date added").tag(HomeSortField.downloaded)
                Text("Date published").tag(HomeSortField.published)
            }
            SettingsPicker("Home order", selection: $appSettings.homeSortOrder) {
                Text("Newest first").tag(HomeSortOrder.desc)
                Text("Oldest first").tag(HomeSortOrder.asc)
            }
            SettingsPicker("Video type", selection: $appSettings.videoTypeFilter) {
                Text("All").tag(VideoTypeFilter?.none)
                Text("Videos").tag(VideoTypeFilter?.some(.videos))
                Text("Streams").tag(VideoTypeFilter?.some(.streams))
                Text("Shorts").tag(VideoTypeFilter?.some(.shorts))
            }
            Toggle("Hide watched videos", isOn: $appSettings.hideWatched)
            SettingsPicker("Sort playlists by", selection: $appSettings.playlistDetailSortField) {
                ForEach(PlaylistEntrySortField.allCases, id: \.self) { field in
                    Text(field.menuTitle).tag(field)
                }
            }
            SettingsPicker("Playlist order", selection: $appSettings.playlistDetailSortOrder) {
                Text("Ascending").tag(HomeSortOrder.asc)
                Text("Descending").tag(HomeSortOrder.desc)
            }
        }
    }

    #if os(iOS)
    private var searchSection: some View {
        Section {
            ForEach(appSettings.searchResultsOrder) { section in
                HStack {
                    Text(section.title)
                    Spacer(minLength: 12)
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                }
            }
            .onMove { indices, newOffset in
                var order = appSettings.searchResultsOrder
                order.move(fromOffsets: indices, toOffset: newOffset)
                appSettings.searchResultsOrder = order
            }
        }
        .environment(\.editMode, .constant(.active))
    }
    #else
    // tvOS has no drag gesture input at all, so this keeps the original
    // explicit up/down buttons — see this property's own doc comment above
    // for the iOS version's full story.
    private var searchSection: some View {
        Section {
            ForEach(Array(appSettings.searchResultsOrder.enumerated()), id: \.element) { index, section in
                HStack {
                    Text(section.title)
                    Spacer(minLength: 12)
                    Button {
                        moveSearchSection(from: index, to: index - 1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(section.title) up")

                    Button {
                        moveSearchSection(from: index, to: index + 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == appSettings.searchResultsOrder.count - 1)
                    .accessibilityLabel("Move \(section.title) down")
                }
                // Without this each row's whole background becomes one
                // tappable button in a Form, so either arrow would fire both.
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Search")
        }
    }

    private func moveSearchSection(from index: Int, to destination: Int) {
        var order = appSettings.searchResultsOrder
        guard order.indices.contains(index), order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        appSettings.searchResultsOrder = order
    }
    #endif

    /// Other services the app can use. One row per service, each opening its own screen of options.
    private var integrationsSection: some View {
        Section {
            NavigationLink {
                SettingsGroupScreen(title: "SponsorBlock", palette: palette) { sponsorBlockSection }
            } label: {
                LabeledContent("SponsorBlock", value: appSettings.sponsorBlockEnabled ? "On" : "Off")
            }
        }
    }

    /// The four kinds of segment SponsorBlock can skip. There is no master switch: it is on while
    /// any of them is.
    private var sponsorBlockSection: some View {
        Section {
            ForEach(SponsorBlockPolicy.userSelectableCategories, id: \.self) { category in
                Toggle(category.displayName, isOn: sponsorCategoryBinding(category))
            }
        }
    }

    /// A `Toggle` cannot bind to membership of a `Set`, so each category row gets its own binding whose setter reassigns the **whole** set.
    private func sponsorCategoryBinding(_ category: SponsorCategory) -> Binding<Bool> {
        Binding(
            get: { appSettings.sponsorBlockCategories.contains(category) },
            set: { isOn in
                var updated = appSettings.sponsorBlockCategories
                if isOn { updated.insert(category) } else { updated.remove(category) }
                appSettings.sponsorBlockCategories = updated
            }
        )
    }

    private var playbackSection: some View {
        @Bindable var appSettings = appSettings
        return Section {
            Toggle("Auto-play next video", isOn: $appSettings.autoPlayNext)
            SettingsPicker("Resuming videos", selection: $appSettings.resumeBehavior) {
                Text("Always Resume").tag(ResumeBehavior.alwaysResume)
                Text("Ask").tag(ResumeBehavior.ask)
            }
            Toggle("Skip watched videos", isOn: $appSettings.playlistNavSkipWatched)
            // Continue Watching's two settings, moved here from the old Home section at the user's request.
            SettingsPicker("Continue watching", selection: $appSettings.continueWatchingStyle) {
                Text("Carousel").tag(ContinueWatchingStyle.carousel)
                Text("List").tag(ContinueWatchingStyle.list)
            }
            Toggle("Recently played first", isOn: $appSettings.recentlyPlayedFirst)
            SettingsPicker("Compatibility player", selection: $appSettings.fallbackPlayerMode) {
                Text("Automatic").tag(FallbackPlayerMode.automatic)
                Text("Always").tag(FallbackPlayerMode.always)
                Text("Never").tag(FallbackPlayerMode.never)
            }
        }
    }

    #if os(iOS)
    private var storageSection: some View {
        @Bindable var appSettings = appSettings
        return Group {
            savedVideosSection
            artworkCacheSection
        }
    }

    /// The sentence shown after "Remove Watched". A video the server could not be asked about is
    /// said so, rather than counted as "not watched".
    private static func removeWatchedMessage(_ report: OfflineLibrary.RemoveWatchedReport) -> String {
        var parts: [String] = []
        if report.removed > 0 {
            parts.append("Removed \(report.removed) watched video\(report.removed == 1 ? "" : "s").")
        } else if report.unchecked == 0 {
            parts.append("Nothing to remove. No saved video is marked watched on the server.")
        }
        if report.unchecked > 0 {
            parts.append("Couldn't check \(report.unchecked) video\(report.unchecked == 1 ? "" : "s") because the server didn't answer.")
        }
        return parts.joined(separator: " ")
    }

    private var savedVideosSection: some View {
        @Bindable var appSettings = appSettings
        return Section {
            // Tappable rather than a plain figure: "Saved videos: 34" answers how much but
            // not what, and the only per-video removal before this was the "…" menu on a
            // video's own page, which means finding it first.
            NavigationLink {
                OfflineStorageBrowser()
            } label: {
                LabeledContent("Saved videos", value: "\(offlineLibrary.entries.count)")
            }
            .disabled(offlineLibrary.entries.isEmpty)
            LabeledContent("Total size", value: PleviFormatting.byteCount(offlineLibrary.totalBytesUsed))
            Toggle("Allow cellular downloads", isOn: $appSettings.allowCellularDownloads)
            Button(isRemovingWatched ? "Removing…" : "Remove Watched", role: .destructive) {
                isConfirmingRemoveWatched = true
            }
            .disabled(offlineLibrary.entries.isEmpty || isRemovingWatched)
            // On the button so the popover points at it — see `OfflineStorageBrowser`.
            .confirmationDialog(
                "Remove every watched download?",
                isPresented: $isConfirmingRemoveWatched,
                titleVisibility: .visible
            ) {
                Button("Remove Watched", role: .destructive) {
                    Task {
                        // The answer goes to `storageNotice`, whose alert sits on this same screen.
                        guard let client = authStore.client else {
                            storageNotice = "Couldn't reach the server, so nothing was removed."
                            return
                        }
                        isRemovingWatched = true
                        let report = await offlineLibrary.removeWatchedReport(client: client)
                        isRemovingWatched = false
                        storageNotice = Self.removeWatchedMessage(report)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Checks each saved video against Tube Archivist and removes the ones it currently shows as watched. Requires a connection to the server.")
            }

            if foreignBytes > 0 {
                LabeledContent("Saved for another server", value: PleviFormatting.byteCount(foreignBytes))
                Button("Remove Videos for Other Servers", role: .destructive) {
                    Task {
                        let reclaimed = await offlineLibrary.removeForeignShelves()
                        foreignBytes = await offlineLibrary.foreignBytesUsed()
                        storageNotice = "Removed \(PleviFormatting.byteCount(reclaimed))."
                    }
                }
            }
        }
        .task {
            foreignBytes = await offlineLibrary.foreignBytesUsed()
        }
        .alert(
            "Storage",
            isPresented: Binding(
                get: { storageNotice != nil },
                set: { if !$0 { storageNotice = nil } }
            ),
            presenting: storageNotice
        ) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice)
        }
    }
    #endif

    #if os(iOS)
    /// iOS/iPadOS only, at the user's own request — tvOS keeps following the
    /// system appearance and never shows this control.
    private var themeSection: some View {
        @Bindable var appSettings = appSettings
        // No header: one control, belonging to the whole app rather than to a category, at the
        // top of the list where an app-wide appearance choice is conventionally found.
        return Section {
            Picker("Theme", selection: $appSettings.appTheme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
        }
    }
    #endif

    #if os(iOS)
    private var diagnosticsSection: some View {
        Section {
            Toggle("Detailed playback logging", isOn: $playbackLogging)
            LabeledContent("Log size", value: ByteCountFormatter.string(fromByteCount: playbackLogSize, countStyle: .file))
                .onAppear { playbackLogSize = PlaybackLog.shared.sizeOnDisk() }
            ShareLink(item: PlaybackLogExport(), preview: SharePreview("Plevi TA playback log")) {
                Label("Share playback log", systemImage: "square.and.arrow.up")
            }
            Button("Clear log", role: .destructive) {
                isConfirmingClearLog = true
            }
            // On the button so the popover points at it — see `OfflineStorageBrowser`.
            .confirmationDialog("Clear the playback log?", isPresented: $isConfirmingClearLog, titleVisibility: .visible) {
                Button("Clear Log", role: .destructive) {
                    PlaybackLog.shared.clear()
                    playbackLogSize = 0
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("App version", value: appVersionString)
            // Continue Watching's order is shared between your devices through iCloud. If two
            // devices show a different "server" code here they signed in with different addresses
            // and keep separate histories.
            LabeledContent("Continue Watching sync") {
                Text(playbackHistory.diagnosticsSummary)
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
            }
            Link("Tube Archivist documentation", destination: URL(string: "https://docs.tubearchivist.com")!)
            // VLCKit is LGPL 2.1 and is the one third-party binary this app ships (the compatibility player).
            Link("VLCKit — LGPL 2.1", destination: URL(string: "https://code.videolan.org/videolan/VLCKit/-/blob/master/COPYING")!)
        }
    }

    private var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// The pushed screen behind each settings group row.
private struct SettingsGroupScreen<Content: View>: View {
    let title: String
    let palette: PleviPalette
    @ViewBuilder var content: () -> Content
    #if os(tvOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        Form { content() }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .background(palette.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            #else
            .pleviRootHorizontalInset()
            .pickerStyle(.menu)
            // Menu goes back to the settings list. This screen is opened with a plain
            // `NavigationLink` that adds nothing to the section's path, so the shell sees a section
            // root and sends Menu to the sidebar instead.
            .onExitCommand { dismiss() }
            #endif
    }
}

/// A settings dropdown that keeps its name on Apple TV.
private struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content
    }

    var body: some View {
        #if os(tvOS)
        LabeledContent(title) {
            Picker(title, selection: $selection, content: content)
                .labelsHidden()
        }
        #else
        Picker(title, selection: $selection, content: content)
        #endif
    }
}

#if os(iOS)
/// The log as a file handed to the share sheet. Built when the user actually shares, not when the
/// row is drawn, so it includes everything up to that moment.
private struct PlaybackLogExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            guard let url = PlaybackLog.shared.exportCombined() else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(url)
        }
    }
}
#endif

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
}
