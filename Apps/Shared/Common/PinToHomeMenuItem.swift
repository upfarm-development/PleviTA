
import SwiftUI
import PleviCore

enum PinTarget {
    case playlist(Playlist)
    case channel(Channel)

    fileprivate var kind: PinnedItem.Kind {
        switch self {
        case .playlist: .playlist
        case .channel: .channel
        }
    }

    fileprivate var id: String {
        switch self {
        case .playlist(let playlist): playlist.id
        case .channel(let channel): channel.id
        }
    }
}

struct PinToHomeMenuItem: View {
    let target: PinTarget

    @Environment(PinnedItems.self) private var pinnedItems

    var body: some View {
        if pinnedItems.isPinned(target.kind, id: target.id) {
            Button {
                pinnedItems.unpin(target.kind, id: target.id)
            } label: {
                Label("Unpin from Home", systemImage: "pin.slash")
            }
        } else {
            // D5: disabled rather than hidden, with a one-line reason — pinning is otherwise
            // always available, so a menu item that just vanishes at 30 pins would look like a
            // bug rather than a limit.
            Button {
                pin()
            } label: {
                Label("Pin to Home", systemImage: "pin")
            }
            .disabled(pinnedItems.isFull)
            if pinnedItems.isFull {
                Text("Home is full")
            }
        }
    }

    private func pin() {
        switch target {
        case .playlist(let playlist): pinnedItems.pin(playlist)
        case .channel(let channel): pinnedItems.pin(channel)
        }
    }
}

#if os(iOS)
/// The menu with an explicit preview, for the reason `VideoContextMenuPreview` gives.
private struct PinToHomeContextMenu: ViewModifier {
    let target: PinTarget
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = PleviTheme.palette(for: colorScheme)
        content.contextMenuWithPreview {
            PinToHomeMenuItem(target: target)
        } preview: {
            Group {
                switch target {
                case .playlist(let playlist): PlaylistCard(playlist: playlist).frame(width: 300)
                case .channel(let channel): ChannelCard(channel: channel).frame(width: 180)
                }
            }
            .padding(12)
            .background(palette.canvas)
        }
    }
}
#endif

extension View {
    /// Long-press menu for a playlist/channel card or row. Attach to the `Button`/
    /// `NavigationLink` itself — never to its label — same rule as `videoActionsContextMenu`
    /// (VideoActions.swift's own doc comment has the full reasoning).
    func pinToHomeContextMenu(_ target: PinTarget) -> some View {
        #if os(iOS)
        modifier(PinToHomeContextMenu(target: target))
        #else
        contextMenu { PinToHomeMenuItem(target: target) }
        #endif
    }
}

#Preview {
    PinToHomeMenuItem(target: .playlist(.previewPlaylist))
        .environment(PinnedItems(scope: "", cloud: nil))
        .padding()
}
