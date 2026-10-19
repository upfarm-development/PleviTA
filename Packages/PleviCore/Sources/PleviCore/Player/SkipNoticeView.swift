
#if os(iOS) || os(tvOS)
import SwiftUI

public struct SkipNoticeView: View {
    private let segment: SponsorSegment

    public init(segment: SponsorSegment) {
        self.segment = segment
    }

    public var body: some View {
        Label("Skipped sponsor", systemImage: "forward.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
            .foregroundStyle(.white)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            .id(segment.id)
    }
}
#endif
