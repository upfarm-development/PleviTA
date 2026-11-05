
import Foundation

public enum BulkRedownloadPolicy {
    public struct Selection: Equatable, Sendable {
        /// Ids to delete and queue again, in the order given.
        public var redownloadIds: [String]
        /// How many were left alone, and in which codecs, for the confirmation to say so.
        public var skippedCount: Int
        public var skippedCodecs: [VideoCodec]
    }

    /// A video with no readable codec is never skipped: not knowing what it is in is not a
    /// reason to leave it.
    public static func select(_ videos: [Video], skipping skipped: Set<VideoCodec>) -> Selection {
        var ids: [String] = []
        var skippedCount = 0
        var seen: Set<VideoCodec> = []
        for video in videos {
            if let codec = video.videoCodec, skipped.contains(codec) {
                skippedCount += 1
                seen.insert(codec)
            } else {
                ids.append(video.id)
            }
        }
        return Selection(
            redownloadIds: ids, skippedCount: skippedCount,
            skippedCodecs: VideoCodec.allCases.filter(seen.contains))
    }
}
