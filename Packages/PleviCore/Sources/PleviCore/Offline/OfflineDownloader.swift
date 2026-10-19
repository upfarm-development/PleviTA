
#if os(iOS)
import Foundation
import Network

public final class OfflineDownloader: NSObject, @unchecked Sendable {
    /// One process, one background session identifier — a second instance (there should never
    /// be one) would otherwise silently steal this one's tasks from under it.
    public static let backgroundSessionIdentifier = "com.plevi.ta.offlinedownload"

    private let library: OfflineLibrary
    private var session: URLSession!
    /// How many transfers the system may run at once against the server.
    public static let maximumConcurrentTransfers = 3

    /// How often a download's byte count is allowed to reach disk and the UI.
    private static let progressInterval: TimeInterval = 0.5

    private let lock = NSLock()
    private var videoIdsByTask: [Int: String] = [:]
    /// When each task's progress was last forwarded — see `progressInterval`.
    private var lastProgressAt: [Int: TimeInterval] = [:]
    private let pathMonitor = NWPathMonitor()
    private var isExpensiveConnection = false
    /// Videos whose task has finished but whose record has not been written yet.
    private var resolvingVideoIds: Set<String> = []
    /// Serialises `pump()` against itself.
    private var isPumping = false
    private var wantsPump = false
    /// Callers waiting for the pump to go idle — see `waitForPumpToFinish`.
    private var pumpIdleWaiters: [CheckedContinuation<Void, Never>] = []
    /// Whoever most recently asked for a download, kept so a pump triggered by a *completion* — a delegate callback, with no caller to pass one.
    private var latestClient: TAClient?
    /// The user's "Allow cellular downloads" setting, as last reported.
    private var latestAllowsCellular: Bool?
    /// Where this login's transfers last went — see `OfflineTransferAddress`.
    private var recordedAddress: OfflineTransferAddress?
    private let credentialStore: CredentialStoring
    private let defaults: UserDefaults
    /// Completion work still running from delegate callbacks — record writes and the pump that
    /// follows each one — plus any pump in progress. See `urlSessionDidFinishEvents`.
    private var inFlightDelegateWork = 0
    private var eventsFinishedWhileBusy = false
    /// Which held completion handler a grace timer belongs to — see `releaseHeldCompletion`.
    private var heldCompletionGeneration = 0
    /// True while the app is not active: the whole queue has been handed to `URLSession`
    /// rather than fed to it a few at a time. See `appWillResignActive`.
    private var isHandedOff = false
    /// Videos whose handed-over transfer is being cancelled on return to the foreground. Kept
    /// out of the pump's live count and out of what it may start until the cancellation lands,
    /// so the freed slot is refilled in queue order rather than by recreating the same video.
    private var reclaimingVideoIds: Set<String> = []
    /// A client for this login's own address, used when the held one cannot be — see
    /// `clientForCurrentLogin`.
    private var fallbackClient: (url: URL, client: TAClient)?
    /// Media paths as the caller gave them, for the one case `video.json` cannot answer — see
    /// `beginTransfer`.
    private var mediaPathsByVideoId: [String: String] = [:]

    /// Set by `AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    private nonisolated(unsafe) var _backgroundEventsCompletion: (() -> Void)?
    public var backgroundEventsCompletion: (() -> Void)? {
        get { lock.withLock { _backgroundEventsCompletion } }
        set { lock.withLock { _backgroundEventsCompletion = newValue } }
    }

