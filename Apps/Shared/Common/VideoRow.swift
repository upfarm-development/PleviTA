
import SwiftUI
import PleviCore

struct VideoRow: View {
    enum Layout {
        /// The grid cell — today's `VideoCard` body.
        case card
        /// The full-width list row — today's `VideoListRow` body, with an
        /// optional leading `position` index for playlist detail.
        case row
        /// A playlist's "Large" view: the thumbnail across the full width of a card with the
        /// index, duration and watched badges on it, the title and date underneath.
        case largeCard
        /// The list view on iPhone and iPad — a playlist's, a channel's and Home's: a wide
        /// thumbnail with the duration and watched badges on it (and the index, where there is
        /// one), the title beside it.
        case wideRow
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
    /// The name of the channel that owns the playlist this row is shown in. The playlist
    /// layouts leave the channel off the row when it is this one, since it would repeat on
    /// every row, and name it only when it differs.
    var ownerName: String? = nil
    /// Every action this row offers, as one value — see VideoActions.swift for why
    /// one parameter and not six closures.
    var actions: VideoActions

    @Environment(VideoCache.self) private var videoCache
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
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
        .system(size: 21, weight: .medium).monospacedDigit()
        #else
        .system(size: 15, weight: .medium).monospacedDigit()
        #endif
    }

    var body: some View {
        Group {
            switch layout {
            case .card: cardBody
            case .row: rowBody
            case .largeCard: playlistLargeBody
            case .wideRow: playlistListBody
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
            .pleviItemMeta()
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
                .pleviItemMeta()
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

    // MARK: - Playlist layouts (iPhone/iPad)

    /// `Channel · date`, or just the date when the channel is the playlist's own owner.
    private var playlistMetaLine: String? {
        var parts: [String] = []
        if let name = video.channel?.channelName, name != ownerName { parts.append(name) }
        if let date = PleviFormatting.displayDate(from: video.published) { parts.append(date) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var playlistLargeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            playlistThumbnail(cornerRadius: 12, fixedSize: nil, maxPixelSize: 640)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title ?? "Untitled")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let playlistMetaLine {
                    Text(playlistMetaLine)
                        .pleviMono()
                        .foregroundStyle(metadataColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }

    /// A little larger on iPad, where the row has the width for it.
    private var playlistListThumbnailSize: CGSize {
        #if os(iOS)
        horizontalSizeClass == .regular ? CGSize(width: 184, height: 104) : CGSize(width: 136, height: 76)
        #else
        CGSize(width: 136, height: 76)
        #endif
    }

    private var playlistListBody: some View {
        HStack(alignment: .center, spacing: 12) {
            playlistThumbnail(cornerRadius: 10, fixedSize: playlistListThumbnailSize, maxPixelSize: 480)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let playlistMetaLine {
                    Text(playlistMetaLine)
                        .pleviMono()
                        .foregroundStyle(metadataColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }

    /// The thumbnail the two playlist layouts share. Every badge is an overlay, so none of them
    /// can claim space of its own — `thumbnail(...)`'s watched tick asks for infinite size and
    /// needed a fixed frame to stop it filling a scroll view.
    @ViewBuilder
    private func playlistThumbnail(cornerRadius: CGFloat, fixedSize: CGSize?, maxPixelSize: CGFloat) -> some View {
        let large = layout == .largeCard
        Group {
            if let fixedSize {
                RemoteImage(path: video.vidThumbUrl, maxPixelSize: maxPixelSize)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: fixedSize.width, height: fixedSize.height)
            } else {
                RemoteImage(path: video.vidThumbUrl, maxPixelSize: maxPixelSize)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let position {
                Text("\(position)")
                    .font(.system(size: large ? 12 : 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(large ? 8 : 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isWatched {
                Image(systemName: "checkmark")
                    .font(.system(size: large ? 12 : 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: large ? 22 : 18, height: large ? 22 : 18)
                    .background(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255), in: Circle())
                    .padding(large ? 8 : 6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            DurationBadge(text: durationText).padding(6)
        }
        #if os(iOS)
        // Bottom-leading here: the index badge has the top-leading corner.
        .overlay(alignment: .bottomLeading) {
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .font(large ? .title3 : .caption)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        #endif
        .overlay(alignment: .bottom) {
            if showProgressBar, let progress = video.player?.progress, progress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: proxy.size.width * CGFloat(min(max(progress / 100, 0), 1)))
                }
                .frame(height: 3)
            }
        }
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
