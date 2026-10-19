
#if os(iOS) || os(tvOS)
import Foundation
import UIKit
import AVFoundation
import Network
import Darwin

@MainActor
public final class PlaybackMonitor {
    public static let shared = PlaybackMonitor()

    private let log = PlaybackLog.shared
    private var samplers: [ObjectIdentifier: () -> String?] = [:]
    private var sampleTask: Task<Void, Never>?
    private let watchdog = MainThreadWatchdog()
    private var systemObserversInstalled = false
    private var observerTokens: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var lastSampleUptime = ProcessInfo.processInfo.systemUptime
    private var sampleTick = 0

    private init() {}

    // MARK: - Sessions

    /// A playback session began. `sampler` returns the engine's own once-a-second line (or nil).
    public func sessionDidBegin(owner: AnyObject, label: String, sampler: @escaping () -> String?) {
        installSystemObservers()
        samplers[ObjectIdentifier(owner)] = sampler
        log.log("session", "begin \(label) activeSessions=\(samplers.count) \(Self.deviceSnapshot())")
        startSamplingIfNeeded()
    }

    public func sessionDidEnd(owner: AnyObject, label: String) {
        guard samplers.removeValue(forKey: ObjectIdentifier(owner)) != nil else { return }
        log.log("session", "end \(label) activeSessions=\(samplers.count) \(Self.deviceSnapshot())")
        if samplers.isEmpty {
            sampleTask?.cancel()
            sampleTask = nil
            watchdog.stop()
        }
    }

    private func startSamplingIfNeeded() {
        guard sampleTask == nil else { return }
        lastSampleUptime = ProcessInfo.processInfo.systemUptime
        sampleTick = 0
        watchdog.start()
        sampleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.emitSample()
            }
        }
    }

    private func emitSample() {
        sampleTick += 1
        let now = ProcessInfo.processInfo.systemUptime
        // A sleep(1s) that comes back much later than a second means the main actor itself was
        // held up — the same finding as the watchdog from the other side.
        let dt = now - lastSampleUptime
        lastSampleUptime = now
        let block = watchdog.takeWorstBlockMilliseconds()
        log.log("sys", String(
            format: "cpu=%.0f%% footprint=%.0fMB free=%.0fMB thermal=%@ lpm=%d dt=%.3f mainBlockMax=%dms",
            Self.cpuPercent(), Self.footprintMB(), Self.availableMB(),
            Self.thermalName(ProcessInfo.processInfo.thermalState),
            ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0, dt, block))
        for sampler in samplers.values {
            if let line = sampler() { log.log("av.sample", line) }
        }
        if sampleTick % 30 == 0 {
            log.log("ctx", Self.deviceSnapshot() + " audio=" + Self.audioRouteDescription())
        }
    }

    // MARK: - System observers

    /// Idempotent. Called at launch and again at every session start, so the events around a stutter
    /// are recorded even when nothing was playing yet.
    public func installSystemObservers() {
        guard !systemObserversInstalled else { return }
        systemObserversInstalled = true
        log.log("launch", Self.launchBanner(), force: true)

        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ body: @escaping @MainActor (Notification) -> Void) {
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                // Delivered on the main queue (asked for above); `Notification` just isn't `Sendable`.
                let box = SendableNotification(note: note)
                MainActor.assumeIsolated { body(box.note) }
            })
        }

        observe(ProcessInfo.thermalStateDidChangeNotification) { [log] _ in
            log.log("thermal", "state -> \(Self.thermalName(ProcessInfo.processInfo.thermalState)) \(Self.deviceSnapshot())")
        }
        observe(.NSProcessInfoPowerStateDidChange) { [log] _ in
            log.log("power", "lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        }
        observe(UIApplication.didReceiveMemoryWarningNotification) { [log] _ in
            log.log("memory", String(format: "MEMORY WARNING footprint=%.0fMB free=%.0fMB", Self.footprintMB(), Self.availableMB()))
        }
        observe(UIApplication.didBecomeActiveNotification) { [log] _ in log.log("app", "didBecomeActive") }
        observe(UIApplication.willResignActiveNotification) { [log] _ in log.log("app", "willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [log] _ in log.log("app", "didEnterBackground") }
        observe(UIApplication.willEnterForegroundNotification) { [log] _ in log.log("app", "willEnterForeground") }
        observe(AVAudioSession.routeChangeNotification) { [log] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue).map(Self.routeChangeReasonName) ?? "\(reasonValue)"
            var previous = "?"
            if let route = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                previous = Self.describe(route)
            }
            log.log("audio", "routeChange reason=\(reason) previous=[\(previous)] now=[\(Self.audioRouteDescription())]")
        }
        observe(AVAudioSession.interruptionNotification) { [log] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) == .began ? "began" : "ended"
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            log.log("audio", "interruption \(type) options=\(options)")
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [log] _ in
            log.log("audio", "MEDIA SERVICES WERE RESET")
        }
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        observe(UIDevice.batteryStateDidChangeNotification) { [log] _ in
            log.log("battery", Self.batteryDescription())
        }
        observe(UIScreen.capturedDidChangeNotification) { [log] _ in
            log.log("screen", "capturing/mirroring changed -> \(Self.screenDescription())")
        }
        observe(UIScreen.didConnectNotification) { [log] _ in log.log("screen", "external screen connected") }
        observe(UIScreen.didDisconnectNotification) { [log] _ in log.log("screen", "external screen disconnected") }
        #endif

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            PlaybackLog.shared.log("net.path", Self.describe(path))
        }
        monitor.start(queue: DispatchQueue(label: "com.plevi.ta.playbacklog.path"))
        pathMonitor = monitor
    }

    // MARK: - Descriptions

    nonisolated static func launchBanner() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        let process = ProcessInfo.processInfo
        let memoryGB = Double(process.physicalMemory) / 1_073_741_824
        return "APP START version=\(version) build=\(build) device=\(model) os=\(process.operatingSystemVersionString) "
            + String(format: "ram=%.1fGB cores=%d/%d ", memoryGB, process.activeProcessorCount, process.processorCount)
            + "configuration=\(Self.buildConfiguration)"
    }

    nonisolated static var buildConfiguration: String {
        #if DEBUG
        "DEBUG(slower than a real build, stutter here may not be representative)"
        #else
        "release"
        #endif
    }

    static func deviceSnapshot() -> String {
        let process = ProcessInfo.processInfo
        var parts = [
            "thermal=\(thermalName(process.thermalState))",
            "lpm=\(process.isLowPowerModeEnabled)",
            String(format: "footprint=%.0fMB free=%.0fMB", footprintMB(), availableMB()),
            "appState=\(appStateName(UIApplication.shared.applicationState))",
        ]
        #if os(iOS)
        parts.append(batteryDescription())
        parts.append(screenDescription())
        #endif
        return parts.joined(separator: " ")
    }

    static func appStateName(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    #if os(iOS)
    static func batteryDescription() -> String {
        let device = UIDevice.current
        let state: String = switch device.batteryState {
        case .unknown: "unknown"
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        @unknown default: "unknown"
        }
        return String(format: "battery=%.0f%%(%@)", device.batteryLevel * 100, state)
    }

    static func screenDescription() -> String {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }.first ?? UIScreen.main
        return "maxFPS=\(screen.maximumFramesPerSecond) captured=\(screen.isCaptured) brightness=\(String(format: "%.2f", screen.brightness))"
    }
    #endif

    nonisolated static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "SERIOUS"
        case .critical: "CRITICAL"
        @unknown default: "unknown"
        }
    }

    nonisolated static func describe(_ path: NWPath) -> String {
        var interfaces = path.availableInterfaces.map { "\($0.name)/\($0.type)" }.joined(separator: ",")
        if interfaces.isEmpty { interfaces = "none" }
        let using = [(NWInterface.InterfaceType.wifi, "wifi"), (.cellular, "cellular"), (.wiredEthernet, "wired"), (.other, "other")]
            .filter { path.usesInterfaceType($0.0) }.map(\.1).joined(separator: "+")
        return "status=\(path.status) using=\(using.isEmpty ? "none" : using) available=[\(interfaces)] "
            + "expensive=\(path.isExpensive) constrained=\(path.isConstrained) ipv4=\(path.supportsIPv4) ipv6=\(path.supportsIPv6) dns=\(path.supportsDNS)"
    }

    static func describe(_ route: AVAudioSessionRouteDescription) -> String {
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        return outputs.isEmpty ? "none" : outputs
    }

    static func audioRouteDescription() -> String {
        let session = AVAudioSession.sharedInstance()
        return "[\(describe(session.currentRoute))] sampleRate=\(Int(session.sampleRate)) "
            + String(format: "ioBuffer=%.4fs outputLatency=%.4fs", session.ioBufferDuration, session.outputLatency)
    }

    static func routeChangeReasonName(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: "unknown"
        case .newDeviceAvailable: "newDeviceAvailable"
        case .oldDeviceUnavailable: "oldDeviceUnavailable"
        case .categoryChange: "categoryChange"
        case .override: "override"
        case .wakeFromSleep: "wakeFromSleep"
        case .noSuitableRouteForCategory: "noSuitableRouteForCategory"
        case .routeConfigurationChange: "routeConfigurationChange"
        @unknown default: "other"
        }
    }

    // MARK: - Process statistics

    /// Whole-process CPU as a percentage of one core (so 150 means one and a half cores busy).
    nonisolated static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return -1 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        return total
    }

    /// `phys_footprint` — the number jetsam actually judges the app by.
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    nonisolated static func availableMB() -> Double {
        Double(os_proc_available_memory()) / 1_048_576
    }
}

