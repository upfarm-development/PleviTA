
import SwiftUI
import VideoToolbox
import PleviCore

struct FileDetailsSection: View {
    let video: Video
    var isCollapsible: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSettings.self) private var appSettings
    @State private var isExpanded = false

    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    private var compatibility: MediaCompatibility {
        MediaCompatibility.assess(video: video, hardwareAV1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
    }

    // Shared with the stats strip, which shows the same three facts as cells on iPad and
    // tvOS — see `VideoFileFacts`.
    private var fileSizeText: String? { VideoFileFacts.fileSize(video) }
    private var videoStream: VideoStream? { video.streams?.first { $0.type == "video" } }
    private var videoDetailText: String? { VideoFileFacts.videoStream(video) }
    private var audioDetailText: String? { VideoFileFacts.audioStream(video) }

    /// The collapsed row's own summary — file size plus a plain `<height>p`
    /// shorthand (not the full `width×height` the expanded "Video" line
    /// shows), matching the spec's own `"4.5 GiB · 1080p"` example exactly.
    private var collapsedSummaryText: String {
        var parts: [String] = []
        if let fileSizeText { parts.append(fileSizeText) }
        if let height = videoStream?.height { parts.append("\(height)p") }
        return parts.joined(separator: " · ")
    }

    private var hasAnyData: Bool {
        fileSizeText != nil || videoDetailText != nil || audioDetailText != nil || subtitlesUnavailable
    }

    private var subtitlesUnavailable: Bool {
        guard !(video.subtitles ?? []).isEmpty else { return false }
        switch appSettings.fallbackPlayerMode {
        case .always: return false
        case .never: return true
        case .automatic: return !compatibility.needsFallback
        }
    }

    var body: some View {
        if hasAnyData {
            Group {
                if isCollapsible {
                    collapsedBody
                } else {
                    expandedBody
                }
            }
            .padding(16)
            .pleviCard()
        }
    }

    // MARK: - iPhone: collapsed row

    private var collapsedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("File details")
                        .pleviSectionHeading()
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    if !collapsedSummaryText.isEmpty {
                        Text(collapsedSummaryText)
                            .pleviMono()
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                }
                .contentShape(Rectangle())
                .tvFocusRing(cornerRadius: PleviMetrics.cardCornerRadius, scales: false)
            }
            .pleviSelectableStyle()
            .accessibilityLabel("File details, \(collapsedSummaryText)")
            .accessibilityHint(isExpanded ? "Double tap to collapse." : "Double tap to expand.")

            if isExpanded {
                detailRows
            }
        }
    }

    // MARK: - iPad / tvOS: always expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Details")
                .pleviEyebrow()
                .foregroundStyle(palette.secondary)
            detailRows
        }
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fileSizeText {
                detailRow(label: "File Size", value: fileSizeText)
            }
            if let videoDetailText {
                detailRow(label: "Video", value: videoDetailText)
            }
            if let audioDetailText {
                detailRow(label: "Audio", value: audioDetailText)
            }
            if let reason = compatibility.reason {
                compatibilityCaption(reason)
            }
            if subtitlesUnavailable {
                subtitleAvailabilityCaption
            }
        }
    }

    /// See `subtitlesUnavailable`'s own doc comment for exactly when this shows. Same voice and
    /// placement as `compatibilityCaption` just above it — a plain caption line, not a badge.
    private var subtitleAvailabilityCaption: some View {
        Text(
            appSettings.fallbackPlayerMode == .never
                ? "Subtitles aren't supported by the built-in player. Turn on the compatibility player in Settings to use them."
                : "Subtitles need the compatibility player. Set Settings → Playback → Compatibility player to “Always” to use them."
        )
            .pleviBody()
            .foregroundStyle(palette.secondary)
    }

    private func compatibilityCaption(_ reason: String) -> some View {
        Text(
            appSettings.fallbackPlayerMode == .never
                ? "\(reason) isn't supported by the built-in player. Turn on the compatibility player in Settings to play it."
                : "Plays with the compatibility player — \(reason) isn't supported by the built-in player."
        )
            .pleviBody()
            .foregroundStyle(palette.secondary)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .pleviEyebrow()
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .pleviMono()
                .foregroundStyle(palette.body)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            FileDetailsSection(
                video: Video(youtubeId: "1", mediaSize: 4_800_000_000, streams: [
                    VideoStream(type: "video", codec: "h264", width: 1920, height: 1080, bitrate: 4_600_000),
                    VideoStream(type: "audio", codec: "aac", width: nil, height: nil, bitrate: 128_000)
                ]),
                isCollapsible: true
            )
            FileDetailsSection(
                video: Video(youtubeId: "1", mediaSize: 4_800_000_000, streams: [
                    VideoStream(type: "video", codec: "h264", width: 1920, height: 1080, bitrate: 4_600_000),
                    VideoStream(type: "audio", codec: "aac", width: nil, height: nil, bitrate: 128_000)
                ]),
                isCollapsible: false
            )
        }
        .padding()
    }
}
