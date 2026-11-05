// BulkDeleteResult.swift
//
// What `TAClient.deleteVideos(ids:ignoring:)` did to a set of videos.

import Foundation

public struct BulkDeleteResult: Sendable, Equatable {
    /// Gone from the server's library, in the order they were deleted.
    public var deleted: [String] = []
    /// Never touched, because an error or a cancel ended the run before their turn.
    public var notAttempted: [String] = []
    /// Why the run stopped early, when an error was the reason.
    public var stopError: TAError?
    /// Deleted, but marking them ignored failed. Only counted when ignoring was asked for.
    public var ignoreFailures = 0

    public init() {}
}