    public init(
        library: OfflineLibrary,
        credentialStore: CredentialStoring = KeychainCredentialStore.platformDefault,
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.recordedAddress = OfflineTransferAddress.load(from: defaults)
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        // A backstop only — `pump()` is what actually limits concurrency, by not creating the
        // tasks in the first place. This matters for the transfers `pump` does start: it keeps
        // the session from opening more connections per video than the cap implies.
        configuration.httpMaximumConnectionsPerHost = Self.maximumConcurrentTransfers
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isExpensive = path.isExpensive
            self.lock.withLock { self.isExpensiveConnection = isExpensive }
            if isExpensive {
                Task { await self.pump() }
            } else {
                Task { await self.resumeAfterPathBecameCheap() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.plevi.ta.offlinedownload.pathmonitor"))
    }

    /// Re-associates this instance with whatever the system already has queued for `Self.backgroundSessionIdentifier`.
    public func restoreExistingTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let restored: Set<String> = self.lock.withLock {
                for task in tasks {
                    guard let videoId = task.taskDescription else { continue }
                    self.videoIdsByTask[task.taskIdentifier] = videoId
                }
                return Set(self.videoIdsByTask.values)
            }
            // Publish them as active straight away rather than waiting for the first pump.
            guard !restored.isEmpty else { return }
            let library = self.library
            Task { await library.setActiveDownloads(restored) }
        }
    }

    /// Puts one video in the download queue.
    public func start(videoId: String, mediaPath: String, client: TAClient, allowsCellular: Bool) async {
        PlaybackLog.shared.log("dl", "start requested video=\(videoId) allowsCellular=\(allowsCellular)")
        enqueue(videoId: videoId, mediaPath: mediaPath, client: client, allowsCellular: allowsCellular)
        // No cellular check here: the gate lives in exactly one place, `beginTransfer`, against the live setting.
        await library.clearWaitingForWiFi(videoId: videoId)
        await pump()
    }

    /// Records what the queue needs to start a video later, without pumping.
    public func enqueue(videoId: String, mediaPath: String, client: TAClient, allowsCellular: Bool) {
        lock.withLock {
            latestClient = client
            if latestAllowsCellular == nil { latestAllowsCellular = allowsCellular }
            mediaPathsByVideoId[videoId] = mediaPath
        }
    }

    /// Seeds the cellular setting at launch from its saved value, before any view exists to
    /// report it — and on a background relaunch, no view ever will. Does nothing if something
    /// has already reported the live value.
    public func seedAllowsCellular(_ allowsCellular: Bool) {
        lock.withLock { if latestAllowsCellular == nil { latestAllowsCellular = allowsCellular } }
    }

    /// For a launch straight into the background — iOS relaunching the app to deliver
    /// finished transfers. The queue should behave as handed off from the start.
    public func beginHandedOff() {
        lock.withLock { isHandedOff = true }
    }

    /// The app is about to stop being active — locked, sent home, switched away from.
    public func appWillResignActive() async {
        lock.withLock { isHandedOff = true }
        PlaybackLog.shared.log("dl", "app resigning active; handing the queue to the system")
        // A "Waiting for Wi-Fi" flag keeps a video out of the pump's picks.
        await library.clearAllWaitingForWiFi()
        await pump()
        await waitForPumpToFinish()
        await logTaskSnapshot("handed off")
    }

    /// One line per task the system holds, so a download that stops while the app is away can be
    /// read off the log: which transfers existed when the app left, how far each had got, and
    /// what state the system had put them in.
    private func logTaskSnapshot(_ moment: String) async {
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        let states = tasks.map { task -> String in
            let state: String
            switch task.state {
            case .running: state = "running"
            case .suspended: state = "suspended"
            case .canceling: state = "canceling"
            case .completed: state = "completed"
            @unknown default: state = "unknown"
            }
            return "\(task.taskDescription ?? "?"):\(state):\(task.countOfBytesReceived)B"
        }
        PlaybackLog.shared.log("dl", "tasks \(moment): \(tasks.count) [\(states.joined(separator: ", "))]")
    }

