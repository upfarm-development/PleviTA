
import SwiftUI
import PleviCore

struct SimilarVideosSection: View {
    /// `.carousel` (the original, everywhere): `VideoRow(.card)` cells in a horizontal scroll.
    enum Layout { case carousel, verticalList }

    let state: LoadState<[Video]>
    var layout: Layout = .carousel
    /// Every action a row in this section offers — see VideoActions.swift for why one
    /// parameter and not six closures.
    var actions: VideoActions
    var onSelect: (Video) -> Void
    var onRetry: () -> Void
    /// `false` only for `VideoDetailView`'s iPhone-only merged playlist + Similar Videos card (`playlistAndSimilarCard`'s own doc comment).
    var appliesOwnCard: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                header
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(appliesOwnCard ? 16 : 0)
            .modifier(OptionalCard(applies: appliesOwnCard))
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                header
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
            .padding(appliesOwnCard ? 16 : 0)
            .modifier(OptionalCard(applies: appliesOwnCard))
        case .loaded(let videos):
            if !videos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    switch layout {
                    case .carousel:
                        carouselContent(videos: videos)
                    case .verticalList:
                        verticalListContent(videos: videos)
                    }
                }
                .padding(appliesOwnCard ? 16 : 0)
                .modifier(OptionalCard(applies: appliesOwnCard))
            }
        }
    }

    /// See `appliesOwnCard`'s own doc comment.
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

    /// tvOS sizes its cells from `PleviMetrics.tvShelfCardWidth` — four across the video
    /// screen's card — while iOS keeps the 220 it has always used. 220 on a television would
    /// put eight and a half cards on a row at a viewing distance where four is already small.
    private var cardWidth: CGFloat {
        #if os(tvOS)
        PleviMetrics.tvShelfCardWidth
        #else
        220
        #endif
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        PleviMetrics.tvShelfCardSpacing
        #else
        16
        #endif
    }

    private func carouselContent(videos: [Video]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: cardSpacing) {
                ForEach(videos) { video in
                    Button {
                        onSelect(video)
                    } label: {
                        VideoRow(
                            video: video,
                            layout: .card,
                            actions: actions
                        )
                        .frame(width: cardWidth)
                    }
                    .pleviSelectableStyle()
                    .videoActionsContextMenu(video: video, actions: actions)
                }
            }
            .padding(.bottom, 4)
        }
        #if os(tvOS)
        // A focused cell grows past the row, and a `ScrollView` clips its content to its own bounds — so at either end of the shelf the lift was cut off.
        .scrollClipDisabled()
        #endif
    }

    private func verticalListContent(videos: [Video]) -> some View {
        VStack(spacing: 0) {
            ForEach(videos) { video in
                Button {
                    onSelect(video)
                } label: {
                    VideoRow(
                        video: video,
                        layout: .row,
                        actions: actions
                    )
                }
                .pleviSelectableStyle()
                .videoActionsContextMenu(video: video, actions: actions)
                if video.id != videos.last?.id {
                    Divider()
                        .overlay(palette.secondary.opacity(0.25))
                }
            }
        }
    }

    private var header: some View {
        Text("Similar Videos")
            .pleviSectionHeading()
            .foregroundStyle(palette.ink)
    }
}
