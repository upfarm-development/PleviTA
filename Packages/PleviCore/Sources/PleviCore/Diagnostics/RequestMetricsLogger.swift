// Per-request timing for `TAClient`, written to `PlaybackLog`.

import Foundation

final class RequestMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: URLSessionTaskMetrics?

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); collected = metrics; lock.unlock()
    }

    /// `proto=h2 reused=true dns=0ms connect=0ms tls=0ms ttfb=41ms body=12ms path=wifi-ish flags`
    var summary: String {
        lock.lock(); let metrics = collected; lock.unlock()
        guard let metrics, let transaction = metrics.transactionMetrics.last else { return "metrics=none" }
        func ms(_ start: Date?, _ end: Date?) -> String {
            guard let start, let end else { return "-" }
            return "\(Int(end.timeIntervalSince(start) * 1000))ms"
        }
        var parts = [
            "proto=\(transaction.networkProtocolName ?? "?")",
            "reused=\(transaction.isReusedConnection)",
            "dns=\(ms(transaction.domainLookupStartDate, transaction.domainLookupEndDate))",
            "connect=\(ms(transaction.connectStartDate, transaction.connectEndDate))",
            "tls=\(ms(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate))",
            "ttfb=\(ms(transaction.requestStartDate, transaction.responseStartDate))",
            "body=\(ms(transaction.responseStartDate, transaction.responseEndDate))",
            "cellular=\(transaction.isCellular)",
            "expensive=\(transaction.isExpensive)",
            "constrained=\(transaction.isConstrained)",
            "remote=\(transaction.remoteAddress ?? "-")",
        ]
        if metrics.redirectCount > 0 { parts.append("redirects=\(metrics.redirectCount)") }
        if metrics.transactionMetrics.count > 1 { parts.append("transactions=\(metrics.transactionMetrics.count)") }
        return parts.joined(separator: " ")
    }
}
