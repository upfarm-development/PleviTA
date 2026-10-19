
import Foundation
import Network
import Observation

@Observable
@MainActor
public final class AuthStore {
    public struct SessionInfo: Equatable, Sendable {
        public var serverURL: URL
        public var username: String?
        public var version: String?
    }

    public enum ConnectionSource: Equatable, Sendable {
        case local
        case remote
        case configured
    }

    public enum State: Equatable, Sendable {
        /// Checking Keychain/UserDefaults for a stored credential at launch.
        case checking
        case loggedOut
        case loggedIn(SessionInfo)
        case connectionFailed(serverURL: URL, message: String)
    }

    public private(set) var state: State = .checking
    public var errorMessage: String?
    public var isBusy = false
    public private(set) var connectionSource: ConnectionSource = .configured

    private let credentialStore: CredentialStoring
    private let appSettings: AppSettings
    /// Injectable so `AuthStoreTests` can exercise real login/retry flows against `MockURLProtocol` instead of real networking.
    private let urlSession: URLSession?
    private let transientRetryDelayNanoseconds: UInt64
    private let offlineImageBytesProvider: (@Sendable (String) -> Data?)?
    public private(set) var client: TAClient?
    public private(set) var imageLoader: ImageLoader?
    /// Bumped whenever the local or remote address is saved, because what is shared between devices
    /// is keyed on them (`syncScope()`) and has to follow an edit.
    public private(set) var addressRevision = 0
    /// The on-disk artwork cache behind `imageLoader`, for this login's server. Exposed so Settings
    /// can show its size and clear it.
    public private(set) var artworkCache: ArtworkDiskCache?

    private func makeImageLoader(client: TAClient) -> ImageLoader {
        var cache: ArtworkDiskCache?
        if let loginURL = credentialStore.serverURL() {
            cache = ArtworkDiskCache(
                directory: ArtworkDiskCache.directory(forScope: loginURL.absoluteString),
                limitBytes: appSettings.artworkCacheLimitBytes
            )
        }
        artworkCache = cache
        return ImageLoader(client: client, localBytesProvider: offlineImageBytesProvider, diskCache: cache)
    }

    private var lastReresolveAt = Date.distantPast
    private static let minimumReresolveInterval: TimeInterval = 5
    private var pathMonitor: NWPathMonitor?

    public init(
        appSettings: AppSettings,
        // `.platformDefault` is `KeychainCredentialStore()` unchanged on iOS.
        credentialStore: CredentialStoring = KeychainCredentialStore.platformDefault,
        urlSession: URLSession? = nil,
        transientRetryDelayNanoseconds: UInt64 = 1_500_000_000,
        offlineImageBytesProvider: (@Sendable (String) -> Data?)? = nil
    ) {
        self.appSettings = appSettings
        self.credentialStore = credentialStore
        self.urlSession = urlSession
        self.transientRetryDelayNanoseconds = transientRetryDelayNanoseconds
        self.offlineImageBytesProvider = offlineImageBytesProvider
    }

    /// Called once at app launch.
    public func restoreSessionIfPossible() async {
        guard let storedServerURL = credentialStore.serverURL(),
              credentialStore.token() != nil || credentialStore.sessionCredential() != nil
        else {
            state = .loggedOut
            return
        }
        startPathMonitoringIfNeeded()
        adoptLoginAddressAsConnectionAddress(storedServerURL, isFreshSignIn: false)

        let resolved = await resolveServerAddress(loginServerURL: storedServerURL)
        let client = TAClient(serverURL: resolved.url, credentialStore: credentialStore, urlSession: urlSession)
        self.client = client
        self.imageLoader = makeImageLoader(client: client)
        connectionSource = resolved.source
        lastReresolveAt = Date()
        do {
            let ping = try await client.ping()
            state = .loggedIn(SessionInfo(serverURL: resolved.url, username: credentialStore.displayUsername(), version: ping.version))
        } catch let error as TAError where error.isUnauthorized {
            // The credential itself was rejected (revoked token, expired
            // session) — drop back to the login screen rather than getting
            // stuck retrying something that can never succeed.
            credentialStore.clearAll()
            self.client = nil
            self.imageLoader = nil
            state = .loggedOut
        } catch {
            // Any other failure (server unreachable, 5xx, a decode error, …) says nothing about whether this credential is still good.
            state = .connectionFailed(serverURL: resolved.url, message: Self.message(for: error))
        }
    }

