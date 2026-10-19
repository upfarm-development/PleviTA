
import SwiftUI

extension View {
    /// iOS/iPadOS: "30pt bold, tracking −0.03em (large title, left aligned)" — tracking computed as −0.03 × 30pt = −0.9pt.
    func pleviScreenTitle() -> some View {
        #if os(tvOS)
        self.font(.system(size: 30, weight: .semibold))
        #else
        self.font(.system(size: 30, weight: .bold)).tracking(-0.9)
        #endif
    }

    /// iOS/iPadOS: "14–15pt semibold" — 15pt chosen (top of the range, so it still reads clearly as a card-level heading next to 13.5pt body text).
    func pleviSectionHeading() -> some View {
        #if os(tvOS)
        self.font(.system(size: 30, weight: .semibold))
        #else
        self.font(.system(size: 15, weight: .semibold))
        #endif
    }

    /// iOS/iPadOS: "12.5–13.5pt medium" — 13pt chosen (midpoint). tvOS:
    /// "titles 24–27px medium" — 26pt chosen (midpoint).
    func pleviItemTitle() -> some View {
        #if os(tvOS)
        self.font(.system(size: 26, weight: .medium))
        #else
        self.font(.system(size: 13, weight: .medium))
        #endif
    }

    func pleviBody() -> some View {
        #if os(tvOS)
        self.font(.system(size: 20, weight: .regular))
        #else
        self.font(.system(size: 13.5, weight: .regular)).lineSpacing(4)
        #endif
    }

    /// iOS/iPadOS: "9.5–11pt semibold, uppercase, tracking 0.08em" — 10pt chosen (midpoint), tracking 0.08 × 10pt = 0.8pt.
    func pleviEyebrow() -> some View {
        #if os(tvOS)
        self.font(.system(size: 20, weight: .semibold)).tracking(1.6).textCase(.uppercase)
        #else
        self.font(.system(size: 10, weight: .semibold)).tracking(0.8).textCase(.uppercase)
        #endif
    }

    func pleviMono() -> some View {
        #if os(tvOS)
        self.font(.system(size: 21, weight: .regular, design: .monospaced))
        #else
        self.font(.system(size: 11.5, weight: .regular, design: .monospaced))
        #endif
    }
}
