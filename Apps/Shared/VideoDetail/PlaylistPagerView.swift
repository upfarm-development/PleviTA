
import SwiftUI
import PleviCore

struct PlaylistPagerView: View {
    let state: LoadState<[PlaylistPagerPage]>
    /// `Route.video`'s own `fromPlaylistId` — see this file's own doc
    /// comment on `currentSelection(in:)`.
    var initialPlaylistId: String?
    /// `(videoId, playlistId)` — `playlistId` is threaded back into
    /// `Route.video(_:fromPlaylistId:)` so the screen this pushes to
    /// defaults its own pager to the same playlist.
    var onSelect: (String, String) -> Void
    var onRetry: () -> Void
    /// Every action a row/callout in this pager offers — see VideoActions.swift for why one parameter and not six closures.
    var actions: VideoActions
    /// `false` only for `VideoDetailView`'s iPhone-only merged playlist + Similar Videos card (`playlistAndSimilarCard`'s own doc comment).
    var appliesOwnCard: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    /// `nil` until the user swipes or taps a chevron — see this file's own
    /// doc comment on why that's enough to seed the right initial page.
    @State private var selection: String?
    /// One entry per page, each page's own natural content height —
    /// see `maxPageHeight`'s own doc comment.
    @State private var pageHeights: [String: CGFloat] = [:]

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            loadingCard
        case .failed:
            failedCard
        case .loaded(let pages):
            // A video in no playlist at all: nothing to page over.
            if !pages.isEmpty {
                loadedCard(pages: pages)
            }
        }
    }

    private var loadingCard: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .modifier(OptionalCard(applies: appliesOwnCard))
    }

    private var failedCard: some View {
        VStack(spacing: 10) {
            Text("Couldn't load this video's playlists.")
                .pleviBody()
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .modifier(OptionalCard(applies: appliesOwnCard))
    }

    private struct OptionalCard: ViewModifier {
        let applies: Bool
        func body(content: Content) -> some View {
            if applies {
                content.pleviCard()
            } else {
                content
            }
        }
    }

    /// `self.selection`, if it still names one of `pages` (a reload can
    /// drop the page the user was on), else `initialPlaylistId` if that
    /// names one, else the first page in `/nav/`'s own order.
    private func currentSelection(in pages: [PlaylistPagerPage]) -> String? {
        if let selection, pages.contains(where: { $0.playlistId == selection }) { return selection }
        if let initialPlaylistId, pages.contains(where: { $0.playlistId == initialPlaylistId }) { return initialPlaylistId }
        return pages.first?.playlistId
    }

    @ViewBuilder
    private func loadedCard(pages: [PlaylistPagerPage]) -> some View {
        let resolvedSelection = currentSelection(in: pages)
        VStack(spacing: 0) {
            header(pages: pages, selection: resolvedSelection)
                .padding(.bottom, 12)

            ZStack(alignment: .top) {
                // Hidden measurement pass: `TabView` only lays out its *currently selected* page, so a page the user hasn't swiped to yet has no on-screen size to read.
                ForEach(pages) { page in
                    pageBody(page: page)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                            pageHeights[page.playlistId] = newHeight
                        }
                }

                #if os(tvOS)
                if let page = pages.first(where: { $0.playlistId == resolvedSelection }) ?? pages.first {
                    pageBody(page: page)
                        .id(page.playlistId)
                        .transition(.opacity)
                        .frame(height: maxPageHeight)
                }
                #else
                TabView(selection: Binding(get: { resolvedSelection }, set: { selection = $0 })) {
                    ForEach(pages) { page in
                        pageBody(page: page)
                            .tag(page.playlistId as String?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: maxPageHeight)
                #endif
            }

            if pages.count > 1 {
                footer(pages: pages, selection: resolvedSelection)
                    .padding(.top, 12)
            }
        }
        .padding(appliesOwnCard ? 16 : 0)
        .modifier(OptionalCard(applies: appliesOwnCard))
    }

    private var maxPageHeight: CGFloat {
        let measured = pageHeights.values.max() ?? 0
        guard measured > 0 else {
            #if os(tvOS)
            return 640
            #else
            return 440
            #endif
        }
        return measured
    }

    // MARK: - Header (playlist name, position, chevrons)

    @ViewBuilder
    private func header(pages: [PlaylistPagerPage], selection: String?) -> some View {
        if let page = pages.first(where: { $0.playlistId == selection }) ?? pages.first {
            HStack(spacing: 12) {
                if pages.count > 1 {
                    chevronButton(systemName: "chevron.left") { selectAdjacent(-1, pages: pages, current: selection) }
                        .accessibilityLabel("Previous playlist")
                }
                VStack(spacing: 2) {
                    Text(page.playlistName ?? "Playlist")
                        .pleviSectionHeading()
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("\(page.currentPosition) / \(page.totalCount)")
                        .pleviMono()
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity)
                if pages.count > 1 {
                    chevronButton(systemName: "chevron.right") { selectAdjacent(1, pages: pages, current: selection) }
                        .accessibilityLabel("Next playlist")
                }
            }
            #if os(tvOS)
            // The ‹ › buttons are the only way to change playlist on Apple TV (see `loadedCard`), and they sit at the far ends of this row, not above the cards.
            .focusSection()
            #endif
        }
    }

    private func chevronButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 28)
                .background(palette.canvas, in: Circle())
                // Inside the label, and `pleviSelectableStyle` below — the same pairing the two rows further down this file already use, and for the same two reasons.
                .tvFocusRing(cornerRadius: 14)
        }
        .pleviSelectableStyle()
    }

    private func selectAdjacent(_ delta: Int, pages: [PlaylistPagerPage], current: String?) {
        guard let index = pages.firstIndex(where: { $0.playlistId == current }) else { return }
        let newIndex = min(max(index + delta, 0), pages.count - 1)
        withAnimation(.easeInOut(duration: 0.2)) { selection = pages[newIndex].playlistId }
    }

    // MARK: - One page (callout + surrounding rows)

    @ViewBuilder
    private func pageBody(page: PlaylistPagerPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = page.entries.first(where: { $0.position == page.currentPosition + 1 }) {
                nextCallout(entry: next, playlistId: page.playlistId)
                Divider()
            }
            #if os(tvOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: PleviMetrics.tvShelfCardSpacing) {
                    ForEach(page.entries) { entry in
                        Button {
                            onSelect(entry.video.id, page.playlistId)
                        } label: {
                            VideoRow(
                                video: entry.video,
                                layout: .card,
                                position: entry.position,
                                // Where you are now, carried over from the row this replaces.
                                highlight: entry.isCurrent ? palette.accentTint : nil,
                                actions: actions
                            )
                            .frame(width: PleviMetrics.tvShelfCardWidth)
                        }
                        .pleviSelectableStyle()
                        .videoActionsContextMenu(video: entry.video, actions: actions)
                    }
                }
                // Room for a focused cell's lift, left INSIDE the row rather than taken from outside it.
                .padding(.horizontal, PleviMetrics.tvShelfFocusOverhang)
                .padding(.bottom, PleviMetrics.tvShelfLiftHeadroom)
            }
            .scrollClipDisabled()
            #else
            VStack(spacing: 0) {
                ForEach(Array(page.entries.enumerated()), id: \.element.id) { index, entry in
                    PlaylistPagerRow(entry: entry, actions: actions) {
                        onSelect(entry.video.id, page.playlistId)
                    }
                    if index < page.entries.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            #endif
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func nextCallout(entry: PlaylistPagerEntry, playlistId: String) -> some View {
        Button {
            onSelect(entry.video.id, playlistId)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next in Playlist")
                    .pleviEyebrow()
                    .foregroundStyle(palette.accent)
                Text(entry.video.title ?? "Untitled")
                    .pleviItemTitle()
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(palette.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Inside the label: `tvFocusRing` reads `\.isFocused`, which SwiftUI only sets within the focusable's own subtree.
            .tvFocusRing(cornerRadius: 10, scales: false)
        }
        .pleviSelectableStyle()
        .videoActionsContextMenu(video: entry.video, actions: actions)
    }

    // MARK: - Footer (dots + caption)

    @ViewBuilder
    private func footer(pages: [PlaylistPagerPage], selection: String?) -> some View {
        let index = pages.firstIndex { $0.playlistId == selection } ?? 0
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(pages) { page in
                    Capsule()
                        .fill(page.playlistId == selection ? palette.accent : palette.secondary.opacity(0.3))
                        .frame(width: page.playlistId == selection ? 16 : 6, height: 6)
                }
            }
            Text(footerCaption(index: index, total: pages.count))
                .pleviMono()
                .foregroundStyle(palette.secondary)
        }
    }

    private func footerCaption(index: Int, total: Int) -> String {
        #if os(tvOS)
        "Swipe left or right · \(index + 1) of \(total) playlists"
        #else
        "Swipe to switch playlist · \(index + 1) of \(total) playlists"
        #endif
    }
}

