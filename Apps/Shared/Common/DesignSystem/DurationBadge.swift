
import SwiftUI

/// A small pill overlay for a clock-style duration string (`PleviFormatting.clockDuration`), meant to sit `.bottomTrailing` over a video thumbnail.
struct DurationBadge: View {
    let text: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: Self.fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .background(
                    PleviTheme.palette(for: colorScheme).durationBadgeBg,
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                )
        }
    }

    #if os(tvOS)
    private static let fontSize: CGFloat = 16
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 3
    private static let cornerRadius: CGFloat = 6
    #else
    private static let fontSize: CGFloat = 10
    private static let horizontalPadding: CGFloat = 5
    private static let verticalPadding: CGFloat = 2
    private static let cornerRadius: CGFloat = 4
    #endif
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.gray.opacity(0.3)
            .frame(width: 240, height: 135)
        DurationBadge(text: "12:34")
            .padding(6)
    }
}
