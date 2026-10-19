
#if os(iOS)
import SwiftUI
import PleviCore

struct InlinePlayerSection: View {
    let video: Video
    /// Owned by `VideoDetailView` (one per video, created in its
    /// `.task(id: videoId)`), not by this section — see this file's own
    /// doc comment for why.
    let controller: VideoPlaybackController
    @Binding var seekRequestSeconds: Double?
    /// Fires once playback reaches `.ended` (after the controller has already marked the video watched).
    var onFinished: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @Environment(NavigationModel.self) private var navigation
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var isFallbackFullScreen = false
    @State private var showUnsupportedNotice = false
    /// `true` while this section paused the fallback engine for backgrounding (not a user
    /// pause) — so foregrounding knows to resume it. The native engine needs no equivalent:
    /// AVKit already pauses inline video on its own when backgrounded outside of PiP.
    @State private var pausedForBackground = false
    /// Set by `tapPlay()` when `ResumePolicy` says to ask rather than resume silently
    /// (Settings → Playback → "Resuming videos" = "Ask"). `video` is a `let` on this view, so
    /// only the position needs capturing.
    private struct ResumePrompt { let position: Double }
    @State private var resumePrompt: ResumePrompt?

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            Color.black
            if controller.hasStarted {
                if let nativeEngine = controller.nativeEngine {
                    PlayerView(
                        engine: nativeEngine,
                        onFullScreenChanged: { controller.isFullScreen = $0 },
                        onPictureInPictureChanged: { controller.isPictureInPicture = $0 },
                        onRestoreUI: { completion in restorePlayerScreen(completion) },
                        skipNotice: controller.skipNotice,
                        session: controller
                    )
                } else if controller.engineKind == .fallback {
                    FallbackPlayerView(
                        controller: controller,
                        isFullScreen: false,
                        onToggleFullScreen: { isFallbackFullScreen = true }
                    )
                    .fullScreenCover(isPresented: $isFallbackFullScreen) {
                        FallbackPlayerView(
                            controller: controller,
                            isFullScreen: true,
                            onToggleFullScreen: { isFallbackFullScreen = false }
                        )
                        .ignoresSafeArea()
                        .statusBarHidden()
                        .preferredColorScheme(.dark)
                    }
                    .onChange(of: isFallbackFullScreen) { _, newValue in
                        controller.isFullScreen = newValue
                    }
                }
            } else if showUnsupportedNotice, let notice = controller.unsupportedNotice {
                unsupportedNoticeView(notice)
            } else {
                restingThumbnail
            }

