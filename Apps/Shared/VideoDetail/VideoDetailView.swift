import SwiftUI
import PleviCore

#if os(tvOS)
/// Everything one tvOS fullscreen playback session needs, captured atomically at the moment a Play action fires.
private struct PlaybackRequest: Identifiable {
    let id = UUID()
    let videos: [Video]
    let startIndex: Int
    let startPosition: Double?
}

/// Captured atomically alongside `showResumeDialog` — same reason `PlaybackRequest` exists.
private struct ResumePrompt {
    let video: Video
    let position: Double
}

/// The controls `VideoDetailView` can hand tvOS's focus engine by name. Only
/// Play is addressed today (it's the screen's default focus target); the enum
/// exists because `@FocusState` needs a value type to bind against.
private enum TVFocusTarget: Hashable {
    case play
}
#endif

struct VideoDetailView: View {
    let videoId: String
    var navigate: (Route) -> Void = { _ in }
    var fromPlaylistId: String? = nil

    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(VideoCache.self) private var videoCache
    @Environment(PlaybackHistory.self) private var playbackHistory
    @Environment(VideoActionsCoordinator.self) private var videoActionsCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(iOS)
    /// True when this page is being shown off the offline shelf — see
    /// `OfflineShelfEnvironment`. Suppresses the sections that need a server.
    @Environment(\.isOfflineShelf) private var isOfflineShelf
    #endif
    /// Set by a `DescriptionText` timestamp tap and consumed once by
    /// `InlinePlayerSection` — see this file's own doc comment.
    @State private var seekRequestSeconds: Double?
    /// Owns the one `VideoPlaybackController` `InlinePlayerSection` is handed, rather than letting that section create/store its own.
    @State private var playbackController: VideoPlaybackController?
    @Environment(PlaybackSession.self) private var playbackSession
    @Environment(NavigationModel.self) private var navigation
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @Environment(OfflinePlaybackLedger.self) private var offlinePlaybackLedger
    #endif
    @State private var store: VideoDetailStore?
    #if os(iOS)
    /// Where Delete's confirmation points from when chosen in this page's "…" menu — see
    /// `VideoActionsCoordinator.PendingConfirmation.anchor`.
    @State private var overflowMenuAnchor = UUID()
    #endif

