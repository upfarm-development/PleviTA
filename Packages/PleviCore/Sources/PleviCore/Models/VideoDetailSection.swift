// The video-detail screen's sections.

import Foundation

public enum VideoDetailSection: String, CaseIterable, Sendable, Codable, Identifiable {
    case stats
    case actions
    case fileDetails
    case description
    case inThisPlaylist
    case comments
    case similarVideos

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stats: "Stats"
        case .actions: "Actions"
        case .fileDetails: "File details"
        case .description: "Description"
        case .inThisPlaylist: "In this playlist"
        case .comments: "Comments"
        case .similarVideos: "Similar videos"
        }
    }
}
