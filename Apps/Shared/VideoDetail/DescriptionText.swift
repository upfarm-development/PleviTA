
import SwiftUI
import UIKit

enum DescriptionLinkifier {
    static let seekURLScheme = "plevi-seek"

    /// `nil` return means "no seek timestamp" (a normal link tap or a tap
    /// outside any link).
    static func seekSeconds(from url: URL) -> Double? {
        guard url.scheme == seekURLScheme else { return nil }
        // Built as `plevi-seek:///<seconds>`; `host` is empty, `path` is
        // "/<seconds>".
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Double(raw)
    }

    static func attributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        applyLinks(&attributed, in: text)
        applyTimestamps(&attributed, in: text)
        return attributed
    }

    private static func applyLinks(_ attributed: inout AttributedString, in text: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let url = match.url,
                  let swiftRange = Range(match.range, in: text),
                  let attrRange = Range(swiftRange, in: attributed)
            else { continue }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = .accentColor
        }
    }

    /// `mm:ss` or `h:mm:ss`, word-bounded so it doesn't match inside a larger
    /// number or a URL's own path/port.
    private static let timestampRegex = try? NSRegularExpression(pattern: #"\b(?:\d{1,2}:)?[0-5]?\d:[0-5]\d\b"#)

    private static func applyTimestamps(_ attributed: inout AttributedString, in text: String) {
        guard let regex = timestampRegex else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let matchedText = nsText.substring(with: match.range)
            guard let seconds = parseTimestamp(matchedText),
                  let swiftRange = Range(match.range, in: text),
                  let attrRange = Range(swiftRange, in: attributed)
            else { continue }
            // Don't clobber a URL link this range is already part of (e.g. a
            // port number inside a URL happening to look like "12:34").
            if attributed[attrRange].link != nil { continue }
            attributed[attrRange].link = URL(string: "\(seekURLScheme):///\(Int(seconds))")
            attributed[attrRange].foregroundColor = .accentColor
            attributed[attrRange].underlineStyle = .single
        }
    }

    private static func parseTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        var seconds: Double = 0
        for part in parts { seconds = seconds * 60 + part }
        return seconds
    }
}

/// Collapsible description block: 4 lines by default with a "more"/"less" toggle, linkified URLs and timestamps.
struct DescriptionText: View {
    let text: String
    var onSeek: (Double) -> Void
    var maxCollapsedLines: Int? = nil

    @State private var isExpanded = false
    @State private var isTruncated = false

    private var collapsedLineLimit: Int { maxCollapsedLines ?? 4 }

    var body: some View {
        #if os(tvOS)
        let stackSpacing: CGFloat = 12
        #else
        let stackSpacing: CGFloat = 6
        #endif
        return VStack(alignment: .leading, spacing: stackSpacing) {
            Text(DescriptionLinkifier.attributedString(for: text))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .environment(\.openURL, OpenURLAction { url in
                    if let seconds = DescriptionLinkifier.seekSeconds(from: url) {
                        onSeek(seconds)
                        return .handled
                    }
                    return .systemAction
                })
                .background(TruncationDetector(text: text, isExpanded: isExpanded, collapsedLineLimit: collapsedLineLimit, isTruncated: $isTruncated))
                #if os(iOS)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    },
                    including: isExpanded ? .all : .subviews
                )
                #endif

            if isTruncated || isExpanded {
                let title = isExpanded ? "Show Less" : "Show More"
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    #if os(tvOS)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        // The gaps after the text count as the control, so the rail is one
                        // object rather than a word with dead space beside it.
                        .contentShape(Rectangle())
                        .tvFocusRing(cornerRadius: 10, scales: false)
                    #else
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    #endif
                }
                .pleviSelectableStyle()
            }
        }
    }
}

private struct TruncationDetector: View {
    let text: String
    let isExpanded: Bool
    let collapsedLineLimit: Int
    @Binding var isTruncated: Bool

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { measure(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, newWidth in measure(width: newWidth) }
        }
    }

    private func measure(width: CGFloat) {
        guard width > 0 else { return }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let lineHeight = font.lineHeight
        let renderedLines = Int((bounding.height / lineHeight).rounded(.up))
        isTruncated = renderedLines > collapsedLineLimit
    }
}
