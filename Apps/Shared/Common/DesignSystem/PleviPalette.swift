
import SwiftUI

struct PleviPalette {
    // MARK: - Shared across light/dark/tvOS

    /// Screen background.
    let canvas: Color
    /// Card/panel surface, sitting on `canvas`.
    let card: Color
    let cardShadow: Color
    /// Primary/highest-contrast text (titles).
    let ink: Color
    /// Lowest-emphasis text (eyebrow labels, captions).
    let secondary: Color
    /// Body/description text — between `ink` and `secondary` in emphasis.
    let body: Color
    /// The app's one accent color, identical on every platform/appearance.
    let accent: Color
    /// A light accent-tinted background (e.g. behind the "current" row).
    let accentTint: Color
    /// Duration-badge pill background — "Accent and duration badges
    /// unchanged" per the tvOS spec, so all three instances carry the same
    /// value; light/dark's own spec text agrees (`rgba(0,0,0,.72)`).
    let durationBadgeBg: Color

    // MARK: - tvOS-only

    let primaryContent: Color
    /// tvOS's un-focused metadata color — brightens to `secondary`
    /// (`#c7c7cf`) on focus, same mechanism as `primaryContent` above.
    let metadata: Color
    /// tvOS grid-card fill (`rgba(255,255,255,.05)`) — tvOS cards have no
    /// opaque white surface, just a faint tint over the dark canvas.
    let cardFillOnGrid: Color

    static let light = PleviPalette(
        canvas: Color(hex: "f2f1ed"),
        card: Color(hex: "ffffff"),
        cardShadow: Color.black.opacity(0.05),
        ink: Color(hex: "1a1a1a"),
        secondary: Color(hex: "6e6e73"),
        body: Color(hex: "48484d"),
        accent: Color(hex: "0a7cff"),
        accentTint: Color(hex: "eaf2fe"),
        durationBadgeBg: Color.black.opacity(0.72),
        primaryContent: Color(hex: "48484d"),
        metadata: Color(hex: "6e6e73"),
        cardFillOnGrid: Color(hex: "ffffff")
    )

    static let dark = PleviPalette(
        canvas: Color(hex: "0e0e10"),
        card: Color(hex: "16161a"),
        cardShadow: Color.black.opacity(0.05),
        ink: Color(hex: "f5f5f7"),
        secondary: Color(hex: "a1a1a8"),
        body: Color(hex: "c7c7cc"),
        accent: Color(hex: "0a7cff"),
        // Not spec'd for dark either — a low-opacity tint of the same
        // accent, since light's near-opaque `#eaf2fe` tint would read as a
        // pale rectangle punched into a dark canvas rather than a tint.
        accentTint: Color(hex: "0a7cff").opacity(0.18),
        durationBadgeBg: Color.black.opacity(0.72),
        primaryContent: Color(hex: "c7c7cc"),
        metadata: Color(hex: "a1a1a8"),
        cardFillOnGrid: Color(hex: "16161a")
    )

    static let tvOS = PleviPalette(
        canvas: Color(hex: "0e0e10"),
        // "panels `rgba(22,22,26,.82)`" — translucent, unlike light/dark's
        // opaque card surface.
        card: Color(hex: "16161a").opacity(0.82),
        // tvOS cards get no resting shadow at all (see `cardShadow`'s own
        // doc comment above) — this value is never read.
        cardShadow: .clear,
        ink: Color(hex: "ffffff"),
        secondary: Color(hex: "c7c7cf"),
        // Description/body text has no dedicated hex in the tvOS spec;
        // `primaryContent` (a row's own unfocused title color) is the
        // closest documented tier and reads correctly at the type floor.
        body: Color(hex: "e8e8ec"),
        accent: Color(hex: "0a7cff"),
        accentTint: Color(hex: "0a7cff").opacity(0.18),
        durationBadgeBg: Color.black.opacity(0.72),
        primaryContent: Color(hex: "e8e8ec"),
        metadata: Color(hex: "a1a1a8"),
        cardFillOnGrid: Color.white.opacity(0.05)
    )
}

enum PleviTheme {
    @MainActor static func palette(for colorScheme: ColorScheme) -> PleviPalette {
        #if os(tvOS)
        .tvOS
        #else
        colorScheme == .dark ? .dark : .light
        #endif
    }
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
