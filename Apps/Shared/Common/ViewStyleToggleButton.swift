
import SwiftUI
import PleviCore

struct ViewStyleToggleButton: View {
    @Binding var viewStyle: ViewStyle

    var body: some View {
        Button {
            viewStyle = (viewStyle == .grid) ? .list : .grid
        } label: {
            Label(
                viewStyle == .grid ? "Switch to List" : "Switch to Grid",
                systemImage: viewStyle == .grid ? "list.bullet" : "square.grid.2x2"
            )
        }
    }
}
