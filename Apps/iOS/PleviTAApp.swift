import SwiftUI

@main
struct PleviTAApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(offlineLibrary: appDelegate.offlineLibrary, offlineDownloader: appDelegate.offlineDownloader)
        }
    }
}