    public func retryConnection() async {
        guard case .connectionFailed(let failedServerURL, _) = state, let client else {
            await restoreSessionIfPossible()
            return
        }
        let loginServerURL = credentialStore.serverURL() ?? failedServerURL
        let resolved = await resolveServerAddress(loginServerURL: loginServerURL)
        if await resolved.url != client.currentServerURL() {
            await client.updateServerURL(resolved.url)
        }
        connectionSource = resolved.source
        lastReresolveAt = Date()
        do {
            let ping = try await client.ping()
            state = .loggedIn(SessionInfo(serverURL: resolved.url, username: credentialStore.displayUsername(), version: ping.version))
        } catch let error as TAError where error.isUnauthorized {
            credentialStore.clearAll()
            self.client = nil
            self.imageLoader = nil
            state = .loggedOut
        } catch {
            state = .connectionFailed(serverURL: resolved.url, message: Self.message(for: error))
        }
    }

    public func reresolveServerAddressIfNeeded(force: Bool = false) async {
        guard case .loggedIn(let session) = state, let client else { return }
        guard credentialStore.localServerURL() != nil || credentialStore.remoteServerURL() != nil else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastReresolveAt) >= Self.minimumReresolveInterval else { return }
        lastReresolveAt = now

        let loginServerURL = credentialStore.serverURL() ?? session.serverURL
        let resolved = await resolveServerAddress(loginServerURL: loginServerURL)
        connectionSource = resolved.source
        guard await resolved.url != client.currentServerURL() else { return }
        await client.updateServerURL(resolved.url)
        state = .loggedIn(SessionInfo(serverURL: resolved.url, username: session.username, version: session.version))
    }

    // MARK: - Connection settings

    /// The address the user actually signed in with, as stored — *not* whichever of local/remote `resolveServerAddress` picked for the live connection.
    public func loginServerURL() -> URL? { credentialStore.serverURL() }

    public func localServerURL() -> URL? { credentialStore.localServerURL() }
    public func setLocalServerURL(_ url: URL?) {
        credentialStore.setLocalServerURL(url)
        addressRevision += 1
    }

    public func remoteServerURL() -> URL? { credentialStore.remoteServerURL() }

    /// Where "Sign in via browser" should go.
    public func browserSignInURL(fallback: URL) -> URL {
        credentialStore.remoteServerURL() ?? credentialStore.localServerURL() ?? fallback
    }
    public func setRemoteServerURL(_ url: URL?) {
        credentialStore.setRemoteServerURL(url)
        addressRevision += 1
    }

    /// The key for what syncs between this user's devices; see `ServerScope.syncScope`.
    public func syncScope() -> String? { credentialStore.syncScope() }

    public func connectionMode() -> ConnectionMode { credentialStore.connectionMode() }
    public func setConnectionMode(_ mode: ConnectionMode) { credentialStore.setConnectionMode(mode) }

    /// A passthrough for the same reason as the settings above: `AuthStore` stays the one owner of the credential store.
    private func adoptLoginAddressAsConnectionAddress(_ url: URL, isFreshSignIn: Bool) {
        if isFreshSignIn { discardConnectionAddressesIfServerChanged(loginServerURL: url) }
        switch ServerAddressClassifier.classify(url) {
        case .local:
            guard credentialStore.localServerURL() == nil else { return }
            credentialStore.setLocalServerURL(url)
        case .remote:
            guard credentialStore.remoteServerURL() == nil else { return }
            credentialStore.setRemoteServerURL(url)
        case .indeterminate:
            break
        }
    }

    private func discardConnectionAddressesIfServerChanged(loginServerURL url: URL) {
        let local = credentialStore.localServerURL()
        let remote = credentialStore.remoteServerURL()
        guard local != nil || remote != nil else { return }
        let host = url.host?.lowercased()
        let matchesStoredServer = [local, remote].contains { $0?.host?.lowercased() == host }
        guard !matchesStoredServer else { return }
        credentialStore.setLocalServerURL(nil)
        credentialStore.setRemoteServerURL(nil)
    }

    public func canReachServer(_ url: URL, timeout: TimeInterval = 8) async -> Bool {
        await ServerReachabilityProbe(credentialStore: credentialStore, timeout: timeout)(url)
    }

    private func resolveServerAddress(loginServerURL: URL) async -> (url: URL, source: ConnectionSource) {
        let local = credentialStore.localServerURL()
        let remote = credentialStore.remoteServerURL()
        guard local != nil || remote != nil else {
            return (loginServerURL, .configured)
        }
        let mode = credentialStore.connectionMode()
        let probe = ServerReachabilityProbe(credentialStore: credentialStore)
        let resolvedURL = await ServerAddressResolver.resolve(
            local: local,
            remote: remote,
            mode: mode,
            loginServerURL: loginServerURL,
            probe: probe.callAsFunction
        ) ?? loginServerURL

        let source: ConnectionSource
        if let local, resolvedURL == local {
            source = .local
        } else if let remote, resolvedURL == remote {
            source = .remote
        } else {
            source = .configured
        }
        return (resolvedURL, source)
    }

    private func startPathMonitoringIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.reresolveServerAddressIfNeeded()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.plevi.ta.pathmonitor"))
        pathMonitor = monitor
    }

    public func loginWithPassword(serverURLText: String, username: String, password: String) async {
        errorMessage = nil
        guard let url = Self.normalizedURL(from: serverURLText) else {
            errorMessage = TAError.invalidServerURL.errorDescription
            return
        }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = "Enter a username and password."
            return
        }

        isBusy = true
        defer { isBusy = false }

        let client = TAClient(serverURL: url, credentialStore: credentialStore, urlSession: urlSession)
        do {
            _ = try await retryingOnTransientNetworkError(serverURL: url) {
                try await client.login(username: trimmedUsername, password: password)
            }
            credentialStore.setServerURL(url)
            credentialStore.setDisplayUsername(trimmedUsername)
            self.client = client
            self.imageLoader = makeImageLoader(client: client)
            await finishLogin(client: client, serverURL: url)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func loginWithToken(serverURLText: String, token: String) async {
        errorMessage = nil
        guard let url = Self.normalizedURL(from: serverURLText) else {
            errorMessage = TAError.invalidServerURL.errorDescription
            return
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            errorMessage = "Enter a token."
            return
        }

        isBusy = true
        defer { isBusy = false }

        let client = TAClient(serverURL: url, credentialStore: credentialStore, urlSession: urlSession)
        do {
            let ping = try await retryingOnTransientNetworkError(serverURL: url) {
                try await client.validateToken(trimmedToken)
            }
            credentialStore.setToken(trimmedToken)
            credentialStore.setSessionCredential(nil)
            credentialStore.setServerURL(url)
            self.client = client
            self.imageLoader = makeImageLoader(client: client)
            await finishLogin(client: client, serverURL: url, existingPing: ping)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func signOut() async {
        if let client {
            await client.logout()
        }
        credentialStore.clearAll()
        appSettings.resetServerSeed()
        client = nil
        imageLoader = nil
        artworkCache = nil
        errorMessage = nil
        state = .loggedOut
    }

    // MARK: - Helpers

    private func finishLogin(client: TAClient, serverURL: URL, existingPing: PingResponse? = nil) async {
        startPathMonitoringIfNeeded()
        adoptLoginAddressAsConnectionAddress(serverURL, isFreshSignIn: true)
        let ping: PingResponse
        if let existingPing {
            ping = existingPing
        } else if let fetched = try? await client.ping() {
            ping = fetched
        } else {
            ping = PingResponse(response: nil, user: nil, version: nil, taUpdate: nil)
        }

        if let config = try? await client.fetchUserConfig() {
            appSettings.seedFromServerIfNeeded(config)
        }

        var username = credentialStore.displayUsername()
        if username == nil, let account = try? await client.account(), let accountUsername = account.username {
            username = accountUsername
            credentialStore.setDisplayUsername(accountUsername)
        }

        state = .loggedIn(SessionInfo(serverURL: serverURL, username: username, version: ping.version))
    }

    private static func message(for error: Error) -> String {
        (error as? TAError)?.errorDescription ?? error.localizedDescription
    }

    private func retryingOnTransientNetworkError<T>(
        serverURL: URL,
        _ operation: () async throws -> T
    ) async throws -> T {
        let retries = ServerAddressClassifier.classify(serverURL) == .local ? 4 : 1
        for attempt in 0..<retries {
            do {
                return try await operation()
            } catch TAError.network {
                // Back off further each round: ~1.5s, 3s, 4.5s, 6s.
                try? await Task.sleep(nanoseconds: transientRetryDelayNanoseconds * UInt64(attempt + 1))
            }
        }
        // Whatever this last attempt throws is what the user sees.
        return try await operation()
    }

    public nonisolated static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }
}
