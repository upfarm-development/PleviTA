// What `TAClient.redownload(videoIds:)` did to a set of videos, enough for the caller to say plainly how far it got.

import Foundation

public struct BulkRedownloadResult: Sendable, Equatable {
    /// Gone from the server's library, in the order they were deleted.
    public var deleted: [String] = []
    /// Never touched, because an error or a cancel ended the run before their turn.
    public var notAttempted: [String] = []
    /// Why the run stopped early, when an error was the reason.
    public var stopError: TAError?
    /// The `deleted` videos are now on the download queue.
    public var queued = false
    /// Set when the delete worked but adding them to the queue did not.
    public var queueError: TAError?

    public init() {}
}
