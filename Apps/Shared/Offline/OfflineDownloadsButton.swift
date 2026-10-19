// Somewhere to watch a download happen.

#if os(iOS)
import SwiftUI
import PleviCore

struct OfflineDownloadsButton: View {
    @Environment(OfflineLibrary.self) private var offlineLibrary
    @State private var isShowingQueue = false

    /// Everything not finished — in flight or failed. A failure has to count, or the button
    /// disappears at the exact moment the user most needs to know something went wrong.
    private var unfinished: [OfflineLibrary.Entry] {
        offlineLibrary.entries.filter { $0.record.state != .complete }
    }

    var body: some View {
        // Present whenever anything is saved, not only while something is downloading: the sheet
        // is also where the saved videos are.
        if !offlineLibrary.entries.isEmpty {
            Button {
                isShowingQueue = true
            } label: {
                Label("Downloads", systemImage: glyphName)
                    .overlay(alignment: .topTrailing) {
                        // The count, not a spinner: "three left" is the thing worth knowing at
                        // a glance, and a spinner in a toolbar reads as the screen loading.
                        if unfinished.count > 1 {
                            Text("\(unfinished.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.tint, in: Capsule())
                                .foregroundStyle(.white)
                                .offset(x: 8, y: -6)
                        }
                    }
            }
            .sheet(isPresented: $isShowingQueue) {
                OfflineDownloadsSheet()
            }
        }
    }

    private var glyphName: String {
        if hasFailure { return "exclamationmark.arrow.circlepath" }
        return unfinished.isEmpty ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    private var hasFailure: Bool {
        unfinished.contains { $0.record.state == .failed }
    }
}
#endif