            // `FallbackPlayerView` draws its own overlay for a fallback-engine failure, but nothing showed a *native* one.
            if let failure = controller.lastFailure, failure.engineKind == .native {
                nativeFailureView(failure.message)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PleviMetrics.cardCornerRadius, style: .continuous))
        .onAppear {
            // This section reappearing means the disappearance that scheduled a teardown was
            // AVKit moving the player around, not the user leaving.
            controller.cancelDeferredTeardown()
        }
        .onChange(of: seekRequestSeconds) { _, newValue in
            guard let seconds = newValue else { return }
            // Consumed once — cleared immediately so the same value can't
            // reapply on a later, unrelated re-render.
            seekRequestSeconds = nil
            activate(startPosition: seconds, isSeek: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard controller.hasStarted, let engine = controller.engine else { return }
            PlaybackLog.shared.log("app", "scene \(newPhase) engine=\(String(describing: controller.engineKind)) "
                + "state=\(String(describing: engine.state)) position=\(String(format: "%.1f", engine.currentTime)) "
                + "pip=\(controller.isPictureInPicture)")
            if newPhase == .background {
                let position = engine.currentTime
                Task { await controller.reportProgress(position: position, force: true) }
                // Parity with AVKit's own inline behavior — pausing when backgrounded outside PiP — since the fallback engine has no such built-in policy of its own.
                if controller.engineKind == .fallback, !controller.isPictureInPicture {
                    switch engine.state {
                    case .paused, .ended, .failed:
                        break
                    case .idle, .ready, .playing:
                        engine.pause()
                        pausedForBackground = true
                    }
                }
            } else if newPhase == .active, pausedForBackground {
                pausedForBackground = false
                if !controller.consumeRemoteTransportCommand(), engine.state == .paused {
                    engine.play()
                }
            }
        }
        .onChange(of: controller.isPictureInPicture) { wasActive, isActive in
            guard controller.engineKind == .fallback, wasActive, !isActive else { return }
            if scenePhase == .active {
                // In front of the app: reveal the video's page to come back to, still playing.
                controller.cancelDeferredTeardown()
                revealThisVideoPage()
            } else {
                // Somewhere else entirely — they closed the PiP window with the X.
                controller.engine?.pause()
                pausedForBackground = false
                let position = controller.engine?.currentTime ?? 0
                Task { await controller.reportProgress(position: position, force: true) }
            }
        }
        .onDisappear {
            guard controller.hasStarted,
                  !controller.isFullScreen,
                  !controller.isPictureInPicture else { return }
            // Position first, same ordering `PlayerScreen.onDisappear` uses
            // and documents: `stop()` tears the item down, after which
            // there's no live position left to trust.
            let finalPosition = controller.engine?.currentTime ?? 0
            // Those three flags are level-triggered, and `isPictureInPicture` is cleared by the *last* callback AVKit sends.
            if controller.isWithinRestoreGrace {
                controller.scheduleTeardownAfterRestoreGrace(finalPosition: finalPosition)
                return
            }
            Task { await controller.reportProgress(position: finalPosition, force: true) }
            controller.stop()
        }
        // `InlinePlayerSection` has never presented a `confirmationDialog` before; its only modal-ish state is this inline overlay stack.
        .confirmationDialog(
            resumePrompt.map { "Resume from \(PleviFormatting.clockDuration(seconds: $0.position))?" } ?? "Resume playback?",
            isPresented: Binding(
                get: { resumePrompt != nil },
                set: { if !$0 { resumePrompt = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Resume") {
                if let prompt = resumePrompt {
                    activate(startPosition: prompt.position, isSeek: false)
                }
                resumePrompt = nil
            }
            Button("Start Over") {
                activate(startPosition: nil, isSeek: false)
                resumePrompt = nil
            }
            Button("Cancel", role: .cancel) { resumePrompt = nil }
        }
        .statusBarHidden(controller.isFullScreen)
    }

    @ViewBuilder
    private var restingThumbnail: some View {
        ZStack {
            RemoteImage(path: video.vidThumbUrl, maxPixelSize: 1024)
                .aspectRatio(16.0 / 9.0, contentMode: .fill)

            Button {
                tapPlay()
            } label: {
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.black.opacity(0.75), .white)
                    .shadow(radius: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
        }
        .overlay(alignment: .bottom) {
            if let progress = video.player?.progress, progress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: proxy.size.width * CGFloat(min(max(progress / 100, 0), 1)))
                }
                .frame(height: 3)
            }
        }
    }

    /// Puts this video's screen back on screen for AVKit, then tells it so.
    private func restorePlayerScreen(_ completion: @escaping (Bool) -> Void) {
        controller.cancelDeferredTeardown()
        guard let playing = navigation.playing else {
            completion(true)
            return
        }
        // Already on the page — the common case, and the one that works today. Answer at once
        // rather than making it wait on a poll it doesn't need.
        if navigation.selectedSection == playing.section,
           navigation.path(for: playing.section).last == playing.route {
            completion(true)
            return
        }
        navigation.reveal(playing.route, in: playing.section)
        controller.completeRestoreWhenPlayerIsOnScreen(completion)
    }

    /// Where the video actually lives, recorded when playback started.
    private func revealThisVideoPage() {
        if let playing = navigation.playing {
            navigation.reveal(playing.route, in: playing.section)
        }
    }

    private func tapPlay() {
        switch ResumePolicy.decide(
            behavior: appSettings.resumeBehavior,
            isWatched: video.player?.watched == true,
            position: video.player?.position,
            duration: video.player?.duration
        ) {
        case .startFromBeginning:
            activate(startPosition: nil, isSeek: false)
        case .resume(let position):
            activate(startPosition: position, isSeek: false)
        case .ask(let position):
            resumePrompt = ResumePrompt(position: position)
        }
    }

    private func activate(startPosition: Double?, isSeek: Bool) {
        if controller.hasStarted {
            // Already playing (or paused/ended): only a seek request means
            // anything further here — a bare tap has no button left to
            // trigger it from once playback has started.
            guard isSeek, let startPosition, let engine = controller.engine else { return }
            Task {
                await engine.seek(to: startPosition)
                engine.play()
            }
            return
        }
        controller.prepareEngine(for: video)
        // The video needs the fallback player and none is available (Settings → "Never", or no factory on this platform).
        guard controller.unsupportedNotice == nil else {
            showUnsupportedNotice = true
            return
        }
        controller.hasStarted = true
        controller.onEnded = { onFinished() }
        // Remember where this is playing from, so PiP's restore button has
        // somewhere definite to go back to.
        if let route = navigation.path(for: navigation.selectedSection).last {
            navigation.playing = .init(section: navigation.selectedSection, route: route)
        }
        Task { await controller.start(video: video, startPosition: startPosition) }
    }

    /// Restarts the item from the top of `start`, re-running the compatibility decision with it.
    private func retry() {
        let resumeFrom = controller.engine?.currentTime ?? 0
        Task {
            await controller.start(video: video, startPosition: resumeFrom > 0 ? resumeFrom : nil)
        }
    }

    /// The native engine's counterpart to `FallbackPlayerView`'s error overlay, drawn over
    /// whatever AVKit is (not) showing.
    private func nativeFailureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
            Text("Can't Play This Video")
                .pleviSectionHeading()
            // The reason is the whole point of this overlay, and the inline player is a short 16:9 box.
            Text(message)
                .pleviBody()
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
            Button("Retry") { retry() }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }

    /// The resting-slot equivalent of `FallbackPlayerView`'s own error overlay — shown instead
    /// of ever calling `start()` when `controller.unsupportedNotice` is set (see `activate()`).
    private func unsupportedNoticeView(_ message: String) -> some View {
        ZStack {
            RemoteImage(path: video.vidThumbUrl, maxPixelSize: 1024)
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                Text(message)
                    .pleviBody()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                // Only when the user's own "Never" is what is standing in the way — the notice
                // also appears where there is no compatibility player to offer at all, and a
                // button that fixed nothing would be worse than none.
                if appSettings.fallbackPlayerMode == .never {
                    Button("Use compatibility player") {
                        // Writing the setting is all that is needed now: the controller
                        // reads the mode live rather than from a snapshot taken when it
                        // was built.
                        appSettings.fallbackPlayerMode = .automatic
                        showUnsupportedNotice = false
                        tapPlay()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(.black)
                }
            }
            .foregroundStyle(.white)
        }
    }
}
#endif
