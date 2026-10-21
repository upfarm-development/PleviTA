
import Foundation
import os

public final class PlaybackLog: @unchecked Sendable {
    public static let shared = PlaybackLog()

    /// `UserDefaults` key behind Settings → Playback → "Detailed playback logging". On by default:
    /// the log only helps if it was already running when the problem happened.
    public static let enabledKey = "playbackLogging.enabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Short id for this launch, repeated on every line so that two launches in one file (or a file
    /// pasted into a chat out of order) can still be told apart.
    public let launchID = String(UUID().uuidString.prefix(6)).lowercased()

    private let osLogger = Logger(subsystem: "com.plevi.ta", category: "playback")
    private let queue = DispatchQueue(label: "com.plevi.ta.playbacklog", qos: .utility)
    private let directory: URL
    private let maxFileBytes: UInt64
    private let keptFiles: Int

    // Touched only on `queue`.
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public init(directory: URL? = nil, maxFileBytes: UInt64 = 4_000_000, keptFiles: Int = 4) {
        self.directory = directory ?? Self.defaultDirectory()
        self.maxFileBytes = maxFileBytes
        self.keptFiles = max(1, keptFiles)
    }

    private static func defaultDirectory() -> URL {
        return StorageLocation.base.appendingPathComponent("PlaybackLogs", isDirectory: true)
    }

    // MARK: - Writing

    /// `message` is an autoclosure so a disabled log costs nothing, not even the string building.
    public func log(_ category: String, _ message: @autoclosure () -> String, force: Bool = false) {
        guard force || Self.isEnabled else { return }
        let text = message()
        let date = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        osLogger.info("[\(category, privacy: .public)] \(text, privacy: .public)")
        queue.async { [self] in
            append(date: date, uptime: uptime, category: category, text: text)
        }
    }

    private func append(date: Date, uptime: TimeInterval, category: String, text: String) {
        // `u=` is seconds since boot: monotonic and unaffected by clock changes, so it orders lines
        // correctly across a timezone change or an NTP step, and lines from two sources (this file
        // and a Console capture) can be lined up exactly.
        let line = "\(formatter.string(from: date)) u=\(String(format: "%.3f", uptime)) \(launchID) \(category) \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            let handle = try openHandle()
            try handle.write(contentsOf: data)
            currentSize += UInt64(data.count)
            if currentSize >= maxFileBytes { rotate() }
        } catch {
            // Logging must never take playback down with it; drop the handle and reopen next time.
            self.handle = nil
        }
    }

    private var currentURL: URL { directory.appendingPathComponent("playback.log") }

    private func rotatedURL(_ index: Int) -> URL { directory.appendingPathComponent("playback.\(index).log") }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Nothing here is worth an iCloud/iTunes backup, and the log can be megabytes.
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        if !FileManager.default.fileExists(atPath: currentURL.path) {
            FileManager.default.createFile(atPath: currentURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: currentURL)
        currentSize = (try? handle.seekToEnd()) ?? 0
        self.handle = handle
        return handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedURL(keptFiles - 1))
        if keptFiles > 1 {
            for index in stride(from: keptFiles - 2, through: 1, by: -1) {
                try? fm.moveItem(at: rotatedURL(index), to: rotatedURL(index + 1))
            }
            try? fm.moveItem(at: currentURL, to: rotatedURL(1))
        } else {
            try? fm.removeItem(at: currentURL)
        }
        currentSize = 0
    }

    // MARK: - Reading

    /// Every file, oldest first.
    private func orderedFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for index in stride(from: keptFiles - 1, through: 1, by: -1) where fm.fileExists(atPath: rotatedURL(index).path) {
            files.append(rotatedURL(index))
        }
        if fm.fileExists(atPath: currentURL.path) { files.append(currentURL) }
        return files
    }

    /// Bytes currently on disk, for Settings.
    public func sizeOnDisk() -> Int64 {
        queue.sync {
            orderedFiles().reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }

    /// One text file holding the whole history, oldest first, in the temporary directory — what the
    /// share sheet hands over. Synchronous on the log queue, so it includes every line logged before
    /// the call. `nil` when there is nothing to share.
    public func exportCombined() -> URL? {
        queue.sync {
            let files = orderedFiles()
            guard !files.isEmpty else { return nil }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("plevi-playback-log-\(stamp).txt")
            FileManager.default.createFile(atPath: out.path, contents: nil)
            guard let outHandle = try? FileHandle(forWritingTo: out) else { return nil }
            defer { try? outHandle.close() }
            for url in files {
                if let data = try? Data(contentsOf: url) { try? outHandle.write(contentsOf: data) }
            }
            return out
        }
    }

    public func clear() {
        queue.sync {
            try? handle?.close()
            handle = nil
            currentSize = 0
            for url in orderedFiles() { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Blocks until everything logged so far is on disk. For tests and for export.
    public func flush() {
        queue.sync {}
    }

    // MARK: - Redaction

    /// `scheme://host:port/path` — no userinfo, query or fragment. The only way a URL should be
    /// written to this log.
    public static func redacted(_ url: URL?) -> String {
        guard let url else { return "nil" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "<unparseable url>" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<unparseable url>"
    }

    /// Header names only, sorted; the values are credentials.
    public static func headerNames(_ headers: [String: String]) -> String {
        headers.isEmpty ? "none" : headers.keys.sorted().joined(separator: ",")
    }
}

/// "At most once every N seconds" per key, callable from any thread.
final class LogThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: [String: TimeInterval] = [:]

    func allows(_ key: String, every interval: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        if let previous = last[key], now - previous < interval { return false }
        last[key] = now
        return true
    }
}
