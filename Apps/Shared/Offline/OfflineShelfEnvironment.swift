
#if os(iOS)
import SwiftUI

private struct OfflineShelfKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside `OfflineRootView` — the app is showing what is on disk because the server
    /// cannot be reached, so anything that needs the network should be hidden rather than
    /// left to fail visibly.
    var isOfflineShelf: Bool {
        get { self[OfflineShelfKey.self] }
        set { self[OfflineShelfKey.self] = newValue }
    }
}
#endif
