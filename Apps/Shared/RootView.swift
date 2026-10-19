// Top-level content for both apps.

import SwiftUI
import PleviCore
#if os(iOS)
import UniformTypeIdentifiers
#endif

#if os(iOS)
private extension AppTheme {
    /// `nil` for `.system`, which is what `.preferredColorScheme` wants in
    /// order to hand the decision back to the OS rather than pinning either
    /// appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif

private struct TVMediaProxyKey: EnvironmentKey {
    static let defaultValue: LoopbackMediaProxy? = nil
}

extension EnvironmentValues {
    var tvOSMediaProxy: LoopbackMediaProxy? {
        get { self[TVMediaProxyKey.self] }
        set { self[TVMediaProxyKey.self] = newValue }
    }
}

#if os(iOS)
/// A plain `EnvironmentKey`, not `.environment(_:)`/`@Environment(Type.self)`.
private struct OfflineDownloaderKey: EnvironmentKey {
    static let defaultValue: OfflineDownloader? = nil
}

extension EnvironmentValues {
    var offlineDownloader: OfflineDownloader? {
        get { self[OfflineDownloaderKey.self] }
        set { self[OfflineDownloaderKey.self] = newValue }
    }
}
#endif

public struct RootView: View {
    @State private var appSettings = AppSettings(defaults: KeychainCredentialStore.sharedDefaults)
    @State private var authStore: AuthStore
    /// Owned here, above the login/shell switch, so neither that switch nor
    /// `AppShellView`'s own size-class branch can throw the user's place in
    /// the app away — see NavigationModel.swift.
    @State private var navigation = NavigationModel()
    #if os(iOS)
    /// Outlives the video screen so a Picture in Picture session does — see
    /// PlaybackSession.swift.
    @State private var playbackSession = PlaybackSession()
    @State private var offlineLibrary: OfflineLibrary
    @State private var offlineDownloader: OfflineDownloader
    @State private var offlinePlaybackLedger = OfflinePlaybackLedger(scope: "", defaults: KeychainCredentialStore.sharedDefaults)
    #endif
    #if os(tvOS)
    /// App-lifetime proxy for the fallback engine's tvOS media requests.
    @State private var mediaProxy = LoopbackMediaProxy()
    #endif
    /// One per app, shared by Home (which orders Continue Watching with it) and the playback controllers (which record into it).
    @State private var playbackHistory = PlaybackHistory(scope: "", defaults: KeychainCredentialStore.sharedDefaults)
    @State private var pinnedItems = PinnedItems(scope: "", defaults: KeychainCredentialStore.sharedDefaults)
    /// One per app, shared by every video row/card's long-press and "…" menu (Ignore/Delete/
    /// Delete and Ignore/Add to Playlist) — see VideoActions.swift.
    @State private var videoActions = VideoActionsCoordinator()
    /// Lets a video page open already drawn instead of blank — see `VideoCache`.
    @State private var videoCache = VideoCache()
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    public init(offlineLibrary: OfflineLibrary, offlineDownloader: OfflineDownloader) {
        let settings = AppSettings(defaults: KeychainCredentialStore.sharedDefaults)
        _appSettings = State(initialValue: settings)
        _offlineLibrary = State(initialValue: offlineLibrary)
        _offlineDownloader = State(initialValue: offlineDownloader)
        _authStore = State(initialValue: AuthStore(
            appSettings: settings,
            offlineImageBytesProvider: { path in offlineLibrary.localImageData(forPath: path) }
        ))
    }
    #else
    public init() {
        let settings = AppSettings(defaults: KeychainCredentialStore.sharedDefaults)
        _appSettings = State(initialValue: settings)
        _authStore = State(initialValue: AuthStore(appSettings: settings))
    }
    #endif

