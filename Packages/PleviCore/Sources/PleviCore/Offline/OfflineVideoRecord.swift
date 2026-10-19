
import Foundation

/// One video's place in the offline shelf, independent of whether its bytes have finished
/// arriving yet.
public struct OfflineVideoRecord: Codable, Sendable, Equatable {
    /// Where this download currently stands.
    public enum State: String, Codable, Sendable {
        case downloading
        case complete
        case failed
    }

    public enum Reason: String, Codable, Sendable {
        case savedByUser
        case keptByRule
    }

    public var youtubeId: String
    public var state: State
    public var reason: Reason
    public var savedAt: Date
    public var mediaFilename: String
    /// `Content-Length` from the download response, once known — **not** `Video.mediaSize`.
    public var expectedByteCount: Int?
    /// Bytes actually written to disk so far. The one number `OfflineVideosView`'s progress
    /// bar and "downloaded" test may use — never `receivedByteCount == video.mediaSize`.
    public var receivedByteCount: Int
    /// Set only on `.failed`, for a retry affordance's subtitle. `nil` in every other state.
    public var lastError: String?
    public var subtitleFilenames: [String]
    public var isOrphaned: Bool
    /// This video's chosen place in the download queue — see `OfflineDownloadQueue.order`.
    public var queuePosition: Int?

    public init(
        youtubeId: String,
        state: State,
        reason: Reason,
        savedAt: Date,
        mediaFilename: String,
        expectedByteCount: Int? = nil,
        receivedByteCount: Int = 0,
        lastError: String? = nil,
        subtitleFilenames: [String] = [],
        isOrphaned: Bool = false,
        queuePosition: Int? = nil
    ) {
        self.youtubeId = youtubeId
        self.state = state
        self.reason = reason
        self.savedAt = savedAt
        self.mediaFilename = mediaFilename
        self.expectedByteCount = expectedByteCount
        self.receivedByteCount = receivedByteCount
        self.lastError = lastError
        self.subtitleFilenames = subtitleFilenames
        self.isOrphaned = isOrphaned
        self.queuePosition = queuePosition
    }

    enum CodingKeys: String, CodingKey {
        case youtubeId, state, reason, savedAt, mediaFilename, expectedByteCount, receivedByteCount, lastError, subtitleFilenames, isOrphaned, queuePosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        youtubeId = try container.decode(String.self, forKey: .youtubeId)
        state = (try? container.decodeIfPresent(State.self, forKey: .state)) ?? .failed
        reason = (try? container.decodeIfPresent(Reason.self, forKey: .reason)) ?? .savedByUser
        savedAt = (try? container.decodeIfPresent(Date.self, forKey: .savedAt)) ?? .distantPast
        mediaFilename = (try? container.decodeIfPresent(String.self, forKey: .mediaFilename)) ?? "\(youtubeId).mp4"
        expectedByteCount = try? container.decodeIfPresent(Int.self, forKey: .expectedByteCount)
        receivedByteCount = (try? container.decodeIfPresent(Int.self, forKey: .receivedByteCount)) ?? 0
        lastError = try? container.decodeIfPresent(String.self, forKey: .lastError)
        subtitleFilenames = (try? container.decodeIfPresent([String].self, forKey: .subtitleFilenames)) ?? []
        isOrphaned = (try? container.decodeIfPresent(Bool.self, forKey: .isOrphaned)) ?? false
        queuePosition = try? container.decodeIfPresent(Int.self, forKey: .queuePosition)
    }
}
