// Resolves `Route` (Route.swift) to an actual view.

import SwiftUI
import PleviCore

struct RouteDestinationView: View {
    let route: Route
    var navigate: (Route) -> Void = { _ in }

    var body: some View {
        switch route {
        case .video(let id, let fromPlaylistId):
            // `fromPlaylistId` defaults the multi-playlist pager's own selection — see `Route.swift`'s and `PlaylistPagerView.swift`'s doc comments.
            VideoDetailView(videoId: id, navigate: navigate, fromPlaylistId: fromPlaylistId)
        case .channel(let id):
            ChannelDetailView(channelId: id, navigate: navigate)
        case .playlist(let id):
            PlaylistDetailView(playlistId: id, navigate: navigate)
        }
    }
}

#Preview {
    NavigationStack {
        RouteDestinationView(route: .channel("preview-channel"))
    }
    .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
    .environment(AppSettings())
}
