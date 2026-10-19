
import SwiftUI
import PleviCore

struct PlaylistCard: View {
    let playlist: Playlist

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }
    private var isSubscribed: Bool { playlist.playlistSubscribed == true }
    private var isCustom: Bool { playlist.playlistType == "custom" }
    private var videoCount: Int? { playlist.playlistEntries?.count }

    private var titleColor: Color {
        #if os(tvOS)
        isFocused ? palette.ink : palette.primaryContent
        #else
        palette.ink
        #endif
    }

    private var metadataColor: Color {
        #if os(tvOS)
        isFocused ? palette.secondary : palette.metadata
        #else
        palette.secondary
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(path: playlist.playlistThumbnail, maxPixelSize: 480)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        DurationBadge(text: videoCountBadgeText)
                            .padding(6)
                    }

                if isCustom {
                    Text("Custom")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }

            FixedLineText(text: playlist.playlistName ?? "Untitled playlist", lineLimit: 2, alignment: .leading)
                .pleviItemTitle()
                .foregroundStyle(titleColor)

            HStack(spacing: 6) {
                Text(playlist.playlistChannel ?? "Multiple channels")
                    .lineLimit(1)
                if isSubscribed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(palette.accent)
                }
                Spacer(minLength: 4)
            }
            .pleviMono()
            .foregroundStyle(metadataColor)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: PleviMetrics.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [playlist.playlistName ?? "Untitled playlist"]
        parts.append(playlist.playlistChannel ?? "Multiple channels")
        if isCustom { parts.append("custom playlist") }
        if isSubscribed { parts.append("subscribed") }
        if let videoCountBadgeText { parts.append(videoCountBadgeText) }
        return parts.joined(separator: ", ")
    }

    /// `DurationBadge`'s `text` — `nil` renders no badge at all (a playlist
    /// with no `playlistEntries` loaded), the same "nothing to show" default
    /// every other optional field in this card already falls back to.
    private var videoCountBadgeText: String? {
        guard let videoCount else { return nil }
        return "\(videoCount) video\(videoCount == 1 ? "" : "s")"
    }
}

#Preview {
    PlaylistCard(playlist: .previewPlaylist)
        .frame(width: 200)
        .padding()
}