    public var body: some View {
        Group {
            switch authStore.state {
            case .checking:
                ProgressView("Connecting…")
                    .controlSize(.large)
            case .loggedOut:
                LoginView()
            case .loggedIn:
                AppShellView()
            case .connectionFailed(let serverURL, let message):
                #if os(iOS)
                if !offlineLibrary.entries.isEmpty {
                    OfflineRootView(serverURL: serverURL, message: message)
                } else {
                    ConnectionFailedView(serverURL: serverURL, message: message)
                }
                #else
                ConnectionFailedView(serverURL: serverURL, message: message)
                #endif
            }
        }
        .environment(authStore)
        .environment(appSettings)
        .environment(navigation)
        .environment(playbackHistory)
        .environment(pinnedItems)
        .environment(videoActions)
        .environment(videoCache)
        #if os(iOS)
        .environment(offlineLibrary)
        .environment(offlinePlaybackLedger)
        .environment(\.offlineDownloader, offlineDownloader)
        #endif
        // `TAClient` is an actor, so the server it talks to is read with an await rather than
        // used as the task's identity directly; the client's own identity is enough to re-run
        // this whenever sign-in swaps it.
        .task(id: authStore.client.map(ObjectIdentifier.init)) {
            videoActions.adopt(client: authStore.client, playbackHistory: playbackHistory)
            guard authStore.client != nil, let loginURL = authStore.loginServerURL() else { return }
            // The *stored login* address, not `client.serverURL` (which is whichever of local/remote the resolver picked).
            let syncScope = authStore.syncScope() ?? loginURL.absoluteString
            playbackHistory.adopt(scope: syncScope, legacyScope: loginURL.absoluteString)
            pinnedItems.adopt(scope: syncScope, legacyScope: loginURL.absoluteString)
            #if os(iOS)
            // Same scoping rule, same reason — see `ServerScope`'s own doc comment.
            await offlineLibrary.adopt(scope: loginURL.absoluteString)
            offlinePlaybackLedger.adopt(scope: loginURL.absoluteString)
            #endif
        }
        // The shared key follows the local and remote addresses, so an edit re-points it.
        .task(id: authStore.addressRevision) {
            guard authStore.client != nil, let loginURL = authStore.loginServerURL(),
                  let syncScope = authStore.syncScope() else { return }
            playbackHistory.adopt(scope: syncScope, legacyScope: loginURL.absoluteString)
            pinnedItems.adopt(scope: syncScope, legacyScope: loginURL.absoluteString)
        }
        #if os(iOS)
        .environment(playbackSession)
        .task(id: authStore.state) {
            guard case .loggedIn = authStore.state, let client = authStore.client else { return }
            await OfflineProgressSync.flush(ledger: offlinePlaybackLedger, client: client)
            await offlineDownloader.reconcileStuckDownloads(client: client, allowsCellular: appSettings.allowCellularDownloads)
            await OfflineMetadataSync.refresh(library: offlineLibrary, client: client)
        }
        .onChange(of: appSettings.allowCellularDownloads) { _, newValue in
            Task { await offlineDownloader.setAllowsCellular(newValue) }
        }
        .offlineCopyExporter(offlineLibrary)
        #endif
        #if os(tvOS)
        .environment(\.tvOSMediaProxy, mediaProxy)
        #endif
        // Applied here rather than in `PleviTAApp` because `appSettings` is owned by this view, and applied to the whole root so it reaches the window itself.
        #if os(iOS)
        .preferredColorScheme(appSettings.appTheme.preferredColorScheme)
        #endif
        .task {
            // Before anything else, so the launch banner and every system event from here on —
            // thermal changes, network changes, audio route changes — are in the playback log
            // even for a stutter that starts before the first video is opened.
            PlaybackMonitor.shared.installSystemObservers()
            // Restore before the session check so the shell, once it appears,
            // is already pointed at wherever the user was — rather than
            // rendering Home first and jumping.
            navigation.restore()
            await authStore.restoreSessionIfPossible()
        }
        // Persisted on every move rather than only on the way to the
        // background: a terminated app gets no further notice, and this is
        // two small values through JSONEncoder, not work worth batching.
        .onChange(of: navigation.selectedSection) { _, _ in navigation.persist() }
        .onChange(of: navigation.paths) { _, _ in navigation.persist() }
        .onChange(of: scenePhase) { _, newPhase in
            // Leaving the foreground re-stamps the saved place, so its age measures time since the user was last *in* the app rather than since they last navigated.
            if newPhase != .active { navigation.persist() }
            let session: String
            switch authStore.state {
            case .checking: session = "checking"
            case .loggedOut: session = "loggedOut"
            case .loggedIn: session = "loggedIn"
            case .connectionFailed: session = "connectionFailed"
            }
            PlaybackLog.shared.log("app", "scene \(newPhase) session=\(session)")
            guard newPhase == .active else { return }
            playbackHistory.refreshFromCloud()
            Task { await authStore.reresolveServerAddressIfNeeded() }
        }
    }
}

private struct ConnectionFailedView: View {
    let serverURL: URL
    let message: String

