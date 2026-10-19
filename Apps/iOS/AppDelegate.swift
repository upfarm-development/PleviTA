
import BackgroundTasks
import UIKit
import PleviCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    let offlineLibrary = OfflineLibrary(root: OfflineLibrary.defaultRoot())
    private(set) lazy var offlineDownloader = OfflineDownloader(library: offlineLibrary)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The shelf has to know which server it is before anything can be filed on it, and on a background relaunch nothing else will tell it.
        if let loginURL = KeychainCredentialStore.platformDefault.serverURL() {
            let library = offlineLibrary
            Task { await library.adopt(scope: loginURL.absoluteString) }
        }

        // Forces `offlineDownloader` into existence now rather than waiting for the first caller.
        offlineDownloader.restoreExistingTasks()

        // Every delete, from any screen, stops that video's transfer and lets the queue move up
        // — see `OfflineDownloader.handleDeleted` for why this is a hook on the library rather
        // than something each delete affordance has to remember.
        let downloader = offlineDownloader
        offlineLibrary.didDelete = { videoIds in
            Task { await downloader.handleDeleted(videoIds) }
        }

        // The cellular setting, from where `AppSettings` saved it.
        downloader.seedAllowsCellular(
            AppSettings.persistedAllowCellularDownloads(in: KeychainCredentialStore.sharedDefaults)
        )

        if application.applicationState == .background {
            downloader.beginHandedOff()
        }
        let center = NotificationCenter.default
        // Both observers are delivered on the main queue, which is what makes `assumeIsolated`
        // correct here rather than a guess.
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // Held so a long queue finishes being handed over even if the app reaches the background part-way through.
                let assertion = BackgroundAssertion(name: "Hand download queue to the system")
                Task { @MainActor in
                    await downloader.appWillResignActive()
                    assertion.end()
                }
            }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await downloader.appDidBecomeActive() }
        }

        // Home's background refresh: iOS decides when to run it, at most now and then, and it only
        // ever asks again if this schedules a next one. Registered here because registration has to
        // finish before launch does.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: HomeBackgroundRefresh.taskIdentifier, using: nil) { task in
            MainActor.assumeIsolated { Self.handleHomeRefresh(task) }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Self.scheduleHomeRefresh()
        }
        return true
    }

    nonisolated private static func scheduleHomeRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: HomeBackgroundRefresh.taskIdentifier)
        // A hint, not a promise: the system picks the time, usually later, and skips it entirely
        // when the device is low on power or the app is rarely opened.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            PlaybackLog.shared.log("bg", "could not schedule the Home refresh: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func handleHomeRefresh(_ task: BGTask) {
        // The next one is asked for first, so a run that fails or is cut short does not end the chain.
        scheduleHomeRefresh()
        PlaybackLog.shared.log("bg", "Home refresh started by the system")
        let work = Task { @MainActor in
            let saved = await HomeBackgroundRefresh.run()
            PlaybackLog.shared.log("bg", "Home refresh finished saved=\(saved)")
            task.setTaskCompleted(success: saved)
        }
        // Out of time: stop the work. `run()` returns early and reports through the line above,
        // so the task is completed exactly once.
        task.expirationHandler = { work.cancel() }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == OfflineDownloader.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        offlineDownloader.backgroundEventsCompletion = completionHandler
    }
}

/// A background-task assertion that is ended exactly once: when the work it covers finishes, or when iOS says the time is up — whichever comes first.
@MainActor
final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Called on the main thread.
            MainActor.assumeIsolated { self.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
