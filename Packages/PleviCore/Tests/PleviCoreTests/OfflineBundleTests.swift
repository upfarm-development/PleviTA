import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineBundle")
struct OfflineBundleTests {
    private func makeVideo() -> Video {
        var video = Video(youtubeId: "abc123", title: "A Video", mediaUrl: "/media/chan/abc123.mp4")
        video.player = VideoPlayerState(duration: 754, durationStr: "12:34", watched: true, position: 300, progress: 40)
        return video
    }

    @Test("watched/position/progress are stripped; duration survives")
    func stripsPlayerStateOnly() {
        let stripped = OfflineBundle.strippedForStorage(makeVideo())
        #expect(stripped.player?.watched == nil)
        #expect(stripped.player?.position == nil)
        #expect(stripped.player?.progress == nil)
        #expect(stripped.player?.duration == 754)
        #expect(stripped.player?.durationStr == "12:34")
    }

    @Test("a video with no player state round-trips with none")
    func noPlayerStateStaysNil() throws {
        let video = Video(youtubeId: "novideo")
        let data = try OfflineBundle.encodeVideoJSON(video)
        let decoded = try OfflineBundle.decodeVideoJSON(data)
        #expect(decoded.player == nil)
    }

    @Test("video.json round-trips through Video's own Codable shape")
    func roundTripsThroughVideoJSON() throws {
        let data = try OfflineBundle.encodeVideoJSON(makeVideo())
        let decoded = try OfflineBundle.decodeVideoJSON(data)
        #expect(decoded.youtubeId == "abc123")
        #expect(decoded.title == "A Video")
        #expect(decoded.player?.watched == nil)
        #expect(decoded.player?.duration == 754)
    }

    @Test("the media filename is the server's own, extension preserved, never a UUID")
    func mediaFilenamePreservesServerName() {
        let video = Video(youtubeId: "xyz", mediaUrl: "/media/some-channel/xyz.webm?token=abc")
        #expect(OfflineBundle.mediaFilename(for: video) == "xyz.webm")
    }

    @Test("a missing mediaUrl falls back to <youtubeId>.mp4")
    func missingMediaUrlFallsBack() {
        let video = Video(youtubeId: "novideo")
        #expect(OfflineBundle.mediaFilename(for: video) == "novideo.mp4")
    }

    @Test("record.json round-trips every field")
    func recordRoundTrips() throws {
        let record = OfflineVideoRecord(
            youtubeId: "abc123",
            state: .downloading,
            reason: .savedByUser,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mediaFilename: "abc123.mp4",
            expectedByteCount: 1000,
            receivedByteCount: 500,
            lastError: nil,
            subtitleFilenames: ["abc123.en.vtt"],
            isOrphaned: true
        )
        let data = try OfflineBundle.encodeRecordJSON(record)
        let decoded = try OfflineBundle.decodeRecordJSON(data)
        #expect(decoded == record)
    }

    @Test("a record.json written before subtitleFilenames/isOrphaned existed still decodes, with safe defaults")
    func recordDecodesOlderShapeTolerantly() throws {
        let olderShape = Data("""
        {"youtubeId": "abc123", "state": "complete", "reason": "savedByUser",
         "savedAt": "2023-11-14T22:13:20Z", "mediaFilename": "abc123.mp4", "receivedByteCount": 500}
        """.utf8)
        let decoded = try OfflineBundle.decodeRecordJSON(olderShape)
        #expect(decoded.youtubeId == "abc123")
        #expect(decoded.state == .complete)
        #expect(decoded.subtitleFilenames.isEmpty)
        #expect(decoded.isOrphaned == false)
    }

    @Test("a record.json with only youtubeId still decodes to safe, conservative defaults")
    func recordDecodesMinimalShape() throws {
        let minimal = Data("""
        {"youtubeId": "abc123"}
        """.utf8)
        let decoded = try OfflineBundle.decodeRecordJSON(minimal)
        #expect(decoded.youtubeId == "abc123")
        #expect(decoded.state == .failed, "an unreadable record must never be assumed .complete")
        #expect(decoded.reason == .savedByUser)
        #expect(decoded.mediaFilename == "abc123.mp4")
        #expect(decoded.subtitleFilenames.isEmpty)
        #expect(decoded.isOrphaned == false)
    }

    @Test("layout paths are all inside the video's own directory")
    func layoutPathsNest() {
        let root = URL(fileURLWithPath: "/tmp/offline-root")
        let layout = OfflineBundle.layout(root: root, serverDigest: "deadbeef", youtubeId: "abc123")
        #expect(layout.directory.path == "/tmp/offline-root/deadbeef/abc123")
        #expect(layout.videoJSON.path == "/tmp/offline-root/deadbeef/abc123/video.json")
        #expect(layout.recordJSON.path == "/tmp/offline-root/deadbeef/abc123/record.json")
        #expect(layout.thumbnail.path == "/tmp/offline-root/deadbeef/abc123/thumb.jpg")
        #expect(layout.mediaFile(named: "abc123.mp4").path == "/tmp/offline-root/deadbeef/abc123/abc123.mp4")
    }
}