    /// The app is active again.
    public func appDidBecomeActive() async {
        lock.withLock { isHandedOff = false }
        await logTaskSnapshot("on return to the foreground")
        // A hand-off pass may still be creating tasks — a quick trip to Control Center is well under a second.
        await waitForPumpToFinish()
        // And look at the shelf as it is, not as it was: on a cold launch it may not have
        // loaded yet, and an empty queue would make every waiting transfer look surplus.
        await library.reload()
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        var inProgress: Set<String> = []
        var waitingInSystem: Set<String> = []
        for task in tasks where task.state == .running {
            guard let videoId = task.taskDescription else { continue }
            if task.countOfBytesReceived > 0 {
                inProgress.insert(videoId)
            } else {
                waitingInSystem.insert(videoId)
            }
        }
        let toCancel = cellularGateAllowsStart()
            ? OfflineDownloadQueue.toReclaim(
                items: await library.queueItems(),
                inProgress: inProgress,
                waitingInSystem: waitingInSystem,
                limit: Self.maximumConcurrentTransfers
            )
            : waitingInSystem
        if !toCancel.isEmpty {
            lock.withLock { reclaimingVideoIds.formUnion(toCancel) }
            cancelTasks(for: toCancel)
        }
        await pump()
    }

    /// Re-examines the queue and starts whatever should be running.
    public func pumpQueue() async {
        await pump()
    }

    /// Starts whatever the queue says should be running and is not, up to `maximumConcurrentTransfers`.
    private func pump() async {
        let shouldRun: Bool = lock.withLock {
            guard !isPumping else { wantsPump = true; return false }
            isPumping = true
            wantsPump = false
            return true
        }
        guard shouldRun else { return }
        // Counted as completion work for as long as it runs.
        lock.withLock { inFlightDelegateWork += 1 }
        defer { endCompletionWork() }

        // Videos refused during THIS pump, kept for all its passes.
        var refused: Set<String> = []
        while true {
            let newlyRefused = await runPump(excluding: refused)
            refused.formUnion(newlyRefused)
            let (again, idleWaiters): (Bool, [CheckedContinuation<Void, Never>]) = lock.withLock {
                // A refusal leaves its slot empty with nothing coming to fill it (no task, so
                // no completion), so it earns another pass for the video behind it.
                if !newlyRefused.isEmpty { wantsPump = true }
                guard wantsPump else {
                    isPumping = false
                    defer { pumpIdleWaiters = [] }
                    return (false, pumpIdleWaiters)
                }
                wantsPump = false
                return (true, [])
            }
            for waiter in idleWaiters { waiter.resume() }
            guard again else { return }
        }
    }

