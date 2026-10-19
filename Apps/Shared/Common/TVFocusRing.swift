import SwiftUI

private struct TVFocusRingModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    var cornerRadius: CGFloat
    /// Whether focus grows the content. True suits a card with gaps around
    /// it; false suits a full-width row, which has nowhere to grow into —
    /// see `tvFocusRing(cornerRadius:scales:)`.
    var scales: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
        if scales {
            content
                .scaleEffect(isFocused ? PleviMetrics.tvFocusScale : 1.0, anchor: .top)
                .shadow(color: .black.opacity(isFocused ? 0.75 : 0), radius: isFocused ? 30 : 0, x: 0, y: isFocused ? 24 : 0)
                .animation(.easeOut(duration: 0.2), value: isFocused)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.16 : 0))
                )
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }
        #else
        content
        #endif
    }
}

/// Renders a button as nothing but its own label.
private struct PleviBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    /// A tvOS-only focus indicator (border + slight lift) for custom card/row buttons.
    func tvFocusRing(cornerRadius: CGFloat = 10, scales: Bool = true) -> some View {
        modifier(TVFocusRingModifier(cornerRadius: cornerRadius, scales: scales))
    }

    func pleviSelectableStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(PleviBareButtonStyle())
        #else
        self.buttonStyle(.plain)
        #endif
    }
}

/// A `LazyVStack` on iOS/iPadOS, a plain `VStack` on tvOS.
struct TVOSEagerStack<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(tvOS)
        VStack(alignment: alignment, spacing: spacing, content: content)
        #else
        LazyVStack(alignment: alignment, spacing: spacing, content: content)
        #endif
    }
}
