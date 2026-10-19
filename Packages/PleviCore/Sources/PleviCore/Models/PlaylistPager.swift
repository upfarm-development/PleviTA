
import Foundation

public struct PlaylistPagerEntry: Sendable, Equatable, Identifiable {
    public var video: Video
    public var position: Int
    public var isCurrent: Bool

    public var id: String { video.id }

    public init(video: Video, position: Int, isCurrent: Bool) {
        self.video = video
        self.position = position
        self.isCurrent = isCurrent
    }
}

public struct PlaylistPagerPage: Sendable, Equatable, Identifiable {
    public var playlistId: String
    public var playlistName: String?
    public var currentPosition: Int
    public var totalCount: Int
    public var entries: [PlaylistPagerEntry]

    public var id: String { playlistId }

    public init(
        playlistId: String,
        playlistName: String?,
        currentPosition: Int,
        totalCount: Int,
        entries: [PlaylistPagerEntry]
    ) {
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.currentPosition = currentPosition
        self.totalCount = totalCount
        self.entries = entries
    }
}
