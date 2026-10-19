
#if os(iOS)
import SwiftUI
import PleviCore

struct OfflineRootView: View {
    let serverURL: URL
    let message: String

    @Environment(AuthStore.self) private var authStore
    @State private var path: [Route] = []
    @State private var showSSOSheet = false
    @State private var isRetrying = false
    @State private var isMessageExpanded = false

    var body: some View {
        NavigationStack(path: $path) {
            OfflineVideosView(navigate: { path.append($0) })
                .navigationDestination(for: Route.self) { route in
                    RouteDestinationView(route: route, navigate: { path.append($0) })
                }
                .safeAreaInset(edge: .top) { banner }
                // Everything below here is being served from disk — see
                // `OfflineShelfEnvironment`.
                .environment(\.isOfflineShelf, true)
        }
        // Reached only from the banner: an expired sign-in at a proxy in front of the server looks exactly like being offline, and Retry alone can never fix it.
        .sheet(isPresented: $showSSOSheet) {
            SSOLoginSheet(serverURL: authStore.browserSignInURL(fallback: serverURL), probe: { await APIGateProbe()($0) }) {
                Task { await retry() }
            }
        }
    }

    private func retry() async {
        isRetrying = true
        await authStore.retryConnection()
        isRetrying = false
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't Reach \(serverURL.host ?? "Server")")
                    .font(.subheadline.bold())
                // The whole reason, not two lines of it: this is the only place the app says what is
                // wrong, and it is long when something sits in front of the server. Tap to read it.
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isMessageExpanded ? nil : 2)
                    .onTapGesture { isMessageExpanded.toggle() }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Task { await retry() }
                } label: {
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry")
                    }
                }
                .font(.caption.bold())
                .disabled(isRetrying)
                Button("Sign in via browser") { showSSOSheet = true }
                    .font(.caption)
                Button("Sign Out", role: .destructive) { Task { await authStore.signOut() } }
                    .font(.caption)
            }
        }
        .padding(12)
        .background(.thinMaterial)
    }
}
#endif
