
import SwiftUI
import PleviCore

struct ChannelListRow: View {
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                // Same reasoning as `ChannelCard`: the `.frame` must
                // constrain `RemoteImage` itself, before `.aspectRatio(_:
                // contentMode: .fill)`/`.clipShape`.
                RemoteImage(path: channel.channelThumbUrl, maxPixelSize: 160)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                if isSubscribed {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, palette.accent)
                        .font(.caption)
                        .background(Circle().fill(.background))
                }
            }
            .frame(width: 52, height: 52)

            Text(channel.channelName ?? "Unknown channel")
                .pleviItemTitle()
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .tvFocusRing(cornerRadius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (channel.channelName ?? "Unknown channel") + (isSubscribed ? ", subscribed" : "")
        )
    }
}

#Preview {
    ChannelListRow(channel: .previewChannel)
        .padding()
}
