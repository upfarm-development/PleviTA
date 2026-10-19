// Each section's own NavigationStack (AppShellView.swift) pushes these via `.navigationDestination(for: Route.self)`.
enum Route: Hashable, Codable {
    case video(String, fromPlaylistId: String? = nil)
    case channel(String)
    case playlist(String)
}
