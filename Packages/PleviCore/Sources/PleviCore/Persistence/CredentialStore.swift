
import Foundation

/// Snapshot of an active non-admin session login: the CSRF token value needed on non-GET requests, plus the username for display.
public struct SessionCredential: Sendable, Equatable, Codable {
    public var csrfToken: String
    public var username: String?

    public init(csrfToken: String, username: String?) {
        self.csrfToken = csrfToken
        self.username = username
    }
}

public enum ConnectionMode: String, CaseIterable, Sendable, Codable {
    case automatic
    case alwaysLocal
    case alwaysRemote

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .alwaysLocal: return "Always Local"
        case .alwaysRemote: return "Always Remote"
        }
    }
}

public protocol CredentialStoring: Sendable {
    func serverURL() -> URL?
    func setServerURL(_ url: URL?)

    func localServerURL() -> URL?
    func setLocalServerURL(_ url: URL?)

    func remoteServerURL() -> URL?
    func setRemoteServerURL(_ url: URL?)

    /// Defaults to `.automatic` when never explicitly set.
    func connectionMode() -> ConnectionMode
    func setConnectionMode(_ mode: ConnectionMode)

    func token() -> String?
    func setToken(_ token: String?)

    func sessionCredential() -> SessionCredential?
    func setSessionCredential(_ credential: SessionCredential?)

    /// Username to display in Settings, independent of which auth mode is
    /// active (set from the login form even on the token-fetch success path,
    /// where the token response itself carries no username).
    func displayUsername() -> String?
    func setDisplayUsername(_ username: String?)

    /// Clears every stored credential (server URL, token, session, display name) as part of sign-out.
    func clearAll()
}

/// Keychain + UserDefaults backed implementation used by both apps.
public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let keychain: KeychainStore
    private let defaults: UserDefaults

    private enum Key {
        static let serverURL = "com.plevi.ta.serverURL"
        static let localServerURL = "com.plevi.ta.localServerURL"
        static let remoteServerURL = "com.plevi.ta.remoteServerURL"
        static let connectionMode = "com.plevi.ta.connectionMode"
        static let token = "token"
        static let sessionCsrf = "sessionCsrf"
        static let sessionUsername = "sessionUsername"
        static let displayUsername = "displayUsername"
    }

    public init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }

    public func serverURL() -> URL? {
        guard let string = defaults.string(forKey: Key.serverURL) else { return nil }
        return URL(string: string)
    }

    public func setServerURL(_ url: URL?) {
        if let url {
            defaults.set(url.absoluteString, forKey: Key.serverURL)
        } else {
            defaults.removeObject(forKey: Key.serverURL)
        }
    }

    public func localServerURL() -> URL? {
        guard let string = defaults.string(forKey: Key.localServerURL) else { return nil }
        return URL(string: string)
    }

    public func setLocalServerURL(_ url: URL?) {
        if let url {
            defaults.set(url.absoluteString, forKey: Key.localServerURL)
        } else {
            defaults.removeObject(forKey: Key.localServerURL)
        }
    }

    public func remoteServerURL() -> URL? {
        guard let string = defaults.string(forKey: Key.remoteServerURL) else { return nil }
        return URL(string: string)
    }

    public func setRemoteServerURL(_ url: URL?) {
        if let url {
            defaults.set(url.absoluteString, forKey: Key.remoteServerURL)
        } else {
            defaults.removeObject(forKey: Key.remoteServerURL)
        }
    }

    public func connectionMode() -> ConnectionMode {
        guard let raw = defaults.string(forKey: Key.connectionMode) else { return .automatic }
        return ConnectionMode(rawValue: raw) ?? .automatic
    }

    public func setConnectionMode(_ mode: ConnectionMode) {
        defaults.set(mode.rawValue, forKey: Key.connectionMode)
    }

    public func token() -> String? {
        keychain.get(forKey: Key.token)
    }

    public func setToken(_ token: String?) {
        if let token {
            keychain.set(token, forKey: Key.token)
        } else {
            keychain.delete(forKey: Key.token)
        }
    }

    public func sessionCredential() -> SessionCredential? {
        guard let csrf = keychain.get(forKey: Key.sessionCsrf) else { return nil }
        let username = keychain.get(forKey: Key.sessionUsername)
        return SessionCredential(csrfToken: csrf, username: username)
    }

    public func setSessionCredential(_ credential: SessionCredential?) {
        if let credential {
            keychain.set(credential.csrfToken, forKey: Key.sessionCsrf)
            if let username = credential.username {
                keychain.set(username, forKey: Key.sessionUsername)
            } else {
                keychain.delete(forKey: Key.sessionUsername)
            }
        } else {
            keychain.delete(forKey: Key.sessionCsrf)
            keychain.delete(forKey: Key.sessionUsername)
        }
    }

    public func displayUsername() -> String? {
        keychain.get(forKey: Key.displayUsername)
    }

    public func setDisplayUsername(_ username: String?) {
        if let username {
            keychain.set(username, forKey: Key.displayUsername)
        } else {
            keychain.delete(forKey: Key.displayUsername)
        }
    }

    public func clearAll() {
        setServerURL(nil)
        setToken(nil)
        setSessionCredential(nil)
        setDisplayUsername(nil)
    }
}

