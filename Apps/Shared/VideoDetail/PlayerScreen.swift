
import SwiftUI
import VideoToolbox
import PleviCore
import PleviFallbackPlayer

struct PlayerScreen: View {
    let videos: [Video]
    let startPosition: Double?
    let client: TAClient
    let imageLoader: ImageLoader?
    /// `AppSettings.autoPlayNext`.
    let autoPlayNext: Bool
    /// Settings → Playback → "Compatibility player". Read once, same rule as `autoPlayNext`
    /// above — a live change mid-session doesn't retroactively affect an engine already chosen.
    let fallbackPlayerMode: @MainActor () -> FallbackPlayerMode
    /// The loopback proxy the fallback engine's media requests are routed through — see `LoopbackMediaProxy`'s own doc comment.
    let mediaProxy: LoopbackMediaProxy?
    /// Recorded into on every `start` so Continue Watching can lead with what was last played on this Apple TV.
    let playbackHistory: PlaybackHistory?
    var onFinished: (Double, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: VideoPlaybackController
    @State private var currentIndex: Int
    @State private var didStart = false
    @State private var didFinish = false
    private final class FinishOnce { var fired = false }
    @State private var finishOnce = FinishOnce()

    /// Computed once per process, not per video — `VTIsHardwareDecodeSupported` is a real (if
    /// fast) VideoToolbox call, and the answer only depends on the device, never the file. Same
    /// pattern as `PlaybackSession.hardwareAV1` on iOS.
    private static let hardwareAV1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)

    init(
        videos: [Video],
        startIndex: Int = 0,
        startPosition: Double? = nil,
        client: TAClient,
        imageLoader: ImageLoader?,
        autoPlayNext: Bool,
        fallbackPlayerMode: @escaping @MainActor () -> FallbackPlayerMode,
        isSponsorBlockEnabled: @escaping @MainActor () -> Bool,
        sponsorBlockCategories: @escaping @MainActor () -> Set<SponsorCategory>,
        mediaProxy: LoopbackMediaProxy?,
        playbackHistory: PlaybackHistory?,
        onFinished: @escaping (Double, Bool) -> Void = { _, _ in }
    ) {
        self.videos = videos
        self.startPosition = startPosition
        self.client = client
        self.imageLoader = imageLoader
        self.autoPlayNext = autoPlayNext
        self.fallbackPlayerMode = fallbackPlayerMode
        self.mediaProxy = mediaProxy
        self.playbackHistory = playbackHistory
        self.onFinished = onFinished
        let clamped = videos.isEmpty ? 0 : min(max(startIndex, 0), videos.count - 1)
        _currentIndex = State(initialValue: clamped)
        let freshController = VideoPlaybackController(
            client: client,
            imageLoader: imageLoader,
            isSponsorBlockEnabled: isSponsorBlockEnabled,
            sponsorBlockCategories: sponsorBlockCategories,
            fallbackEngineFactory: makeFallbackPlayerEngine,
            proxy: mediaProxy,
            fallbackPlayerMode: fallbackPlayerMode,
            hardwareAV1: Self.hardwareAV1,
            playbackHistory: playbackHistory
        )
        // Synchronous, before this screen's first render — see `VideoPlaybackController.prepareEngine(for:)`'s own doc comment.
        if videos.indices.contains(clamped) {
            freshController.prepareEngine(for: videos[clamped])
        }
        _controller = State(initialValue: freshController)
    }

