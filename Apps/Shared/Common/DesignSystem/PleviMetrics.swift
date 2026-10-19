
import SwiftUI

enum PleviMetrics {
    static let insetPhone: CGFloat = 16
    /// Screen-edge inset, iPad.
    static let insetPad: CGFloat = 24
    static let insetTV: (horizontal: CGFloat, vertical: CGFloat) = (90, 65)

    #if os(tvOS)
    /// `TVSidebar`'s collapsed width — the small rounded pill of icons that sits on the left edge of every section root screen.
    static let tvSidebarRailWidth: CGFloat = 92
    static let insetTVLeadingRoot: CGFloat = 170
    #endif

    #if os(tvOS)
    static let tvShelfCardWidth: CGFloat = 399

    /// Room a shelf must leave inside its scroll view for a focused cell's lift.
    static let tvFocusScale: CGFloat = 1.10

    /// 24 at a focus scale of 1.10: a 399pt card grows ~40 points, half of it each way, plus
    /// a little for the shadow. Raised from 16 when the scale went up from 1.06 — these two
    /// numbers move together, and `TVFocusRingModifier.focusScale` says so at the other end.
    static let tvShelfFocusOverhang: CGFloat = 24

    /// Vertical room a focused shelf cell needs, for a shelf that cannot simply stop clipping.
    static let tvShelfLiftHeadroom: CGFloat = 40
    /// Gap between shelf cells, and the figure `tvShelfCardWidth` is derived against.
    static let tvShelfCardSpacing: CGFloat = 32
    #endif
    static let cardCornerRadius: CGFloat = 14
    static let cardShadowX: CGFloat = 0
    static let cardShadowY: CGFloat = 1
    static let cardShadowRadius: CGFloat = 2
    static let screenHeaderTop: CGFloat = 12

    /// The gap between a root section's in-content headline and whatever sits under it: Playlists' and Channels' filter chips, and Settings' `Form`.
    static let screenHeaderToControls: CGFloat = 16

    static let cardContentPadding: CGFloat = 16
}

extension View {
    /// A root section screen's own horizontal inset.
    @ViewBuilder
    func pleviRootHorizontalInset(_ inset: CGFloat? = nil) -> some View {
        #if os(tvOS)
        self.padding(.leading, PleviMetrics.insetTVLeadingRoot)
            .padding(.trailing, inset ?? PleviMetrics.insetTV.horizontal)
        #else
        if let inset {
            self.padding(.horizontal, inset)
        } else {
            self.padding(.horizontal)
        }
        #endif
    }

    func pleviCard() -> some View {
        modifier(PleviCardModifier())
    }
}

private struct PleviCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = PleviTheme.palette(for: colorScheme)
        let shape = RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous)
        // Two full, independent chains rather than one chain with the tail conditionally compiled.
        #if os(tvOS)
        // No resting shadow on tvOS — see this modifier's own doc comment above.
        content
            .background(palette.card, in: shape)
        #else
        content
            .background(palette.card)
            .clipShape(shape)
            .shadow(
                color: palette.cardShadow,
                radius: PleviMetrics.cardShadowRadius,
                x: PleviMetrics.cardShadowX,
                y: PleviMetrics.cardShadowY
            )
        #endif
    }
}