    /// Returns once no pump is running — including any passes a running pump has yet to make.
    private func waitForPumpToFinish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyIdle: Bool = lock.withLock {
                guard isPumping else { return true }
                pumpIdleWaiters.append(continuation)
                return false
            }
            if alreadyIdle { continuation.resume() }
        }
    }

    /// One pass: works out what is live, and starts what should be. Returns the videos it
    /// refused — see `pump` for why the caller has to remember them.
    private func runPump(excluding refused: Set<String>) async -> Set<String> {
        let handedOff = lock.withLock { isHandedOff }
        guard let client = await clientForCurrentLogin(handedOff: handedOff) else { return [] }

        // The union of what the system reports, what this object has handed over, and what is mid-resolution.
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        let reported = Set(tasks.compactMap(\.taskDescription))

        // Transfers the system is holding for Wi-Fi: their request forbids an expensive path (see `beginTransfer`), and the path is expensive.
        let held: Set<String> = lock.withLock { isExpensiveConnection }
            ? Set(tasks.lazy
                .filter { $0.state == .running && $0.originalRequest?.allowsExpensiveNetworkAccess == false }
                .compactMap(\.taskDescription))
            : []
        await library.setHeldForWiFi(held)

        let resolving = lock.withLock { resolvingVideoIds }
        // Reclaims whose task has already gone are finished, whether or not their cancellation
        // callback has arrived yet.
        let reclaiming: Set<String> = lock.withLock {
            reclaimingVideoIds.formIntersection(reported)
            return reclaimingVideoIds
        }
        let live = reported.union(lock.withLock { Set(videoIdsByTask.values) }).union(resolving).subtracting(reclaiming)

        // A "Waiting for Wi-Fi" flag is stale whenever the gate is open, however it came to be open.
        if handedOff || cellularGateAllowsStart() {
            await library.clearAllWaitingForWiFi()
        }

        let queue = await library.queueItems()
        let queuedIds = Set(queue.map(\.videoId))

        // A task still running for a video that is no longer queued.
        var orphans: Set<String> = []
        for videoId in live.subtracting(queuedIds).subtracting(resolving) {
            if await !library.bundleExists(videoId: videoId) {
                orphans.insert(videoId)
            }
        }
        if !orphans.isEmpty {
            cancelTasks(for: orphans)
        }
        let effectiveLive = live.subtracting(orphans)
        await library.setActiveDownloads(effectiveLive)

        let next = OfflineDownloadQueue.nextToStart(
            items: queue,
            liveVideoIds: effectiveLive.subtracting(held),
            // Handed off: everything, and the connection cap keeps concurrency down.
            limit: handedOff ? Int.max : Self.maximumConcurrentTransfers,
            // Held transfers are excluded from starting even though they do not occupy a slot.
            excluding: refused.union(held).union(handedOff ? [] : reclaiming)
        )
        guard !next.isEmpty else { return [] }

        // Once per pass, not per video: the same for every request, and a hand-off can start
        // hundreds of transfers in a window of well under a second.
        let headers = await client.authorizationHeaders()
        var newlyRefused: Set<String> = []
        for videoId in next {
            // The app came back while this hand-off pass was still running. Stop: everything
            // not yet handed over stays with the foreground queue, and `appDidBecomeActive` —
            // which waits for this pump — takes back what was.
            if handedOff, !lock.withLock({ isHandedOff }) { break }
            switch await beginTransfer(videoId: videoId, client: client, headers: headers, handedOff: handedOff) {
            case .started:
                continue
            case .refused:
                newlyRefused.insert(videoId)
            case .deferred:
                // The cellular gate is one switch for the whole queue, not a per-video fact: if this video may not start on this connection, nor may any behind it.
                await library.setActiveDownloads(effectiveLive.union(lock.withLock { Set(videoIdsByTask.values) }))
                return newlyRefused
            }
        }
        await library.setActiveDownloads(effectiveLive.union(lock.withLock { Set(videoIdsByTask.values) }))
        return newlyRefused
    }

    /// The client to start transfers with, but only if it belongs to whoever is signed in NOW.
    private func clientForCurrentLogin(handedOff: Bool) async -> TAClient? {
        let loginURL = credentialStore.serverURL()
        let hasCredential = credentialStore.token() != nil || credentialStore.sessionCredential() != nil
        guard hasCredential, let loginURL else {
            lock.withLock { latestClient = nil }
            return nil
        }
        let addressesOfThisLogin = Set(
            [loginURL, credentialStore.localServerURL(), credentialStore.remoteServerURL()].compactMap { $0 }
        )

        if let client = lock.withLock({ latestClient }) {
            let address = await client.currentServerURL()
            if addressesOfThisLogin.contains(address) {
                record(OfflineTransferAddress(loginURL: loginURL, serverURL: address))
                return client
            }
            return fallbackClient(for: loginURL)
        }

        guard handedOff else { return nil }

        // Handed off with no client held — a cold background relaunch, where `AuthStore` never restores because no scene connects.
        let rebuiltAddress = OfflineTransferAddress.addressForRebuiltClient(
            recorded: lock.withLock({ recordedAddress }),
            currentLoginURL: loginURL,
            hasCredential: hasCredential
        ).flatMap { addressesOfThisLogin.contains($0) ? $0 : nil } ?? loginURL
        let rebuilt = TAClient(serverURL: rebuiltAddress, credentialStore: credentialStore)
        return lock.withLock {
            if latestClient == nil { latestClient = rebuilt }
            return latestClient
        }
    }

    private func fallbackClient(for url: URL) -> TAClient {
        lock.withLock {
            if let fallbackClient, fallbackClient.url == url { return fallbackClient.client }
            let client = TAClient(serverURL: url, credentialStore: credentialStore)
            fallbackClient = (url, client)
            return client
        }
    }

    /// Keeps `recordedAddress` current, writing through to `UserDefaults` only when it changes
    /// — this runs on every pump.
    private func record(_ address: OfflineTransferAddress) {
        let changed: Bool = lock.withLock {
            guard recordedAddress != address else { return false }
            recordedAddress = address
            return true
        }
        if changed { OfflineTransferAddress.save(address, to: defaults) }
    }

    /// Cancels the live tasks for these videos without capturing resume data — used only for
    /// orphans, whose bundles are already gone, so there is nothing left for resume data to
    /// resume into.
    private func cancelTasks(for videoIds: Set<String>) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription.map(videoIds.contains) == true {
                task.cancel()
            }
        }
    }

    /// What became of one video the pump tried to start.
    private enum TransferOutcome {
        /// A task was created and resumed.
        case started
        /// Held back by the cellular gate, and flagged "Waiting for Wi-Fi". Not a failure:
        /// the flag keeps it out of later passes, and a change of path or setting pumps again.
        case deferred
        /// Could not be started — failed, or no longer on the shelf. Its slot is still free.
        case refused
    }

    /// Creates and resumes the actual `URLSessionDownloadTask` for one video.
    private func beginTransfer(
        videoId: String,
        client: TAClient,
        headers: [String: String],
        handedOff: Bool
    ) async -> TransferOutcome {
        guard await library.bundleExists(videoId: videoId) else {
            return .refused
        }

        // Resolved before anything else, so that a video which can never be downloaded fails HERE — visibly, with a reason.
        let entry = await library.entry(for: videoId)
        guard let mediaPath = entry?.video.mediaUrl ?? lock.withLock({ mediaPathsByVideoId[videoId] }) else {
            await library.markFailed(videoId: videoId, reason: "Couldn't resolve the media address.")
            return .refused
        }

        // The cellular gate, against the setting as it is NOW rather than as it was when this pump began.
        guard handedOff || cellularGateAllowsStart() else {
            await library.markWaitingForWiFi(videoId: videoId)
            // Read again AFTER flagging.
            if cellularGateAllowsStart() {
                await library.clearWaitingForWiFi(videoId: videoId)
            }
            return .deferred
        }

        let estimatedByteCount = entry?.video.mediaSize
        if let availableCapacity = OfflineDiskSpace.availableCapacity(),
           !OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: estimatedByteCount, availableCapacity: availableCapacity) {
            await library.markFailed(videoId: videoId, reason: "Not enough free space on this device.")
            return .refused
        }

        guard let url = await client.mediaURL(forPath: mediaPath) else {
            await library.markFailed(videoId: videoId, reason: "Couldn't resolve the media address.")
            return .refused
        }

        let task: URLSessionDownloadTask
        if let resumeData = await library.resumeData(videoId: videoId) {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            // The cellular setting, enforced by the system for the life of the transfer.
            request.allowsExpensiveNetworkAccess = lock.withLock { latestAllowsCellular ?? false }
            task = session.downloadTask(with: request)
        }
        task.taskDescription = videoId
        lock.withLock { videoIdsByTask[task.taskIdentifier] = videoId }
        task.resume()
        return .started
    }

    /// The cellular gate against the live state: the setting as last reported, and the path
    /// as `NWPathMonitor` last saw it. An unreported setting counts as "not allowed".
    private func cellularGateAllowsStart() -> Bool {
        let (allowsCellular, isExpensive) = lock.withLock { (latestAllowsCellular ?? false, isExpensiveConnection) }
        return OfflineNetworkPolicy.shouldStartNow(allowsCellular: allowsCellular, isExpensiveConnection: isExpensive)
    }

    public func handleDeleted(_ videoIds: [String]) async {
        guard !videoIds.isEmpty else { return }
        lock.withLock {
            for videoId in videoIds { mediaPathsByVideoId[videoId] = nil }
        }
        cancelTasks(for: Set(videoIds))
        await pump()
    }

    /// The "Allow cellular downloads" setting changed — called from `RootView`'s `.onChange` in BOTH directions.
    public func setAllowsCellular(_ allowsCellular: Bool) async {
        lock.withLock { latestAllowsCellular = allowsCellular }
        guard allowsCellular else { return }
        // A transfer created while cellular was forbidden carries that in its request, and a request cannot be changed once its task exists.
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        let restrictedUnstarted = Set(tasks.lazy
            .filter { $0.state == .running && $0.countOfBytesReceived == 0 && $0.originalRequest?.allowsExpensiveNetworkAccess == false }
            .compactMap(\.taskDescription))
        if !restrictedUnstarted.isEmpty {
            lock.withLock { reclaimingVideoIds.formUnion(restrictedUnstarted) }
            cancelTasks(for: restrictedUnstarted)
        }
        await drainCellularDeferrals()
    }

    /// The path monitor's resume: the connection stopped being expensive, so nothing is blocked any more regardless of the setting.
    private func resumeAfterPathBecameCheap() async {
        await drainCellularDeferrals()
    }

    /// Clears every "Waiting for Wi-Fi" flag and pumps. Every flag, not a remembered subset:
    /// `beginTransfer` re-checks the gate for each video it starts, so anything still blocked
    /// is simply flagged again, and nothing flagged can be missed.
    private func drainCellularDeferrals() async {
        await library.clearAllWaitingForWiFi()
        await pump()
    }

    /// Re-queues any `.downloading` record with no live task backing it.
    public func reconcileStuckDownloads(client: TAClient, allowsCellular: Bool) async {
        await library.reload()
        let liveVideoIds: Set<String> = await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: Set(tasks.compactMap(\.taskDescription)))
            }
        }
        for entry in await library.entries where entry.record.state == .downloading && !liveVideoIds.contains(entry.id) {
            guard let mediaPath = entry.video.mediaUrl else { continue }
            lock.withLock { mediaPathsByVideoId[entry.id] = mediaPath }
        }
        lock.withLock {
            latestClient = client
            latestAllowsCellular = allowsCellular
        }
        await pump()
    }

    private func videoId(for task: URLSessionTask) -> String? {
        lock.withLock { videoId(forLocked: task) }
    }

    /// `videoId(for:)` for a caller already holding `lock` — `NSLock` is not recursive, so the
    /// public form would deadlock there.
    private func videoId(forLocked task: URLSessionTask) -> String? {
        task.taskDescription ?? videoIdsByTask[task.taskIdentifier]
    }

    /// Releases a video once its record has been written — both the pump's reservation and
    /// the remembered media path, which only exists to bridge the gap between being queued and
    /// being started. A retry supplies it again through `start`.
    private func finishResolving(_ videoId: String) {
        lock.withLock {
            resolvingVideoIds.remove(videoId)
            mediaPathsByVideoId[videoId] = nil
        }
    }

    private func forget(_ task: URLSessionTask) {
        lock.withLock {
            videoIdsByTask[task.taskIdentifier] = nil
            lastProgressAt[task.taskIdentifier] = nil
        }
    }
}

