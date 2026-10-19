
#if os(iOS)
import SwiftUI
import PleviCore

struct AddToPlaylistSheet: View {
    let video: Video
    let coordinator: VideoActionsCoordinator

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var state: LoadState<[Playlist]> = .idle

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard let client = authStore.client else { return }
            state = .loading
            do {
                state = .loaded(try await loadAllCustomPlaylists(client))
            } catch {
                state = .failed((error as? TAError) ?? .network(error.localizedDescription))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "Couldn't load your playlists.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondary)
                Button("Retry") {
                    Task {
                        guard let client = authStore.client else { return }
                        state = .loading
                        do {
                            state = .loaded(try await loadAllCustomPlaylists(client))
                        } catch {
                            state = .failed((error as? TAError) ?? .network(error.localizedDescription))
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        case .loaded(let playlists):
            if playlists.isEmpty {
                ContentUnavailableView(
                    VideoActionsCoordinator.noCustomPlaylistsTitle,
                    systemImage: "text.badge.plus",
                    description: Text(VideoActionsCoordinator.noCustomPlaylistsMessage)
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(playlists) { playlist in
                    Button {
                        Task {
                            await coordinator.add(video, to: playlist)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(playlist.playlistName ?? "Untitled playlist")
                                .foregroundStyle(palette.ink)
                            Spacer()
                            if video.playlist?.contains(playlist.playlistId) == true {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
