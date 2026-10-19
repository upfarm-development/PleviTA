
import Foundation

public enum OfflineBundle {
    /// The paths that make up one video's bundle, rooted at
    /// `<root>/<serverDigest>/<youtubeId>/`.
    public struct Layout: Sendable, Equatable {
        public let directory: URL

        public init(directory: URL) {
            self.directory = directory
        }

        public var videoJSON: URL { directory.appendingPathComponent("video.json") }
        public var recordJSON: URL { directory.appendingPathComponent("record.json") }
        public var thumbnail: URL { directory.appendingPathComponent("thumb.jpg") }

        /// The media file's own path, given the server's filename (extension preserved —
        /// see this file's own top comment on why it's never a UUID).
        public func mediaFile(named filename: String) -> URL {
            directory.appendingPathComponent(filename)
        }

        public func subtitleFile(named filename: String) -> URL {
            directory.appendingPathComponent(filename)
        }
    }

    public static func serverDirectory(root: URL, serverDigest: String) -> URL {
        root.appendingPathComponent(serverDigest, isDirectory: true)
    }

    public static func layout(root: URL, serverDigest: String, youtubeId: String) -> Layout {
        Layout(directory: serverDirectory(root: root, serverDigest: serverDigest)
            .appendingPathComponent(youtubeId, isDirectory: true))
    }

    /// The server's own filename for a video's media file, taken from `mediaUrl`'s last path component — never a UUID.
    public static func mediaFilename(for video: Video) -> String {
        guard let mediaUrl = video.mediaUrl else { return "\(video.youtubeId).mp4" }
        let name = mediaUrl.split(separator: "/").last.map(String.init) ?? ""
        let withoutQuery = name.split(separator: "?", maxSplits: 1).first.map(String.init) ?? name
        return withoutQuery.isEmpty ? "\(video.youtubeId).mp4" : withoutQuery
    }

    public static func subtitleFilename(for subtitle: Subtitle) -> String? {
        guard let mediaUrl = subtitle.mediaUrl else { return nil }
        let name = mediaUrl.split(separator: "/").last.map(String.init) ?? ""
        let withoutQuery = name.split(separator: "?", maxSplits: 1).first.map(String.init) ?? name
        return withoutQuery.isEmpty ? nil : withoutQuery
    }

    public static func strippedForStorage(_ video: Video) -> Video {
        var stripped = video
        if let player = video.player {
            stripped.player = VideoPlayerState(
                duration: player.duration,
                durationStr: player.durationStr,
                watched: nil,
                position: nil,
                progress: nil
            )
        }
        return stripped
    }

    /// Encodes `video` for `video.json`, stripped per `strippedForStorage`.
    public static func encodeVideoJSON(_ video: Video) throws -> Data {
        try JSONEncoder().encode(strippedForStorage(video))
    }

    public static func decodeVideoJSON(_ data: Data) throws -> Video {
        try JSONDecoder().decode(Video.self, from: data)
    }

    public static func encodeRecordJSON(_ record: OfflineVideoRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(record)
    }

    public static func decodeRecordJSON(_ data: Data) throws -> OfflineVideoRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OfflineVideoRecord.self, from: data)
    }
}