    #if os(tvOS)
    @Environment(\.tvOSMediaProxy) private var mediaProxy
    @State private var playbackRequest: PlaybackRequest?
    @State private var resumePrompt: ResumePrompt?
    @State private var showResumeDialog = false
    @FocusState private var tvFocusTarget: TVFocusTarget?
    /// Whether the opening focus has already been claimed, so it is claimed exactly once.
    /// See the `.task` in `tvOSContent` for what went wrong without it.
    @State private var didClaimInitialFocus = false
    #endif

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
        .task(id: videoId) {
            guard let client = authStore.client else { return }
            guard store?.videoId != videoId else { return }
            #if os(iOS)
            playbackController = playbackSession.controller(
                for: videoId,
                client: client,
                imageLoader: authStore.imageLoader,
                fallbackPlayerMode: { [weak appSettings] in appSettings?.fallbackPlayerMode ?? .automatic },
                isSponsorBlockEnabled: { [weak appSettings] in appSettings?.sponsorBlockEnabled ?? false },
                sponsorBlockCategories: { [weak appSettings] in appSettings?.sponsorBlockCategories ?? [] },
                playbackHistory: playbackHistory,
                offlineMediaProvider: { [weak offlineLibrary] videoId in offlineLibrary?.localMediaURL(forVideoId: videoId) },
                offlineOutbox: offlinePlaybackLedger,
                offlineSubtitlesProvider: { [weak offlineLibrary] videoId in offlineLibrary?.localSubtitles(forVideoId: videoId) ?? [] }
            )
            #endif
            // Seeded from the copy the list the user just tapped was already showing, so
            // this page slides in drawn rather than blank — see `VideoCache`. `loadVideo`
            // below still refetches and replaces it.
            var seed = videoCache.video(id: videoId)
            #if os(iOS)
            if let video = seed, offlineLibrary.localMediaURL(forVideoId: videoId) != nil,
               let entry = offlinePlaybackLedger.entry(for: videoId) {
                seed = video.applyingOfflineLedger(entry)
            }
            #endif
            let newStore = VideoDetailStore(
                client: client,
                videoId: videoId,
                seed: seed
            )
            store = newStore
            #if os(iOS)
            // On the offline shelf there is no server to ask, and asking anyway is what
            // turned a saved video into a working player under three error panels. The seed
            // already holds everything this page can show — see `OfflineShelfEnvironment`.
            if isOfflineShelf {
                await newStore.loadVideo()
                return
            }
            #endif
            async let video: Void = newStore.loadVideo()
            async let pager: Void = newStore.loadPager(
                hideWatched: appSettings.hideWatched(in: .playlistEntries),
                sortField: appSettings.playlistDetailSortField,
                sortOrder: appSettings.playlistDetailSortOrder
            )
            async let comments: Void = newStore.loadCommentsIfNeeded()
            async let similar: Void = newStore.loadSimilarIfNeeded()
            _ = await (video, pager, comments, similar)
        }
        #if os(tvOS)
        .fullScreenCover(item: $playbackRequest) { request in
            if let client = authStore.client {
                PlayerScreen(
                    videos: request.videos,
                    startIndex: request.startIndex,
                    startPosition: request.startPosition,
                    client: client,
                    imageLoader: authStore.imageLoader,
                    autoPlayNext: appSettings.autoPlayNext,
                    fallbackPlayerMode: { [weak appSettings] in appSettings?.fallbackPlayerMode ?? .automatic },
                    isSponsorBlockEnabled: { [weak appSettings] in appSettings?.sponsorBlockEnabled ?? false },
                    sponsorBlockCategories: { [weak appSettings] in appSettings?.sponsorBlockCategories ?? [] },
                    mediaProxy: mediaProxy,
                    playbackHistory: playbackHistory,
                    onFinished: { finalPosition, watched in
                        // Applied immediately, before the round trip below even starts.
                        store?.applyLocalPlaybackResult(position: finalPosition, watched: watched)
                        Task { await store?.refreshVideo() }
                    }
                )
            }
        }
        .confirmationDialog(
            resumePrompt.map { "Resume from \(PleviFormatting.clockDuration(seconds: $0.position))?" } ?? "Resume playback?",
            isPresented: $showResumeDialog,
            titleVisibility: .visible
        ) {
            Button("Resume") {
                if let prompt = resumePrompt {
                    playbackRequest = PlaybackRequest(videos: [prompt.video], startIndex: 0, startPosition: prompt.position)
                }
            }
            Button("Start Over") {
                if let prompt = resumePrompt {
                    playbackRequest = PlaybackRequest(videos: [prompt.video], startIndex: 0, startPosition: nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        #endif
    }

    /// For a video that is NOT this screen's own — Similar Videos rows. `store` doubles as
    /// this section's `VideoMutating` (it drops a removed id from `similarState`).
    private func videoActions(list: any VideoMutating) -> VideoActions {
        VideoActions(list: list, coordinator: videoActionsCoordinator, navigate: navigate)
    }

    /// For the video THIS screen is about (the "…" overflow button below) — deleting it must
    /// leave the screen, not just drop a row, so this adds `onRemoved` teardown on top of the
    /// same `videoActions(list:)` plumbing.
    private func ownVideoActions(video: Video, store: VideoDetailStore) -> VideoActions {
        VideoActions(list: store, coordinator: videoActionsCoordinator, navigate: navigate,
                     onRemoved: {
                         #if os(iOS)
                         playbackController?.stop()
                         if case .video(let playingId, _) = navigation.playing?.route, playingId == video.id {
                             navigation.playing = nil
                         }
                         #endif
                         dismiss()
                     })
    }

    @ViewBuilder
    private func content(store: VideoDetailStore) -> some View {
        switch store.videoState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Load Video", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "Something went wrong.")
            } actions: {
                Button("Retry") { Task { await store.loadVideo() } }
            }
        case .loaded(let video):
            #if os(iOS)
            if let client = authStore.client {
                iOSContent(video: video, store: store, client: client)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            tvOSContent(video: video, store: store)
            #endif
        }
    }

    // MARK: - iOS/iPadOS layout

    #if os(iOS)
    @ViewBuilder
    private func iOSContent(video: Video, store: VideoDetailStore, client: TAClient) -> some View {
        if horizontalSizeClass == .regular {
            iPadContent(video: video, store: store, client: client)
        } else {
            iPhoneContent(video: video, store: store, client: client)
        }
    }

    private func iPhoneContent(video: Video, store: VideoDetailStore, client: TAClient) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let playbackController {
                    InlinePlayerSection(
                        video: video,
                        controller: playbackController,
                        seekRequestSeconds: $seekRequestSeconds,
                        onFinished: { Task { await store.refreshVideo() } }
                    )
                }
                titleDetailsCard(video: video, store: store)

                if AppSettings.videoDetailSectionOrder.contains(.fileDetails) {
                    FileDetailsSection(video: video, isCollapsible: true)
                }

                if !isOfflineShelf {
                    iPhoneBottomGroup(video: video, store: store)
                }
            }
            .padding(PleviMetrics.insetPhone)
        }
    }

    @ViewBuilder
 
    private func iPadContent(video: Video, store: VideoDetailStore, client: TAClient) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let playbackController {
                    InlinePlayerSection(
                        video: video,
                        controller: playbackController,
                        seekRequestSeconds: $seekRequestSeconds,
                        onFinished: { Task { await store.refreshVideo() } }
                    )
                }
                titleDetailsCard(video: video, store: store)

                if !isOfflineShelf {
                    iPadBottomRow(video: video, store: store)
                }
            }
            .padding(PleviMetrics.insetPad)
        }
    }
    #endif

    @ViewBuilder
    private func iPadBottomRow(video: Video, store: VideoDetailStore) -> some View {
        let showPlaylist = AppSettings.videoDetailSectionOrder.contains(.inThisPlaylist)
        let showComments = AppSettings.videoDetailSectionOrder.contains(.comments)
        let showSimilar = AppSettings.videoDetailSectionOrder.contains(.similarVideos)
        let commentsHaveContent: Bool = {
            if case .loaded(let roots) = store.commentsState { return !roots.isEmpty }
            return true
        }()
        let pairWithComments = showComments && commentsHaveContent

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                if pairWithComments {
                    sectionView(
                        .comments, video: video, store: store,
                        includeInThisPlaylist: false, fileDetailsCollapsible: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showPlaylist || showSimilar {
                        VStack(alignment: .leading, spacing: 16) {
                            if showPlaylist {
                                pagerView(store: store)
                            }
                            if showSimilar {
                                sectionView(
                                    .similarVideos, video: video, store: store,
                                    includeInThisPlaylist: false, fileDetailsCollapsible: false,
                                    similarVideosLayout: .verticalList
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if showPlaylist {
                        pagerView(store: store)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if showSimilar {
                        sectionView(
                            .similarVideos, video: video, store: store,
                            includeInThisPlaylist: false, fileDetailsCollapsible: false,
                            similarVideosLayout: .verticalList
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !pairWithComments && showComments {
                sectionView(
                    .comments, video: video, store: store,
                    includeInThisPlaylist: false, fileDetailsCollapsible: false
                )
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func iPhoneBottomGroup(video: Video, store: VideoDetailStore) -> some View {
        let showComments = AppSettings.videoDetailSectionOrder.contains(.comments)

        VStack(alignment: .leading, spacing: 16) {
            playlistAndSimilarCard(video: video, store: store)
            if showComments {
                sectionView(
                    .comments, video: video, store: store,
                    includeInThisPlaylist: false, fileDetailsCollapsible: false
                )
            }
        }
    }

    @ViewBuilder
    private func playlistAndSimilarCard(video: Video, store: VideoDetailStore) -> some View {
        let showPlaylist = AppSettings.videoDetailSectionOrder.contains(.inThisPlaylist)
        let showSimilar = AppSettings.videoDetailSectionOrder.contains(.similarVideos)

        if showPlaylist || showSimilar {
            VStack(alignment: .leading, spacing: 16) {
                if showPlaylist {
                    pagerView(store: store, appliesOwnCard: false)
                }
                if showPlaylist && showSimilar {
                    Divider()
                }
                if showSimilar {
                    SimilarVideosSection(
                        state: store.similarState,
                        layout: .carousel,
                        actions: videoActions(list: store),
                        onSelect: { similarVideo in
                            navigate(.video(similarVideo.id))
                        },
                        onRetry: { Task { await store.retrySimilar() } },
                        appliesOwnCard: false
                    )
                }
            }
            .padding(16)
            .pleviCard()
        }
    }
    #endif


    // MARK: - tvOS layout

    #if os(tvOS)
    private func tvOSContent(video: Video, store: VideoDetailStore) -> some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                RemoteImage(path: video.vidThumbUrl, maxPixelSize: 1920)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // Vertical, not leading-to-trailing.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0),
                    .init(color: .black.opacity(0.15), location: Self.tvHeroRevealFraction * 0.55),
                    .init(color: .black.opacity(0.75), location: Self.tvHeroRevealFraction * 0.92),
                    .init(color: .black.opacity(0.95), location: Self.tvHeroRevealFraction),
                    .init(color: .black.opacity(0.98), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Color.clear
                        .frame(height: Self.tvHeroSpacerHeight)
                        // Nothing to focus, and nothing that should intercept a swipe.
                        .allowsHitTesting(false)

                    tvOSTitleDetailsCard(video: video, store: store)

                    tvOSBottomStack(video: video, store: store)
                }
                // Top only, and small.
                .padding(.top, 24)
            }
            // Clears the sidebar's rail, which stays on screen here too.
            .pleviRootHorizontalInset(PleviMetrics.insetTV.horizontal)
            .padding(.top, 20)
            // NO scroll restore here, and that is a decision rather than an omission.
        }
        .defaultFocus($tvFocusTarget, .play)
        .task {
            guard !didClaimInitialFocus else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !didClaimInitialFocus else { return }
            didClaimInitialFocus = true
            tvFocusTarget = .play
        }
    }

    /// How far down the frame the information starts, as a fraction of the screen.
    private static let tvHeroRevealFraction: CGFloat = 2.0 / 3.0

    private static let tvScreenHeight: CGFloat = 1080
    private static var tvHeroSpacerHeight: CGFloat { tvScreenHeight * tvHeroRevealFraction }

    /// What iPad puts in two columns, tvOS stacks in one.
    @ViewBuilder
    private func tvOSBottomStack(video: Video, store: VideoDetailStore) -> some View {
        let sections = AppSettings.videoDetailSectionOrder
        let showPlaylist = sections.contains(.inThisPlaylist)
        let showSimilar = sections.contains(.similarVideos)
        let showComments = sections.contains(.comments)

        VStack(alignment: .leading, spacing: 28) {
            if showPlaylist {
                pagerView(store: store)
            }
            if showSimilar {
                // A shelf, not a list.
                sectionView(
                    .similarVideos, video: video, store: store,
                    includeInThisPlaylist: false, fileDetailsCollapsible: false,
                    similarVideosLayout: .carousel
                )
            }
            if showComments {
                sectionView(
                    .comments, video: video, store: store,
                    includeInThisPlaylist: false, fileDetailsCollapsible: false
                )
            }
        }
        // Each section already fills the column; stating it here too keeps the stack itself
        // from shrinking to its widest child when one of them is hidden.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// tvOS's own version of `titleDetailsWithFileDetails` — see that one for the report.
    @ViewBuilder
 
    private func tvOSTitleDetailsCard(video: Video, store: VideoDetailStore) -> some View {
        let sections = AppSettings.videoDetailSectionOrder
        let showStats = sections.contains(.stats)
        let showActions = sections.contains(.actions)
        let showDescription = sections.contains(.description)
        let items = showStats ? statItems(video: video) : []
        let hasDescription = showDescription && !(video.videoDescription ?? "").isEmpty

        return VStack(alignment: .leading, spacing: 20) {
            Text(video.title ?? "Untitled")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(3)

            channelRow(video: video)

            if !items.isEmpty || showActions {
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    if !items.isEmpty {
                        // The same split iPad got.
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(items.filter { !$0.isFileFact }, id: \.label) { statItemView($0) }
                            Spacer(minLength: 40)
                            ForEach(items.filter(\.isFileFact), id: \.label) { statItemView($0) }
                        }
                    }
                    if showActions {
                        tvOSActionsSection(video: video, store: store)
                    }
                }
            }

            if hasDescription, let description = video.videoDescription {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Description")
                        .pleviEyebrow()
                        .foregroundStyle(palette.secondary)
                    // tvOS has no inline player to seek within (unlike iOS/iPadOS's `titleDetailsCard`, which routes this through `seekRequestSeconds`).
                    DescriptionText(text: description) { seconds in
                        playbackRequest = PlaybackRequest(videos: [video], startIndex: 0, startPosition: seconds)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .pleviCard()
    }

    private func tvOSActionsSection(video: Video, store: VideoDetailStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    tapPlay(video: video)
                } label: {
                    Label(playLabelText(video: video), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                // No `.foregroundStyle(.white)` here.
                .focused($tvFocusTarget, equals: .play)

                Menu {
                    VideoActionsMenu(video: video, actions: ownVideoActions(video: video, store: store))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.bordered)
            }
            .focusSection()
        }
    }

    /// Shares `ResumePolicy.decide` with `tapPlay(video:)` below, deliberately.
    private func playLabelText(video: Video) -> String {
        switch ResumePolicy.decide(
            behavior: appSettings.resumeBehavior,
            isWatched: video.player?.watched == true,
            position: video.player?.position,
            duration: video.player?.duration
        ) {
        case .startFromBeginning:
            return "Play"
        case .resume(let position), .ask(let position):
            return "Resume · \(PleviFormatting.clockDuration(seconds: position))"
        }
    }

    private func tapPlay(video: Video) {
        switch ResumePolicy.decide(
            behavior: appSettings.resumeBehavior,
            isWatched: video.player?.watched == true,
            position: video.player?.position,
            duration: video.player?.duration
        ) {
        case .startFromBeginning:
            playbackRequest = PlaybackRequest(videos: [video], startIndex: 0, startPosition: nil)
        case .resume(let position):
            playbackRequest = PlaybackRequest(videos: [video], startIndex: 0, startPosition: position)
        case .ask(let position):
            resumePrompt = ResumePrompt(video: video, position: position)
            showResumeDialog = true
        }
    }
    #endif

    // MARK: - Fixed title block (iOS/iPadOS)

    #if os(iOS)
    private func titleDetailsCard(video: Video, store: VideoDetailStore) -> some View {
        let sections = AppSettings.videoDetailSectionOrder
        let showStats = sections.contains(.stats)
        let showActions = sections.contains(.actions)
        let showDescription = sections.contains(.description)
        let items = showStats ? statItems(video: video) : []
        let hasDescription = showDescription && !(video.videoDescription ?? "").isEmpty

        return VStack(alignment: .leading, spacing: 14) {
            Text(video.title ?? "Untitled")
                .font(.title2.bold())
                .foregroundStyle(palette.ink)
                .lineLimit(3)

            channelRow(video: video)

            if !items.isEmpty || showActions {
                Divider()
                // One row, not a `ViewThatFits` between a wide and a stacked arrangement.
                HStack(alignment: .top, spacing: 16) {
                    if !items.isEmpty {
                        statsRow(items: items)
                    }
                    if showActions {
                        overflowMenu(video: video, store: store)
                    }
                }
            }

            if hasDescription, let description = video.videoDescription {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Description")
                        .pleviEyebrow()
                        .foregroundStyle(palette.secondary)
                    DescriptionText(text: description) { seconds in
                        seekRequestSeconds = seconds
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pleviCard()
    }


    /// `watchedButton` plus the "…" overflow (Ignore/Delete/Add to Playlist/Open Channel).
    private func overflowMenu(video: Video, store: VideoDetailStore) -> some View {
        Button {} label: {
            Image(systemName: "ellipsis").frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                VideoActionsMenu(video: video, actions: ownVideoActions(video: video, store: store), anchor: overflowMenuAnchor)
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .accessibilityLabel("More actions")
        }
        // Delete chosen here opens pointing at this button, not the middle of the screen.
        .videoActionConfirmation(videoActionsCoordinator, anchor: overflowMenuAnchor)
    }
    #endif

    @ViewBuilder
    private func channelRow(video: Video) -> some View {
        #if os(tvOS)
        channelRowContent(video: video)
        #else
        Button {
            if let channelId = video.channel?.channelId {
                navigate(.channel(channelId))
            }
        } label: {
            channelRowContent(video: video)
        }
        .buttonStyle(.plain)
        .tvFocusRing(cornerRadius: channelAvatarSize / 2)
        #endif
    }

    private func channelRowContent(video: Video) -> some View {
        HStack(spacing: 8) {
            RemoteImage(path: video.channel?.channelThumbUrl, maxPixelSize: 80)
                .frame(width: channelAvatarSize, height: channelAvatarSize)
                .clipShape(Circle())
            Text(video.channel?.channelName ?? "Unknown channel")
                .pleviBody()
                .foregroundStyle(palette.secondary)
        }
    }

    private var channelAvatarSize: CGFloat {
        #if os(tvOS)
        44
        #else
        28
        #endif
    }

    // MARK: - Section dispatch

    /// Single source of truth mapping one `VideoDetailSection` case to its view, shared by every layout above.
    @ViewBuilder
    private func sectionView(
        _ section: VideoDetailSection,
        video: Video,
        store: VideoDetailStore,
        includeInThisPlaylist: Bool,
        fileDetailsCollapsible: Bool,
        similarVideosLayout: SimilarVideosSection.Layout = .carousel
    ) -> some View {
        switch section {
        case .stats:
            statsStripSection(video: video)
        case .actions:
            #if os(tvOS)
            tvOSActionsSection(video: video, store: store)
            #else
            actionsSection(video: video, store: store)
            #endif
        case .fileDetails:
            FileDetailsSection(video: video, isCollapsible: fileDetailsCollapsible)
        case .description:
            descriptionSection(video: video)
        case .inThisPlaylist:
            if includeInThisPlaylist {
                pagerView(store: store)
            } else {
                EmptyView()
            }
        case .comments:
            CommentsSection(state: store.commentsState) {
                Task { await store.retryComments() }
            }
        case .similarVideos:
            SimilarVideosSection(
                state: store.similarState,
                layout: similarVideosLayout,
                actions: videoActions(list: store),
                onSelect: { similarVideo in
                    navigate(.video(similarVideo.id))
                },
                onRetry: { Task { await store.retrySimilar() } }
            )
        }
    }

    private func pagerView(store: VideoDetailStore, appliesOwnCard: Bool = true) -> some View {
        PlaylistPagerView(
            state: store.pagerState,
            initialPlaylistId: fromPlaylistId,
            onSelect: { videoId, playlistId in
                navigate(.video(videoId, fromPlaylistId: playlistId))
            },
            onRetry: {
                Task {
                    await store.loadPager(
                        hideWatched: appSettings.hideWatched(in: .playlistEntries),
                        sortField: appSettings.playlistDetailSortField,
                        sortOrder: appSettings.playlistDetailSortOrder
                    )
                }
            },
            // Built here from `store` plus the environment coordinator so this function's own four callers (below) need no change.
            actions: videoActions(list: store),
            appliesOwnCard: appliesOwnCard
        )
    }

    // MARK: - Stats (fixed 4-up strip)

    /// Whether the stats strip carries the file facts too. tvOS and iPad have the width;
    /// an iPhone does not, and keeps `FileDetailsSection`'s collapsible row instead.
    private var includesFileFacts: Bool {
        #if os(tvOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    /// `isFileFact` splits the row into its two halves: what the video *is* (published, views, likes, runtime) and what the file *is* (size, video, audio).
    private struct StatItem {
        let label: String
        let value: String
        var isFileFact: Bool = false
    }

    private func statItems(video: Video) -> [StatItem] {
        var items: [StatItem] = []
        if let publishedDisplay = PleviFormatting.displayDate(from: video.published) {
            items.append(StatItem(label: "Published", value: publishedDisplay))
        }
        if let views = video.stats?.viewCount {
            items.append(StatItem(label: "Views", value: PleviFormatting.compactCount(views)))
        }
        if let likes = video.stats?.likeCount {
            items.append(StatItem(label: "Likes", value: PleviFormatting.compactCount(likes)))
        }
        if let duration = video.player?.durationStr {
            items.append(StatItem(label: "Runtime", value: duration))
        }
        if includesFileFacts {
            if let size = VideoFileFacts.fileSize(video) {
                items.append(StatItem(label: "Size", value: size, isFileFact: true))
            }
            if let videoStream = VideoFileFacts.videoStreamCompact(video) {
                items.append(StatItem(label: "Video", value: videoStream, isFileFact: true))
            }
            if let audioStream = VideoFileFacts.audioStreamCompact(video) {
                items.append(StatItem(label: "Audio", value: audioStream, isFileFact: true))
            }
        }
        return items
    }

    @ViewBuilder
    private func statsStripSection(video: Video) -> some View {
        let items = statItems(video: video)
        if !items.isEmpty {
            statsRow(items: items)
                .padding(16)
                .pleviCard()
        }
    }

    @ViewBuilder
    private func statsRow(items: [StatItem]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.label) { statItemView($0) }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                // Every cell at its natural width.
                ForEach(items.filter { !$0.isFileFact }, id: \.label) { statItemView($0) }
                Spacer(minLength: 20)
                ForEach(items.filter(\.isFileFact), id: \.label) { statItemView($0) }
            }
        }
    }

    private func statItemView(_ item: StatItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
                .pleviEyebrow()
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(item.value)
                .pleviMono()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    // MARK: - Actions (iOS/iPadOS: Mark as Watched + overflow)

    /// Dead code: `sectionView(.actions)` (below) is never reached on iOS.
    @ViewBuilder
    private func actionsSection(video: Video, store: VideoDetailStore) -> some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    if let channelId = video.channel?.channelId {
                        navigate(.channel(channelId))
                    }
                } label: {
                    Label("Open Channel", systemImage: "person.crop.square")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .pleviCard()
    }

    // MARK: - Description

    @ViewBuilder
    private func descriptionSection(video: Video) -> some View {
        if let description = video.videoDescription, !description.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Description")
                    .pleviEyebrow()
                    .foregroundStyle(palette.secondary)
                DescriptionText(text: description) { seconds in
                    #if os(iOS)
                    seekRequestSeconds = seconds
                    #else
                    playbackRequest = PlaybackRequest(videos: [video], startIndex: 0, startPosition: seconds)
                    #endif
                }
            }
            .padding(16)
            .pleviCard()
        }
    }

}

#Preview {
    NavigationStack {
        VideoDetailView(videoId: Video.previewVideo.id)
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
}