    private var currentVideo: Video? {
        guard videos.indices.contains(currentIndex) else { return nil }
        return videos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let nativeEngine = controller.nativeEngine {
                PlayerView(engine: nativeEngine, onRequestDismiss: closeAndFinish, skipNotice: controller.skipNotice)
                    .ignoresSafeArea()
            } else if controller.engineKind == .fallback {
                #if os(tvOS)
                FallbackPlayerViewTV(controller: controller, onRequestDismiss: closeAndFinish)
                    .ignoresSafeArea()
                #endif
            }

            if let problem = playbackProblem {
                problemView(problem)
            }
        }
        #if os(tvOS)
        // The remote's Menu button is the way out of this screen.
        .onExitCommand { closeAndFinish() }
        #endif
        .task {
            guard !didStart, let video = currentVideo else { return }
            didStart = true
            controller.onEnded = { Task { await handleEnded() } }
            await controller.start(video: video, startPosition: startPosition)
            await matchDisplayModeToCurrentItem()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            let position = controller.engine?.currentTime ?? 0
            Task { await controller.reportProgress(position: position, force: true) }
        }
        .onDisappear {
            // Both read now, synchronously: `controller.stop()` below runs before this closure's `Task` body ever does, and it drops the player item.
            let finalPosition = controller.engine?.currentTime ?? 0
            let reachedEnd = controller.engine?.state == .ended
            Task {
                await controller.reportProgress(position: finalPosition, force: true)
                finishIfNeeded(position: finalPosition, watched: reachedEnd)
            }
            controller.stop()
            // Hand the television back: without this the Apple TV stays in the mode the last
            // video asked for, and every screen after this one inherits it.
            #if os(tvOS)
            TVDisplayModeMatcher.clear()
            #endif
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    // MARK: - Telling the user why nothing is playing

    /// Whether the message is worth drawing at all, and whether anything can
    /// be retried — the two cases differ in more than their text.
    private struct PlaybackProblem {
        var message: String
        /// `false` when there is nothing to restart: an unsupported file on a
        /// platform with no fallback engine will fail identically every time,
        /// and a Retry that visibly does nothing is worse than none.
        var canRetry: Bool
        /// `true` once AVKit is on screen underneath.
        var isOverPlayer: Bool
    }

    private var playbackProblem: PlaybackProblem? {
        // Checked first: this is the case where no engine exists at all, so
        // there is nothing behind the message and nothing to retry.
        if let notice = controller.unsupportedNotice {
            return PlaybackProblem(message: notice, canRetry: false, isOverPlayer: false)
        }
        if let failure = controller.lastFailure {
            return PlaybackProblem(
                message: failure.message,
                canRetry: true,
                isOverPlayer: controller.nativeEngine != nil
            )
        }
        return nil
    }

    @ViewBuilder
    private func problemView(_ problem: PlaybackProblem) -> some View {
        if problem.isOverPlayer {
            // AVKit is mounted and may be drawing its own error, or — for a file whose metadata lied about its codecs.
            VStack {
                Text(problem.message)
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 60)
                    .padding(.top, 80)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                Text("Can't Play This Video")
                    .pleviSectionHeading()
                Text(problem.message)
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 80)
                if problem.canRetry {
                    Button("Try Again") { retry() }
                }
                Button("Close", action: closeAndFinish)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Restarts the whole item rather than nudging the existing engine.
    private func retry() {
        guard let video = currentVideo else { return }
        Task { await controller.start(video: video, startPosition: controller.engine?.currentTime) }
    }

    private func handleEnded() async {
        let nextIndex = currentIndex + 1
        guard autoPlayNext, videos.indices.contains(nextIndex) else {
            closeAndFinish()
            return
        }
        currentIndex = nextIndex
        guard let next = currentVideo else {
            closeAndFinish()
            return
        }
        let resumePosition = ResumePolicy.silentStartPosition(
            isWatched: next.player?.watched == true,
            position: next.player?.position,
            duration: next.player?.duration)
        await controller.start(video: next, startPosition: resumePosition)
        // Re-asked per entry, not once per screen: a queue can move from a 60fps clip to a
        // 24fps film, and the television should follow it.
        await matchDisplayModeToCurrentItem()
    }

    private func matchDisplayModeToCurrentItem() async {
        #if os(tvOS)
        guard let nativeEngine = controller.nativeEngine else { return }
        TVDisplayModeMatcher.apply(await nativeEngine.preferredDisplayCriteria())
        #endif
    }

    private func finishIfNeeded(position: Double, watched: Bool) {
        guard !finishOnce.fired else { return }
        finishOnce.fired = true
        onFinished(position, watched)
    }

    private func closeAndFinish() {
        guard !didFinish else { return }
        didFinish = true
        let finalPosition = controller.engine?.currentTime ?? 0
        let watched = controller.engine?.state == .ended
        // Silence it now rather than at `.onDisappear`, which only fires once the cover's dismissal animation has finished.
        Task { await controller.reportProgress(position: finalPosition, force: true) }
        controller.stop()
        // Through the once-guard, never `onFinished` directly: the `dismiss()` below fires `.onDisappear`, which would otherwise call it a second time.
        finishIfNeeded(position: finalPosition, watched: watched)
        dismiss()
    }
}
