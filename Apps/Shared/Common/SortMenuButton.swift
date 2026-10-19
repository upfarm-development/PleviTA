
import SwiftUI
import PleviCore

struct SortMenuButton<Field: CaseIterable & Hashable>: View where Field.AllCases: RandomAccessCollection {
    @Binding var field: Field
    @Binding var order: HomeSortOrder
    let fieldTitle: (Field) -> String

    var body: some View {
        Menu {
            Picker("Sort By", selection: $field) {
                ForEach(Field.allCases, id: \.self) { candidate in
                    Text(fieldTitle(candidate)).tag(candidate)
                }
            }
            Picker("Order", selection: $order) {
                Label("Ascending", systemImage: "arrow.up").tag(HomeSortOrder.asc)
                Label("Descending", systemImage: "arrow.down").tag(HomeSortOrder.desc)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
