
import SwiftUI
import WebKit
import PleviCore

struct SSOLoginSheet: View {
    /// The server the proxy is fronting — whatever is typed in the login
    /// screen's Server field, or the address a logged-in session was using
    /// when it started failing.
    let serverURL: URL
    /// Deliberately not `AuthStore.canReachServer`, which needs a Tube Archivist credential and so always failed here on a first sign-in.
    let probe: (URL) async -> Bool
    /// Called once `/api/ping/` comes back from Tube Archivist rather than
    /// from the gate, right before this sheet dismisses.
    var onAuthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didAuthenticate = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                SSOWebView(
                    serverURL: serverURL,
                    probe: probe,
                    onAuthenticated: handleAuthenticated,
                    onLoadingChanged: { isLoading = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading && !didAuthenticate {
                    // A remote IdP page over a WAN link can take a moment,
                    // and WKWebView renders plain white until it has
                    // something — without this the sheet looks broken.
                    ProgressView()
                        .controlSize(.large)
                }

                if didAuthenticate {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("Server reachable")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle(serverURL.host ?? "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleAuthenticated() {
        guard !didAuthenticate else { return }
        didAuthenticate = true
        onAuthenticated()
        Task {
            // Long enough to actually register. A server that needs no SSO
            // at all succeeds on the very first navigation, and dismissing
            // immediately there just looks like the button did nothing.
            try? await Task.sleep(for: .milliseconds(1200))
            dismiss()
        }
    }
}

/// `WKWebView` wrapper that, after every completed navigation, hands the web
/// view's cookies to `HTTPCookieStorage.shared` and then asks the server
/// whether the app can now reach it.
private struct SSOWebView: UIViewRepresentable {
    let serverURL: URL
    let probe: (URL) async -> Bool
    var onAuthenticated: () -> Void
    var onLoadingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            serverURL: serverURL,
            probe: probe,
            onAuthenticated: onAuthenticated,
            onLoadingChanged: onLoadingChanged
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The default (persistent) data store, not a non-persistent one: the
        // proxy session should survive the sheet being closed and reopened,
        // the same way it survives in a real browser.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Loading the server root rather than /api/ping/ so the proxy's redirect to its login page happens the way it would in a browser.
        webView.load(URLRequest(url: serverURL, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let serverURL: URL
        private let probe: (URL) async -> Bool
        private let onAuthenticated: () -> Void
        private let onLoadingChanged: (Bool) -> Void
        private var hasSucceeded = false

        init(
            serverURL: URL,
            probe: @escaping (URL) async -> Bool,
            onAuthenticated: @escaping () -> Void,
            onLoadingChanged: @escaping (Bool) -> Void
        ) {
            self.serverURL = serverURL
            self.probe = probe
            self.onAuthenticated = onAuthenticated
            self.onLoadingChanged = onLoadingChanged
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
            guard !hasSucceeded else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            Task { @MainActor in
                let cookies = await cookieStore.allCookies()
                SSOCookieBridge.adopt(cookies, for: serverURL)

                guard await probe(serverURL), !hasSucceeded else { return }
                hasSucceeded = true
                onAuthenticated()
            }
        }
    }
}