private struct SendableNotification: @unchecked Sendable { let note: Notification }

/// Logs every stretch where the main run loop stopped answering for longer than `threshold`.
final class MainThreadWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.plevi.ta.playbacklog.watchdog", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastAck = CACurrentMediaTime()
    private var ackPending = false
    private var stallStart: CFTimeInterval?
    private var worstMilliseconds = 0
    private let threshold: CFTimeInterval = 0.12

    func start() {
        stop()
        lock.lock()
        lastAck = CACurrentMediaTime()
        ackPending = false
        stallStart = nil
        worstMilliseconds = 0
        lock.unlock()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func takeWorstBlockMilliseconds() -> Int {
        lock.lock(); defer { lock.unlock() }
        let value = worstMilliseconds
        worstMilliseconds = 0
        return value
    }

    private func tick() {
        let now = CACurrentMediaTime()
        lock.lock()
        let gap = now - lastAck
        if gap > threshold, stallStart == nil { stallStart = lastAck }
        let shouldRequest = !ackPending
        if shouldRequest { ackPending = true }
        lock.unlock()
        guard shouldRequest else { return }
        DispatchQueue.main.async { [weak self] in self?.acknowledge() }
    }

    private func acknowledge() {
        let now = CACurrentMediaTime()
        lock.lock()
        lastAck = now
        ackPending = false
        var finished: CFTimeInterval?
        if let start = stallStart {
            finished = now - start
            stallStart = nil
        }
        if let finished { worstMilliseconds = max(worstMilliseconds, Int(finished * 1000)) }
        lock.unlock()
        // Longer than this is the app having been suspended, not a stall.
        if let finished, finished < 10 {
            PlaybackLog.shared.log("main", "MAIN-THREAD STALL \(Int(finished * 1000))ms")
        }
    }
}
#endif
