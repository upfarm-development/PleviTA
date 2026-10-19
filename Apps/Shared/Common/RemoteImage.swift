
import SwiftUI
import PleviCore

struct RemoteImage: View {
    let path: String?
    var maxPixelSize: CGFloat = 480
    /// Called once when a *real* (non-nil, non-empty) `path` fails to load — as opposed to still loading, or there being no path at all.
    var onLoadFailed: (() -> Void)? = nil

    @Environment(AuthStore.self) private var authStore
    @State private var cgImage: CGImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            if let cgImage {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard let path, !path.isEmpty, let loader = authStore.imageLoader else {
            cgImage = nil
            return
        }
        do {
            let image = try await loader.image(forPath: path, maxPixelSize: maxPixelSize)
            if !Task.isCancelled {
                cgImage = image
            }
        } catch {
            if !Task.isCancelled {
                onLoadFailed?()
            }
        }
    }
}
