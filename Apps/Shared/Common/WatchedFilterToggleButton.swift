
import SwiftUI
import PleviCore

extension AppSettings {
    func watchedFilterBinding(_ scope: WatchedFilterScope) -> Binding<Bool> {
        Binding(
            get: { self.hideWatched(in: scope) },
            set: { self.setHideWatched($0, in: scope) }
        )
    }
}

struct WatchedFilterToggleButton: View {
    @Binding var hideWatched: Bool

    var body: some View {
        Button {
            hideWatched.toggle()
        } label: {
            Label(
                hideWatched ? "Show Watched" : "Hide Watched",
                systemImage: hideWatched ? "eye.slash" : "eye"
            )
        }
    }
}

#if os(tvOS)
/// tvOS's own shape for the same control.
struct TVWatchedFilterToggle: View {
    @Binding var hideWatched: Bool
    let palette: PleviPalette

    var body: some View {
        Button {
            hideWatched.toggle()
        } label: {
            // The same `Label` iOS builds, icon-only.
            Label(
                hideWatched ? "Show Watched" : "Hide Watched",
                systemImage: hideWatched ? "eye.slash" : "eye"
            )
            .labelStyle(.iconOnly)
            // The glyph is pinned rather than left to size the chip: `eye` and `eye.slash` are not the same height, so without this the capsule.
            .tvControlChip(palette, contentHeight: TVControlChip.captionLineHeight)
        }
        .pleviSelectableStyle()
    }
}
#endif

extension View {
    /// The "Mark All Watched" confirmation a playlist's and a channel's screen both ask.
    func markAllWatchedConfirmation(
        _ title: String,
        isPresented: Binding<Bool>,
        perform: @escaping () -> Void
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("Mark All Watched", role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        }
    }
}
