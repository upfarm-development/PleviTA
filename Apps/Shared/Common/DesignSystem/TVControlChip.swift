
import SwiftUI
import PleviCore

#if os(tvOS)
/// The resting appearance of an in-content control on tvOS: a filled capsule that reads as a button before focus reaches it.
struct TVControlChip: ViewModifier {
    /// The chip draws its own focus appearance rather than delegating to `tvFocusRing`, because neither of that modifier's two modes suits a capsule.
    @Environment(\.isFocused) private var isFocused
    let palette: PleviPalette
    /// Pins the label's height instead of letting the label set it. `nil` keeps the
    /// intrinsic sizing every caption chip has always had — see `captionLineHeight`.
    var contentHeight: CGFloat?

    /// The text line box at this chip's own font, and the height an *icon* chip should pin itself to so it matches the caption chips beside it.
    static let captionLineHeight: CGFloat = 26

    /// Focus inverts the chip: the capsule takes `ink` and the label takes `canvas`.
    func body(content: Content) -> some View {
        content
            // Matches `ChannelDetailView.actionRowFont` and `actionChipPadding`, so a sort
            // control and the tab chip next to it are the same object at the same size.
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isFocused ? palette.canvas : palette.ink)
            // `nil` is a no-op, so caption chips keep sizing themselves exactly as before.
            .frame(height: contentHeight)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Capsule().fill(isFocused ? palette.ink : palette.cardFillOnGrid))
            // Same lift and curve as `tvFocusRing`, kept in step with it by eye rather than by constant.
            .scaleEffect(isFocused ? PleviMetrics.tvFocusScale : 1.0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    /// `contentHeight` pins the label's height. Pass `TVControlChip.captionLineHeight` for a
    /// chip whose label is a glyph that changes between states; leave it off for a caption,
    /// whose own text already holds one height. See `captionLineHeight` for the report.
    func tvControlChip(_ palette: PleviPalette, contentHeight: CGFloat? = nil) -> some View {
        modifier(TVControlChip(palette: palette, contentHeight: contentHeight))
    }
}
#endif