// MARK: - tvOS Top Shelf sharing

extension KeychainCredentialStore {
    /// The store `AuthStore`'s own default parameter now resolves to.
    public static var platformDefault: KeychainCredentialStore {
        #if os(tvOS)
        return KeychainCredentialStore(
            keychain: KeychainStore(accessGroup: sharedAccessGroup),
            defaults: sharedDefaults
        )
        #else
        return KeychainCredentialStore()
        #endif
    }

    /// The `UserDefaults` suite the main app and `PleviTA-TopShelf` both need to agree on.
    public static var sharedDefaults: UserDefaults {
        #if os(tvOS)
        guard let suite = UserDefaults(suiteName: appGroupIdentifier) else { return .standard }
        SharedSuiteMigration.run()
        return suite
        #else
        .standard
        #endif
    }

    #if os(tvOS)
    /// App Group identifiers are literal, developer-chosen strings (unlike a Keychain access group, never Team-ID-prefixed).
    public static let appGroupIdentifier = "group.com.plevi.ta"

    private static var sharedAccessGroup: String? {
        guard let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String, !prefix.isEmpty else {
            return nil
        }
        return prefix + "com.plevi.ta.shared"
    }
    #endif
}

/// In-memory implementation for unit tests and SwiftUI previews.
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var storedServerURL: URL?
    private var storedLocalServerURL: URL?
    private var storedRemoteServerURL: URL?
    private var storedConnectionMode: ConnectionMode = .automatic
    private var storedToken: String?
    private var storedSession: SessionCredential?
    private var storedDisplayUsername: String?

    public init() {}

    public func serverURL() -> URL? { storedServerURL }
    public func setServerURL(_ url: URL?) { storedServerURL = url }

    public func localServerURL() -> URL? { storedLocalServerURL }
    public func setLocalServerURL(_ url: URL?) { storedLocalServerURL = url }

    public func remoteServerURL() -> URL? { storedRemoteServerURL }
    public func setRemoteServerURL(_ url: URL?) { storedRemoteServerURL = url }

    public func connectionMode() -> ConnectionMode { storedConnectionMode }
    public func setConnectionMode(_ mode: ConnectionMode) { storedConnectionMode = mode }

    public func token() -> String? { storedToken }
    public func setToken(_ token: String?) { storedToken = token }

    public func sessionCredential() -> SessionCredential? { storedSession }
    public func setSessionCredential(_ credential: SessionCredential?) { storedSession = credential }

    public func displayUsername() -> String? { storedDisplayUsername }
    public func setDisplayUsername(_ username: String?) { storedDisplayUsername = username }

    public func clearAll() {
        storedServerURL = nil
        storedToken = nil
        storedSession = nil
        storedDisplayUsername = nil
    }
}

#if os(tvOS)
/// Copies what the app persisted to `UserDefaults.standard` into the App Group suite, once.
private enum SharedSuiteMigration {
    private static let migratedFlag = "com.plevi.ta.migratedToAppGroupSuite"
    private static let migratedPrefixes = ["settings.", "playbackHistory.", "com.plevi.ta."]

    private static let hasRun: Bool = {
        guard let suite = UserDefaults(suiteName: KeychainCredentialStore.appGroupIdentifier),
              !suite.bool(forKey: migratedFlag) else { return true }
        for (key, value) in UserDefaults.standard.dictionaryRepresentation()
        where migratedPrefixes.contains(where: key.hasPrefix) && suite.object(forKey: key) == nil {
            suite.set(value, forKey: key)
        }
        suite.set(true, forKey: migratedFlag)
        return true
    }()

    static func run() { _ = hasRun }
}
#endif
