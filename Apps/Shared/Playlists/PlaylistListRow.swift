
import SwiftUI
import PleviCore

struct PlaylistListRow: View {
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
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(path: playlist.playlistThumbnail, maxPixelSize: 320)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        DurationBadge(text: videoCountBadgeText)
                            .padding(4)
                    }

                if isCustom {
                    Text("Custom")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.playlistName ?? "Untitled playlist")
                    .pleviItemTitle()
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(playlist.playlistChannel ?? "Multiple channels")
                        .lineLimit(1)
                    if isSubscribed {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
                .pleviMono()
                .foregroundStyle(metadataColor)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: 8)
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

    /// See `PlaylistCard.swift`'s identical helper — `nil` renders no badge
    /// at all rather than a badge reading "videos" with no number.
    private var videoCountBadgeText: String? {
        guard let videoCount else { return nil }
        return "\(videoCount) video\(videoCount == 1 ? "" : "s")"
    }
}

#Preview {
    PlaylistListRow(playlist: .previewPlaylist)
        .padding()
}