extension OfflineDownloader: URLSessionDownloadDelegate {
    /// The temp file at `location` is deleted the instant this method returns (documented `URLSession` behavior), so everything that needs its bytes.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let videoId = videoId(for: downloadTask) else { return }
        let finishedResponse = downloadTask.response as? HTTPURLResponse
        PlaybackLog.shared.log("dl", "finished video=\(videoId) status=\(finishedResponse?.statusCode ?? 0) "
            + "bytes=\(downloadTask.countOfBytesReceived)/\(downloadTask.countOfBytesExpectedToReceive)")
        // Held from here until the record is written — see `resolvingVideoIds`.
        lock.withLock { _ = resolvingVideoIds.insert(videoId) }
        defer { forget(downloadTask) }

        let response = downloadTask.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        let contentType = response?.value(forHTTPHeaderField: "Content-Type")
        // On a 206 the `Content-Length` is the length of the RANGE, not of the file.
        let expected = DownloadValidation.expectedTotalBytes(
            status: status,
            contentLength: response.flatMap { $0.value(forHTTPHeaderField: "Content-Length") },
            contentRange: response.flatMap { $0.value(forHTTPHeaderField: "Content-Range") }
        )
        let first12 = (try? FileHandle(forReadingFrom: location))?.readData(ofLength: 12) ?? Data()
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? nil

