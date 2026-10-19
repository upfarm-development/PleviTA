// What the download queue needs in order to keep going after iOS has killed the app and later relaunched it in the background.

import Foundation

/// The address the queue's transfers last went to, and the login it belongs to.
public struct OfflineTransferAddress: Codable, Equatable, Sendable {
    /// The address the user signed in with — `CredentialStoring.serverURL()`. The key that ties
    /// this record to one credential.
    public var loginURL: URL
    /// The address transfers were actually sent to — the client's resolved one, which may be
    /// the local or the remote side of a pair (`AuthStore.resolveServerAddress`).
    public var serverURL: URL

    public init(loginURL: URL, serverURL: URL) {
        self.loginURL = loginURL
        self.serverURL = serverURL
    }

    /// The address a client may be rebuilt for, or `nil` if none may be built at all.
    public static func addressForRebuiltClient(
        recorded: OfflineTransferAddress?,
        currentLoginURL: URL?,
        hasCredential: Bool
    ) -> URL? {
        guard hasCredential,
              let recorded,
              let currentLoginURL,
              recorded.loginURL == currentLoginURL
        else { return nil }
        return recorded.serverURL
    }

    // MARK: - Persistence

    /// Where the record lives. `UserDefaults`, not the Keychain: neither address is a secret —
    /// `CredentialStoring` keeps the login address in `UserDefaults` itself — and the credential
    /// this record points at never leaves the Keychain.
    public static let defaultsKey = "OfflineDownloader.transferAddress"

    public static func load(from defaults: UserDefaults) -> OfflineTransferAddress? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(OfflineTransferAddress.self, from: data)
    }

    public static func save(_ address: OfflineTransferAddress?, to defaults: UserDefaults) {
        guard let address, let data = try? JSONEncoder().encode(address) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}