    @Environment(AuthStore.self) private var authStore
    #if os(iOS)
    @State private var showSSOSheet = false
    #endif
    @State private var isEditingAddresses = false
    @State private var localText = ""
    @State private var remoteText = ""
    @State private var addressError: String?

    /// Where "Sign in via browser" should go.
    private var ssoTargetURL: URL {
        authStore.browserSignInURL(fallback: serverURL)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Can't Reach Server")
                .font(.title2.bold())
            Text(serverURL.absoluteString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task { await authStore.retryConnection() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            addressEditor

            #if os(iOS)
            Button {
                showSSOSheet = true
            } label: {
                // Same 44pt tap-target reasoning as LoginView's own SSO
                // button — see its comment.
                Text("Sign in via browser")
                    .font(.footnote)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            #endif

            Button("Sign Out", role: .destructive) {
                Task { await authStore.signOut() }
            }
            // Flat red text is an iOS treatment.
            #if os(tvOS)
            .buttonStyle(.bordered)
            #else
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            #endif
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        #if os(iOS)
        .sheet(isPresented: $showSSOSheet) {
            SSOLoginSheet(serverURL: ssoTargetURL, probe: { await APIGateProbe()($0) }) {
                Task { await authStore.retryConnection() }
            }
        }
        #endif
    }

    @ViewBuilder
    private var addressEditor: some View {
        let hasRemote = authStore.remoteServerURL() != nil
        Button(isEditingAddresses ? "Hide addresses" : (hasRemote ? "Edit server addresses" : "Add a remote address")) {
            if !isEditingAddresses {
                localText = authStore.localServerURL()?.absoluteString ?? ""
                remoteText = authStore.remoteServerURL()?.absoluteString ?? ""
                addressError = nil
            }
            isEditingAddresses.toggle()
        }
        #if os(iOS)
        .font(.footnote)
        .padding(.vertical, 8)
        #endif

        if isEditingAddresses {
            VStack(spacing: 12) {
                addressField("Local address", text: $localText)
                addressField("Remote address", text: $remoteText)
                Text("Use the remote address for when you are away from home, for example myserver.example.com. Local is tried first; remote is used when it can't be reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let addressError {
                    Text(addressError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button("Save and Retry", action: saveAddresses)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 520)
        }
    }

    private func addressField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .textFieldStyle(.roundedBorder)
            #endif
            .autocorrectionDisabled()
    }

    /// Blank clears an address; anything else must parse to a URL with a host, the same rule
    /// Settings and the login screen use (`AuthStore.normalizedURL`, so a bare `host:port` works).
    private func saveAddresses() {
        func parse(_ text: String) -> (url: URL?, valid: Bool) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (nil, true) }
            let url = AuthStore.normalizedURL(from: text)
            return (url, url != nil)
        }
        let local = parse(localText)
        let remote = parse(remoteText)
        guard local.valid, remote.valid else {
            addressError = "That isn't a valid address. Try something like 192.168.1.50:8000 or myserver.example.com."
            return
        }
        addressError = nil
        authStore.setLocalServerURL(local.url)
        authStore.setRemoteServerURL(remote.url)
        isEditingAddresses = false
        Task { await authStore.retryConnection() }
    }
}

#Preview {
    #if os(iOS)
    let previewLibrary = OfflineLibrary(root: OfflineLibrary.defaultRoot())
    RootView(offlineLibrary: previewLibrary, offlineDownloader: OfflineDownloader(library: previewLibrary))
    #else
    RootView()
    #endif
}
