
import SwiftUI
import PleviCore

struct VideoRow: View {
    enum Layout {
        /// The grid cell — today's `VideoCard` body.
        case card
        /// The full-width list row — today's `VideoListRow` body, with an
        /// optional leading `position` index for playlist detail.
        case row
    }

    let video: Video
    var layout: Layout = .row
    /// Leading mono index — playlist detail's own row number. Only drawn
    /// in `.row` layout; a grid `.card` cell has no natural place for a
    /// leading index number.
    var position: Int? = nil
    /// How far into the video you are, as a bar along the bottom of the thumbnail — drawn only once it has been started.
    var showProgressBar: Bool = true
    var highlight: Color? = nil
    /// Every action this row offers, as one value — see VideoActions.swift for why
    /// one parameter and not six closures.
    var actions: VideoActions

    @Environment(VideoCache.self) private var videoCache
    #if os(iOS)
    /// Drives the downloaded badge. Read as a set — see
    /// `OfflineLibrary.downloadedVideoIds` for why this one is not `isSaved`.
    @Environment(OfflineLibrary.self) private var offlineLibrary
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }
    private var isWatched: Bool { video.player?.watched == true }
    #if os(iOS)
    private var isDownloaded: Bool { offlineLibrary.downloadedVideoIds.contains(video.id) }
    #endif

    /// tvOS: unfocused rows use the dim `primaryContent` tier, brightening to `ink` on focus.
    private var titleColor: Color {
        #if os(tvOS)
        isFocused ? palette.ink : palette.primaryContent
        #else
        palette.ink
        #endif
    }

    /// Same mechanism as `titleColor`, one tier down: tvOS's `metadata` →
    /// `secondary` on focus; `secondary` unconditionally elsewhere.
    private var metadataColor: Color {
        #if os(tvOS)
        isFocused ? palette.secondary : palette.metadata
        #else
        palette.secondary
        #endif
    }

    private var positionFont: Font {
        #if os(tvOS)
        .system(size: 21, weight: .medium, design: .monospaced)
        #else
        .system(size: 15, weight: .medium, design: .monospaced)
        #endif
    }

    var body: some View {
        Group {
            switch layout {
            case .card: cardBody
            case .row: rowBody
            }
        }
        .task { cacheForFastOpen() }
    }

    /// Files this video so tapping it can open a detail screen that is already drawn, instead of a blank page that fills in mid-transition (`VideoCache`).
    private func cacheForFastOpen() {
        videoCache.store(video)
    }

    // MARK: - Card layout (grid cell)

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail(cornerRadius: PleviMetrics.cardCornerRadius, fixedSize: nil, maxPixelSize: 480, fit: true)
                // A card can carry the playlist index too, now that tvOS's "In this playlist" is a carousel of these rather than a list of `rowBody`s.
                .overlay(alignment: .topLeading) {
                    if let position {
                        Text("\(position)")
                            .font(positionFont)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(6)
                    }
                }

            FixedLineText(text: video.title ?? "Untitled", lineLimit: 2, alignment: .leading)
                .pleviItemTitle()
                .foregroundStyle(titleColor)

            HStack {
                Text(video.channel?.channelName ?? "Unknown channel")
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let publishedDisplay = PleviFormatting.displayDate(from: video.published) {
                    Text(publishedDisplay)
                        .lineLimit(1)
                }
            }
            .pleviMono()
            .foregroundStyle(metadataColor)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Before `tvFocusRing`, so the lift scales the tint along with the card. See
        // `highlight`'s own doc comment for the report that put it here rather than at the
        // call site.
        .background(
            highlight ?? .clear,
            in: RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: PleviMetrics.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }

    // MARK: - Row layout (list row / playlist entry row)

    private var rowBody: some View {
        HStack(alignment: .center, spacing: 12) {
            if let position {
                Text("\(position)")
                    .font(positionFont)
                    .foregroundStyle(metadataColor)
                    .frame(minWidth: 22, alignment: .center)
            }

            thumbnail(cornerRadius: 8, fixedSize: CGSize(width: 96, height: 54), maxPixelSize: 320, fit: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title ?? "Untitled")
                    .pleviItemTitle()
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(video.channel?.channelName ?? "Unknown channel")
                        .lineLimit(1)
                    if let publishedLine {
                        Text(publishedLine)
                            .lineLimit(1)
                    }
                }
                .pleviMono()
                .foregroundStyle(metadataColor)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: 8, scales: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }

    // No `.contextMenu` here, deliberately.

    private var accessibilityHintText: String {
        "Double tap to open. Touch and hold for watched status, playlist, channel, ignore and delete actions."
    }

    private var accessibilityLabelText: String {
        var parts: [String] = []
        if let position { parts.append("Number \(position)") }
        parts.append(video.title ?? "Untitled video")
        if let channel = video.channel?.channelName { parts.append(channel) }
        if let publishedDisplay = PleviFormatting.displayDate(from: video.published) {
            parts.append("published \(publishedDisplay)")
        }
        if let durationText { parts.append("duration \(durationText)") }
        parts.append(isWatched ? "watched" : "unwatched")
        if showProgressBar, let progress = video.player?.progress, progress > 0 {
            parts.append("\(Int(progress)) percent watched")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnail(cornerRadius: CGFloat, fixedSize: CGSize?, maxPixelSize: CGFloat, fit: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let fixedSize {
                    RemoteImage(path: video.vidThumbUrl, maxPixelSize: maxPixelSize)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .frame(width: fixedSize.width, height: fixedSize.height)
                } else {
                    RemoteImage(path: video.vidThumbUrl, maxPixelSize: maxPixelSize)
                        .aspectRatio(16.0 / 9.0, contentMode: fit ? .fit : .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if showsDurationBadge {
                DurationBadge(text: durationText)
                    .padding(6)
            }

            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .font(layout == .card ? .title3 : .caption)
                    .shadow(radius: layout == .card ? 2 : 1)
                    .padding(layout == .card ? 6 : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            #if os(iOS)
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .font(layout == .card ? .title3 : .caption)
                    .shadow(radius: layout == .card ? 2 : 1)
                    .padding(layout == .card ? 6 : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            #endif
        }
        .frame(width: fixedSize?.width, height: fixedSize?.height)
        .overlay(alignment: .bottom) {
            if showProgressBar, let progress = video.player?.progress, progress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: proxy.size.width * CGFloat(min(max(progress / 100, 0), 1)))
                }
                .frame(height: 4)
            }
        }
    }

    /// Whether the duration rides on the thumbnail as a pill, or on the metadata line.
    private var showsDurationBadge: Bool {
        #if os(tvOS)
        layout != .row
        #else
        true
        #endif
    }

    /// The second metadata line: the published date, plus the duration on the tvOS rows that no longer draw it over the thumbnail.
    private var publishedLine: String? {
        let published = PleviFormatting.displayDate(from: video.published)
        guard !showsDurationBadge, let durationText else { return published }
        guard let published else { return durationText }
        return "\(published) · \(durationText)"
    }

    private var durationText: String? {
        if let duration = video.player?.duration {
            return PleviFormatting.durationBadge(seconds: duration)
        }
        guard let str = video.player?.durationStr, !str.isEmpty else { return nil }
        return str
    }
}

#Preview("Card") {
    VideoRow(
        video: .previewVideo,
        layout: .card,
        showProgressBar: true,
        actions: .preview
    )
    .frame(width: 260)
    .padding()
}

#Preview("Row") {
    VStack {
        VideoRow(
            video: .previewVideo,
            layout: .row,
            actions: .preview
        )
        VideoRow(
            video: .previewVideo,
            layout: .row,
            position: 3,
            showProgressBar: true,
            actions: .preview
        )
    }
    .padding()
}
