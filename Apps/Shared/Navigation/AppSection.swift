
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, channels, playlists, search, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .channels: "Channels"
        case .playlists: "Playlists"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .channels: "person.2.square.stack"
        case .playlists: "list.and.film"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}
