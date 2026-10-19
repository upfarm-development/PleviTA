
import Foundation

@MainActor
public enum HomeBackgroundRefresh {
    /// Must also be listed under `BGTaskSchedulerPermittedIdentifiers` in the app's Info.plist; the
    /// system terminates an app that registers one that is not.
    public nonisolated static let taskIdentifier = "com.plevi.ta.home-refresh"

    /// Fetches Continue Watching and the first page of Newly Added with the stored login, and saves them as the snapshot.
    public static func run(
        credentialStore: CredentialStoring = KeychainCredentialStore.platformDefault,
        snapshots: HomeSnapshotStore = HomeSnapshotStore()
    ) async -> Bool {
        guard credentialStore.token() != nil || credentialStore.sessionCredential() != nil,
              let loginURL = credentialStore.serverURL() else { return false }

        let local = credentialStore.localServerURL()
        let remote = credentialStore.remoteServerURL()
        var address = loginURL
        if local != nil || remote != nil {
            let probe = ServerReachabilityProbe(credentialStore: credentialStore)
            address = await ServerAddressResolver.resolve(
                local: local,
                remote: remote,
                mode: credentialStore.connectionMode(),
                loginServerURL: loginURL,
                probe: probe.callAsFunction
            ) ?? loginURL
        }
        if Task.isCancelled { return false }

        let client = TAClient(serverURL: address, credentialStore: credentialStore)
        let settings = AppSettings(defaults: KeychainCredentialStore.sharedDefaults)
        let store = HomeStore(
            client: client,
            appSettings: settings,
            snapshots: snapshots,
            snapshotScope: loginURL.absoluteString
        )
        return await store.refreshSnapshotNow()
    }
}