// MARK: - Row

/// The row's title, brightening on tvOS focus.
private struct FocusBrighteningTitle: View {
    let text: String
    let palette: PleviPalette

    @Environment(\.isFocused) private var isFocused

    private var color: Color {
        #if os(tvOS)
        isFocused ? palette.ink : palette.primaryContent
        #else
        palette.ink
        #endif
    }

    var body: some View {
        Text(text)
            .pleviItemTitle()
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

private struct PlaylistPagerRow: View {
    let entry: PlaylistPagerEntry
    let actions: VideoActions
    var onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    /// Same "compute from raw seconds first" rule as `VideoRow`'s own
    /// `durationText` — see that property's doc comment.
    private var durationText: String? {
        if let duration = entry.video.player?.duration {
            return PleviFormatting.durationBadge(seconds: duration)
        }
        guard let str = entry.video.player?.durationStr, !str.isEmpty else { return nil }
        return str
    }

    private var metadataLine: String? {
        let published = PleviFormatting.displayDate(from: entry.video.published)
        guard let published else { return durationText }
        guard let durationText else { return published }
        return "\(published) · \(durationText)"
    }

    private var isWatched: Bool { entry.video.player?.watched == true }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text("\(entry.position)")
                    .pleviMono()
                    .foregroundStyle(entry.isCurrent ? palette.accent : palette.secondary)
                    .frame(minWidth: 22, alignment: .trailing)

                ZStack(alignment: .topTrailing) {
                    RemoteImage(path: entry.video.vidThumbUrl, maxPixelSize: 240)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.caption)
                            .shadow(radius: 1)
                            .padding(3)
                    }
                }
                .frame(width: 84, height: 47)
                // The resume bar `VideoRow` draws, at this row's smaller scale.
                .overlay(alignment: .bottom) {
                    if let progress = entry.video.player?.progress, progress > 0 {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: proxy.size.width * CGFloat(min(max(progress / 100, 0), 1)))
                        }
                        .frame(height: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    FocusBrighteningTitle(text: entry.video.title ?? "Untitled", palette: palette)
                    if let metadataLine {
                        Text(metadataLine)
                            .pleviMono()
                            .foregroundStyle(palette.secondary)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(8)
            .background(
                entry.isCurrent ? palette.accentTint : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            #if os(tvOS)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(entry.isCurrent ? 0.9 : 0), lineWidth: 2)
            )
            #endif
            .contentShape(Rectangle())
            // Inside the label: `tvFocusRing` reads `\.isFocused`, which
            // SwiftUI only sets within the focusable's own subtree.
            .tvFocusRing(cornerRadius: 8, scales: false)
        }
        .pleviSelectableStyle()
        .videoActionsContextMenu(video: entry.video, actions: actions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to open this video.")
    }

    private var accessibilityLabelText: String {
        var parts = ["Number \(entry.position)", entry.video.title ?? "Untitled video"]
        if let published = PleviFormatting.displayDate(from: entry.video.published) { parts.append("published \(published)") }
        if let durationText { parts.append("duration \(durationText)") }
        parts.append(isWatched ? "watched" : "unwatched")
        if entry.isCurrent { parts.append("currently playing") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    PlaylistPagerView(
        state: .loaded([
            PlaylistPagerPage(
                playlistId: "p1",
                playlistName: "Morgan Monday",
                currentPosition: 3,
                totalCount: 41,
                entries: (1...5).map { position in
                    PlaylistPagerEntry(
                        video: Video(youtubeId: "v\(position)", title: "Episode \(position)", player: VideoPlayerState(duration: 4380, durationStr: "1h 13m", watched: false, position: nil, progress: nil)),
                        position: position,
                        isCurrent: position == 3
                    )
                }
            )
        ]),
        initialPlaylistId: nil,
        onSelect: { _, _ in },
        onRetry: {},
        actions: .preview
    )
    .padding()
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
}
