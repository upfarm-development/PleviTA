
import SwiftUI

struct HeaderControlChip: ViewModifier {
    let palette: PleviPalette

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(palette.ink)
            .frame(width: 40, height: 40)
            .background(palette.card, in: Circle())
            .shadow(
                color: palette.cardShadow,
                radius: PleviMetrics.cardShadowRadius,
                x: PleviMetrics.cardShadowX,
                y: PleviMetrics.cardShadowY
            )
    }
}
