// The three things "File details" has ever actually shown — size, video stream, audio stream — as plain strings over a `Video`.

import Foundation

public enum VideoFileFacts {
    /// `"4.5 GiB"`, or nil when the server reported no size.
    public static func fileSize(_ video: Video) -> String? {
        guard let size = video.mediaSize, size > 0 else { return nil }
        return PleviFormatting.byteCount(size)
    }

    /// `"h264 · 4.2 Mbps · 1920×1080"` — whichever parts the server actually sent.
    public static func videoStream(_ video: Video) -> String? {
        detail(stream(video, type: "video"), includeResolution: true)
    }

    /// `"opus · 128 kbps"` — no resolution, which an audio stream does not have.
    public static func audioStream(_ video: Video) -> String? {
        detail(stream(video, type: "audio"), includeResolution: false)
    }

    public static func videoStreamCompact(_ video: Video, locale: Locale = .current) -> String? {
        guard let stream = stream(video, type: "video") else { return nil }
        var parts: [String] = []
        if let codec = stream.codec, !codec.isEmpty { parts.append(codec) }
        if let height = stream.height, height > 0 { parts.append("\(height)p") }
        if let bitrate = stream.bitrate, bitrate > 0 {
            parts.append(PleviFormatting.bitRate(bitsPerSecond: bitrate, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func audioStreamCompact(_ video: Video, locale: Locale = .current) -> String? {
        guard let stream = stream(video, type: "audio") else { return nil }
        var parts: [String] = []
        if let codec = stream.codec, !codec.isEmpty { parts.append(codec) }
        if let bitrate = stream.bitrate, bitrate > 0 {
            parts.append(PleviFormatting.bitRate(bitsPerSecond: bitrate, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func stream(_ video: Video, type: String) -> VideoStream? {
        video.streams?.first { $0.type == type }
    }

    /// Nil rather than an empty string when nothing is known, so a caller can drop the row
    /// entirely instead of rendering a label with nothing after it.
    private static func detail(_ stream: VideoStream?, includeResolution: Bool) -> String? {
        guard let stream else { return nil }
        var parts: [String] = []
        if let codec = stream.codec, !codec.isEmpty { parts.append(codec) }
        if let bitrate = stream.bitrate, bitrate > 0 {
            parts.append(PleviFormatting.dataRate(bitsPerSecond: bitrate))
        }
        if includeResolution, let width = stream.width, let height = stream.height {
            parts.append("\(width)×\(height)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