        let verdict = DownloadValidation.validate(
            status: status,
            contentType: contentType,
            first12Bytes: first12,
            byteCount: byteCount ?? 0,
            expected: expected
        )

        switch verdict {
        case .ok:
            // Staged with a `copy`, not a `move`: the `Task` below runs asynchronously, by
            // which point `location` (and the temp directory it lives in) may already have
            // been cleaned up by the system.
            let staged = FileManager.default.temporaryDirectory.appendingPathComponent("offline-download-\(UUID().uuidString)")
            do {
                try FileManager.default.copyItem(at: location, to: staged)
            } catch {
                completionWork { [self] in
                    await library.markFailed(videoId: videoId, reason: "Couldn't save the downloaded file.")
                    finishResolving(videoId)
                    await pump()
                }
                return
            }
            completionWork { [self] in
                await library.markComplete(videoId: videoId, from: staged)
                try? FileManager.default.removeItem(at: staged)
                finishResolving(videoId)
                await pump()
            }
        case .notTheFileWeAskedFor(let reason):
            completionWork { [self] in
                await library.markFailed(videoId: videoId, reason: reason)
                finishResolving(videoId)
                await pump()
            }
        case .retryableAuthFailure:
            completionWork { [self] in
                await library.markFailed(videoId: videoId, reason: "Sign-in is required to finish this download.")
                finishResolving(videoId)
                await pump()
            }
        }
    }

    private static let progressLogThrottle = LogThrottle()

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let videoId = videoId(for: downloadTask) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? Int(totalBytesExpectedToWrite) : nil
        // A saved video transferring while something plays is competing for the same Wi-Fi and the
        // same server; this is the line that says so. Every five seconds per transfer.
        if Self.progressLogThrottle.allows("dl-\(videoId)", every: 5) {
            PlaybackLog.shared.log("dl", "progress video=\(videoId) \(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes")
        }

        // Throttled before the hop, so a suppressed tick costs a dictionary lookup rather
        // than a `Task`, a main-actor hop and a disk write. See `progressInterval`.
        let now = Date().timeIntervalSince1970
        let isComplete = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        let shouldForward: Bool = lock.withLock {
            let last = lastProgressAt[downloadTask.taskIdentifier]
            guard !isComplete else {
                lastProgressAt[downloadTask.taskIdentifier] = now
                return true
            }
            if let last, now - last < Self.progressInterval { return false }
            lastProgressAt[downloadTask.taskIdentifier] = now
            return true
        }
        guard shouldForward else { return }

        Task { await library.updateProgress(videoId: videoId, receivedByteCount: Int(totalBytesWritten), expectedByteCount: expected) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A transfer taken back from the system on return to the foreground has now ended —
        // cancelled, or finished just before the cancel reached it. Once the last one is in,
        // the queue is the app's again and the freed slots can be filled in queue order.
        let lastReclaimLanded: Bool = lock.withLock {
            guard let id = videoId(forLocked: task), reclaimingVideoIds.remove(id) != nil else { return false }
            return reclaimingVideoIds.isEmpty
        }
        if lastReclaimLanded {
            completionWork { [self] in await pump() }
        }

        guard let error, let videoId = videoId(for: task) else { forget(task); return }
        let nsError = error as NSError
        PlaybackLog.shared.log("dl", "ERROR video=\(videoId) \(nsError.domain)#\(nsError.code) \(error.localizedDescription)")
        // Our own cancellation — `handleDeleted` or the orphan check in `runPump`. The record is
        // already gone and `handleDeleted` pumps itself, so there is nothing to mark and no
        // slot owed a pump from here.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            forget(task)
            return
        }
        lock.withLock { _ = resolvingVideoIds.insert(videoId) }
        forget(task)
        completionWork { [self] in
            await library.markFailed(videoId: videoId, reason: error.localizedDescription)
            finishResolving(videoId)
            await pump()
        }
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        PlaybackLog.shared.log("dl", "SESSION INVALID \(error.map { "\(($0 as NSError).domain)#\(($0 as NSError).code)" } ?? "no error")", force: true)
    }

    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        PlaybackLog.shared.log("dl", "waiting for connectivity video=\(task.taskDescription ?? "?")")
    }

    /// Hands the background-events completion handler back to iOS — but only once the work those events started has actually finished.
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        PlaybackLog.shared.log("dl", "background events delivered (the system woke the app for this session)")
        let held: (completion: UncheckedCompletion?, generation: Int) = lock.withLock {
            guard inFlightDelegateWork == 0 else {
                eventsFinishedWhileBusy = true
                heldCompletionGeneration += 1
                return (nil, heldCompletionGeneration)
            }
            defer { _backgroundEventsCompletion = nil }
            return (_backgroundEventsCompletion.map(UncheckedCompletion.init), heldCompletionGeneration)
        }
        if let completion = held.completion {
            DispatchQueue.main.async { completion.run() }
            return
        }
        let generation = held.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.backgroundWorkGrace) { [weak self] in
            self?.releaseHeldCompletion(generation: generation)
        }
    }
}

