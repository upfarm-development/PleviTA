// BulkRedownloadPolicyTests.swift

import Foundation
import Testing
@testable import PleviCore

@Suite("Bulk redownload policy")
struct BulkRedownloadPolicyTests {
    private func video(_ id: String, codec: String?, height: Int = 1080) -> Video {
        let streams = codec.map { [VideoStream(type: "video", codec: $0, width: nil, height: height, bitrate: nil)] }
        return Video(youtubeId: id, title: id, streams: streams)
    }

    @Test("stream codec names map to the known codecs, tags and short names alike")
    func codecNames() {
        #expect(VideoCodec(streamCodec: "h264") == .h264)
        #expect(VideoCodec(streamCodec: "avc1.640028") == .h264)
        #expect(VideoCodec(streamCodec: "hevc") == .h265)
        #expect(VideoCodec(streamCodec: "hev1.1.6.L120") == .h265)
        #expect(VideoCodec(streamCodec: "vp9") == .vp9)
        #expect(VideoCodec(streamCodec: "vp09.00.40.08") == .vp9)
        #expect(VideoCodec(streamCodec: "av1") == .av1)
        #expect(VideoCodec(streamCodec: "av01.0.08M.08") == .av1)
        #expect(VideoCodec(streamCodec: "theora") == nil)
    }

    @Test("a video's codec comes from its video stream, not its audio stream")
    func codecReadsVideoStream() {
        let v = Video(youtubeId: "a", title: "a", streams: [
            VideoStream(type: "audio", codec: "opus", width: nil, height: nil, bitrate: nil),
            VideoStream(type: "video", codec: "av1", width: 1920, height: 1080, bitrate: nil),
        ])
        #expect(v.videoCodec == .av1)
    }

    @Test("nothing is skipped when no codec is chosen")
    func nothingSkipped() {
        let selection = BulkRedownloadPolicy.select([video("a", codec: "av1"), video("b", codec: "h264")], skipping: [])
        #expect(selection.redownloadIds == ["a", "b"])
        #expect(selection.skippedCount == 0)
    }

    @Test("videos already in a chosen codec are left alone and counted")
    func skipsChosenCodecs() {
        let videos = [video("a", codec: "av1"), video("b", codec: "h264"), video("c", codec: "vp9"), video("d", codec: "av01.0.08M.08")]
        let selection = BulkRedownloadPolicy.select(videos, skipping: [.av1, .vp9])
        #expect(selection.redownloadIds == ["b"])
        #expect(selection.skippedCount == 3)
        #expect(selection.skippedCodecs == [.vp9, .av1])
    }

    @Test("a video whose codec is unknown is never skipped")
    func unknownCodecIsRedownloaded() {
        let selection = BulkRedownloadPolicy.select([video("a", codec: nil), video("b", codec: "theora")], skipping: Set(VideoCodec.allCases))
        #expect(selection.redownloadIds == ["a", "b"])
        #expect(selection.skippedCount == 0)
    }

    @Test("a list of codecs reads as a sentence")
    func codecListText() {
        #expect(VideoCodec.list([.av1]) == "AV1")
        #expect(VideoCodec.list([.h264, .av1]) == "H.264 or AV1")
        #expect(VideoCodec.list([.h264, .vp9, .av1]) == "H.264, VP9 or AV1")
    }

    @Test("the confirmation line names the codec and resolution, or nothing without a stream")
    func currentFormatText() {
        #expect(VideoFileFacts.currentFormat(video("a", codec: "h264", height: 1080)) == "H.264 · 1080p")
        #expect(VideoFileFacts.currentFormat(video("b", codec: "theora", height: 480)) == "theora · 480p")
        #expect(VideoFileFacts.currentFormat(video("c", codec: nil)) == nil)
    }
}
