import SwiftUI

struct FixedLineText: View {
    let text: String
    let lineLimit: Int
    var alignment: TextAlignment = .leading

    var body: some View {
        ZStack(alignment: boxAlignment) {
            Text(placeholder)
                .lineLimit(lineLimit)
                .hidden()
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(lineLimit)
                .multilineTextAlignment(alignment)
        }
        .frame(maxWidth: .infinity, alignment: boxAlignment)
    }

    /// `lineLimit` copies of a non-empty placeholder glyph, joined by literal newlines.
    private var placeholder: String {
        Array(repeating: "Wg", count: max(lineLimit, 1)).joined(separator: "\n")
    }

    private var boxAlignment: Alignment {
        switch alignment {
        case .trailing: .topTrailing
        case .center: .top
        default: .topLeading
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 20) {
            FixedLineText(text: "A short title", lineLimit: 2)
                .frame(width: 140)
                .background(.yellow.opacity(0.2))
            FixedLineText(text: "A much longer title that wraps to two full lines", lineLimit: 2)
                .frame(width: 140)
                .background(.yellow.opacity(0.2))
        }
        .font(.subheadline.weight(.medium))
    }
    .padding()
}