extension OfflineDownloader {
    /// How long a background wake may keep working before the completion handler is handed
    /// back regardless. iOS allows roughly thirty seconds; this leaves room.
    fileprivate static let backgroundWorkGrace: TimeInterval = 20

    /// Runs one piece of completion work — a record write and the pump after it — counted, so
    /// that `urlSessionDidFinishEvents` knows to wait for it.
    fileprivate func completionWork(_ work: @escaping @Sendable () async -> Void) {
        lock.withLock { inFlightDelegateWork += 1 }
        Task {
            await work()
            self.endCompletionWork()
        }
    }

    private func endCompletionWork() {
        let completion: UncheckedCompletion? = lock.withLock {
            inFlightDelegateWork -= 1
            guard inFlightDelegateWork == 0, eventsFinishedWhileBusy else { return nil }
            eventsFinishedWhileBusy = false
            defer { _backgroundEventsCompletion = nil }
            return _backgroundEventsCompletion.map(UncheckedCompletion.init)
        }
        if let completion {
            DispatchQueue.main.async { completion.run() }
        }
    }

    /// The grace timer's release — does nothing if the work already finished and handed it back, or if the handler now held belongs to a LATER wake.
    private func releaseHeldCompletion(generation: Int) {
        let completion: UncheckedCompletion? = lock.withLock {
            guard eventsFinishedWhileBusy, heldCompletionGeneration == generation else { return nil }
            eventsFinishedWhileBusy = false
            defer { _backgroundEventsCompletion = nil }
            return _backgroundEventsCompletion.map(UncheckedCompletion.init)
        }
        completion?.run()
    }
}

/// UIKit's completion handler is a plain closure, and must be called on the main queue. It is
/// only ever called once and only there, which is what makes carrying it across safe.
private struct UncheckedCompletion: @unchecked Sendable {
    let run: () -> Void
}
#endif
