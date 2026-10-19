// Holds the one playback controller for as long as its playback lasts, which is longer than the video screen lasts.

#if os(iOS)
import SwiftUI
import VideoToolbox
import PleviCore
import PleviFallbackPlayer

@MainActor
@Observable
final class PlaybackSession {
    /// The controller for whichever video is currently loaded, or `nil` before
    /// anything has played.
    private(set) var controller: VideoPlaybackController?
    /// Which video `controller` belongs to, so a return to the same video
    /// reuses the live session instead of building a second one over the top
    /// of it.
    private(set) var videoId: String?
    /// One loopback proxy shared by every `VideoPlaybackController` this session ever builds
    /// — `LoopbackMediaProxy`'s own doc comment: it's a listener on an ephemeral port, cheap
    /// to keep running for the app's whole lifetime rather than starting/stopping per video.
    private let mediaProxy = LoopbackMediaProxy()
    /// Computed once per process, not per video — `VTIsHardwareDecodeSupported` is a real
    /// (if fast) VideoToolbox call, and the answer only depends on the device, never the file.
    private static let hardwareAV1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)

    /// The controller for `videoId`, creating one if this is a different video from whatever was loaded before.
    func controller(
        for videoId: String,
        client: TAClient,
        imageLoader: ImageLoader?,
        fallbackPlayerMode: @escaping @MainActor () -> FallbackPlayerMode,
        isSponsorBlockEnabled: @escaping @MainActor () -> Bool,
        sponsorBlockCategories: @escaping @MainActor () -> Set<SponsorCategory>,
        playbackHistory: PlaybackHistory? = nil,
        offlineMediaProvider: (@MainActor (String) -> URL?)? = nil,
        offlineOutbox: OfflinePlaybackLedger? = nil,
        offlineSubtitlesProvider: (@MainActor (String) -> [ExternalSubtitle])? = nil
    ) -> VideoPlaybackController {
        if let controller, self.videoId == videoId {
            return controller
        }
        // The outgoing controller is about to be dropped for a different video.
        if let outgoing = controller, !outgoing.isPictureInPicture {
            outgoing.stop()
        }
        let fresh = VideoPlaybackController(
            client: client,
            imageLoader: imageLoader,
            isSponsorBlockEnabled: isSponsorBlockEnabled,
            sponsorBlockCategories: sponsorBlockCategories,
            fallbackEngineFactory: makeFallbackPlayerEngine,
            proxy: mediaProxy,
            fallbackPlayerMode: fallbackPlayerMode,
            hardwareAV1: Self.hardwareAV1,
            playbackHistory: playbackHistory,
            offlineMediaProvider: offlineMediaProvider,
            offlineOutbox: offlineOutbox,
            offlineSubtitlesProvider: offlineSubtitlesProvider
        )
        controller = fresh
        self.videoId = videoId
        return fresh
    }
}
#endif
