
import Foundation

public enum DownloadValidation {
    public enum Verdict: Sendable, Equatable {
        case ok
        /// The bytes on disk are not the media file that was asked for — a gate's login page,
        /// a truncated transfer, or a response for something else entirely. `reason` is a
        /// short, plain-words explanation for a failed-download subtitle.
        case notTheFileWeAskedFor(reason: String)
        /// A 401/403 — the gate or Tube Archivist itself rejected the request.
        case retryableAuthFailure
    }

    public static func validate(
        status: Int,
        contentType: String?,
        first12Bytes: Data,
        byteCount: Int,
        expected: Int?
    ) -> Verdict {
        if status == 401 || status == 403 {
            return .retryableAuthFailure
        }
        guard (200..<300).contains(status) else {
            return .notTheFileWeAskedFor(reason: "the server answered \(status)")
        }
        if let contentType, contentType.lowercased().contains("text/html") {
            return .notTheFileWeAskedFor(reason: "the server sent a web page instead of the video")
        }
        if looksLikeWebPage(first12Bytes) {
            return .notTheFileWeAskedFor(reason: "the server sent a web page instead of the video")
        }
        if let expected, byteCount != expected {
            return .notTheFileWeAskedFor(reason: "received \(byteCount) bytes, the server said \(expected)")
        }
        return .ok
    }

    /// How many bytes the finished file should be, given the response that produced it.
    public static func expectedTotalBytes(status: Int, contentLength: String?, contentRange: String?) -> Int? {
        if status == 206 {
            guard let contentRange, let slash = contentRange.lastIndex(of: "/") else { return nil }
            let total = contentRange[contentRange.index(after: slash)...]
            // "*" is legal in Content-Range when the server does not know the total.
            return Int(total)
        }
        return contentLength.flatMap { Int($0) }
    }

    /// Same test as `TAClient.looksLikeWebPage`, applied to a raw byte peek rather than a
    /// `Data`+`HTTPURLResponse` pair — a media download's `Content-Type` is checked separately
    /// above, so this only needs the body-sniffing half.
    private static func looksLikeWebPage(_ bytes: Data) -> Bool {
        guard let first = bytes.first(where: { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D) }) else {
            return false
        }
        return first == UInt8(ascii: "<")
    }
}
