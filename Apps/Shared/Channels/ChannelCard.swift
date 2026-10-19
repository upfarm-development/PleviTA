
import SwiftUI
import PleviCore

struct ChannelCard: View {
    let channel: Channel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }
    private var isSubscribed: Bool { channel.channelSubscribed == true }

    private var titleColor: Color {
        #if os(tvOS)
        isFocused ? palette.ink : palette.primaryContent
        #else
        palette.ink
        #endif
    }

    private var avatarSize: CGFloat {
        #if os(tvOS)
        118
        #else
        72
        #endif
    }

    private var avatarMaxPixelSize: CGFloat {
        #if os(tvOS)
        320
        #else
        220
        #endif
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        14
        #endif
    }

    /// See this file's own doc comment: the grid-card fill token, not
    /// `.pleviCard()`'s panel token.
    private var cardFillColor: Color {
        #if os(tvOS)
        // A lighter grey while focused, so the focused channel is easy to pick out of the grid.
        isFocused ? Color.white.opacity(0.16) : palette.cardFillOnGrid
        #else
        palette.card
        #endif
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(path: channel.channelThumbUrl, maxPixelSize: avatarMaxPixelSize)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())

                if isSubscribed {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, palette.accent)
                        .font(.title3)
                        .background(Circle().fill(.background))
                }
            }
            .frame(width: avatarSize, height: avatarSize)

            FixedLineText(text: channel.channelName ?? "Unknown channel", lineLimit: 2, alignment: .center)
                .pleviItemTitle()
                .foregroundStyle(titleColor)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity)
        .background(cardFillColor)
        .clipShape(RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous))
        #if os(iOS)
        .shadow(
            color: palette.cardShadow,
            radius: PleviMetrics.cardShadowRadius,
            x: PleviMetrics.cardShadowX,
            y: PleviMetrics.cardShadowY
        )
        #endif
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: PleviMetrics.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (channel.channelName ?? "Unknown channel") + (isSubscribed ? ", subscribed" : "")
        )
    }
}

#Preview {
    ChannelCard(channel: .previewChannel)
        .frame(width: 160)
        .padding()
}
