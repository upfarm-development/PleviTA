
import Foundation
import Testing
@testable import PleviCore

@Suite("PleviFormatting")
struct PleviFormattingTests {
    @Test("byteCount renders a non-empty, unit-suffixed string")
    func byteCountRendersAUnit() {
        let result = PleviFormatting.byteCount(48_318_023_680)
        #expect(!result.isEmpty)
        // Binary count style: a value this large should read in GB (or GiB
        // depending on OS version's byte-count formatter localization), not
        // bytes.
        #expect(result.contains("G"))
    }

    @Test("byteCount handles zero without crashing")
    func byteCountHandlesZero() {
        let result = PleviFormatting.byteCount(0)
        #expect(!result.isEmpty)
    }

    @Test("approximateDuration renders day/hour components, largest first")
    func approximateDurationRendersLargestUnitsFirst() {
        let seconds: Double = 3 * 86_400 + 4 * 3_600
        let result = PleviFormatting.approximateDuration(seconds: seconds)
        #expect(!result.isEmpty)
        #expect(result.contains("3"))
        #expect(result.contains("4"))
    }

    @Test("approximateDuration handles sub-minute durations without crashing")
    func approximateDurationHandlesSubMinute() {
        let result = PleviFormatting.approximateDuration(seconds: 30)
        #expect(!result.isEmpty)
    }

    @Test("approximateDuration returns a placeholder for invalid input")
    func approximateDurationHandlesInvalidInput() {
        #expect(PleviFormatting.approximateDuration(seconds: -5) == "—")
        #expect(PleviFormatting.approximateDuration(seconds: .nan) == "—")
    }

    @Test("displayDate strips the time from a real Tube Archivist published string")
    func displayDateStripsTimeFromRealServerString() {
        let result = PleviFormatting.displayDate(from: "2026-08-14T15:58:23+00:00")
        #expect(result != nil)
        #expect(result?.contains("T") == false)
        #expect(result?.contains("+00:00") == false)
        #expect(result?.contains("2026") == true)
    }

    @Test("displayDate handles a date-only fallback shape")
    func displayDateHandlesDateOnlyShape() {
        let result = PleviFormatting.displayDate(from: "2026-08-14")
        #expect(result != nil)
        #expect(result?.contains("2026") == true)
    }

    @Test("displayDate falls back to stripping an unrecognized string's time component")
    func displayDateFallsBackOnUnparseableString() {
        let result = PleviFormatting.displayDate(from: "not-a-real-date T garbage")
        #expect(result == "not-a-real-date ")
    }

    @Test("displayDate returns nil only for nil input")
    func displayDateHandlesNilAndEmpty() {
        #expect(PleviFormatting.displayDate(from: nil) == nil)
        #expect(PleviFormatting.displayDate(from: "") == nil)
    }

    @Test("dataRate matches the spec's own worked example")
    func dataRateMatchesSpecExample() {
        let bitsPerSecond = Int((564.5 * 1024 * 8).rounded())
        #expect(PleviFormatting.dataRate(bitsPerSecond: bitsPerSecond) == "564.5 KiB/s")
    }

    @Test("dataRate steps up through binary units as the value grows")
    func dataRateStepsThroughUnits() {
        #expect(PleviFormatting.dataRate(bitsPerSecond: 0) == "0 B/s")
        // 100 bytes/sec = 800 bits/sec — stays in bytes, whole-number.
        #expect(PleviFormatting.dataRate(bitsPerSecond: 800) == "100 B/s")
        // Exactly 1 KiB/s = 1024 bytes/sec = 8192 bits/sec.
        #expect(PleviFormatting.dataRate(bitsPerSecond: 8192) == "1.0 KiB/s")
        // Exactly 1 MiB/s.
        #expect(PleviFormatting.dataRate(bitsPerSecond: 1024 * 1024 * 8) == "1.0 MiB/s")
    }

    @Test("compactCount abbreviates large counts")
    func compactCountAbbreviatesLargeCounts() {
        let result = PleviFormatting.compactCount(926_448)
        #expect(!result.isEmpty)
        #expect(result.count < "926448".count)
    }

    @Test("compactCount leaves small counts unabbreviated")
    func compactCountLeavesSmallCountsUnabbreviated() {
        #expect(PleviFormatting.compactCount(999) == "999")
        #expect(PleviFormatting.compactCount(0) == "0")
    }

    @Test("durationBadge matches clockDuration's own mm:ss shape under an hour")
    func durationBadgeMatchesClockDurationUnderAnHour() {
        #expect(PleviFormatting.durationBadge(seconds: 245) == "4:05")
        #expect(PleviFormatting.durationBadge(seconds: 3599) == "59:59")
    }

    @Test("durationBadge drops seconds at an hour or more, unlike clockDuration")
    func durationBadgeDropsSecondsAtAnHour() {
        // The live report's own example: "2h 19m 08s" showed seconds
        // nobody reads at that scale — this should read "2h 19m".
        #expect(PleviFormatting.durationBadge(seconds: 8348) == "2h 19m")
        #expect(PleviFormatting.durationBadge(seconds: 3600) == "1h 0m")
        // clockDuration, unchanged, still carries seconds at this scale —
        // proving the two have genuinely diverged, not just coincided.
        #expect(PleviFormatting.clockDuration(seconds: 8348) == "2:19:08")
    }
}

@Suite("VideoFileFacts")
struct VideoFileFactsTests {
    private func video(codec: String?, height: Int?, bitrate: Int?) -> Video {
        Video(youtubeId: "v", streams: [
            VideoStream(type: "video", codec: codec, width: height.map { $0 * 16 / 9 },
                        height: height, bitrate: bitrate),
            VideoStream(type: "audio", codec: "aac", width: nil, height: nil, bitrate: 128_000)
        ])
    }

    private let posix = Locale(identifier: "en_US_POSIX")

    @Test("the compact video form is codec, resolution and a short bitrate")
    func compactVideoIsShort() {
        // The full form truncated on an iPad and lost the resolution; this keeps all three
        // facts by shortening the bitrate rather than dropping it.
        #expect(VideoFileFacts.videoStreamCompact(video(codec: "h264", height: 1080, bitrate: 2_345_000),
                                                  locale: posix) == "h264 · 1080p · 2.3 Mbps")
        #expect(VideoFileFacts.videoStream(video(codec: "h264", height: 1080, bitrate: 2_345_000))?
                .contains("1920×1080") == true, "the full form still carries the exact resolution")
    }

    @Test("compact audio is codec and bitrate")
    func compactAudioIsShort() {
        #expect(VideoFileFacts.audioStreamCompact(video(codec: "h264", height: 720, bitrate: 1),
                                                  locale: posix) == "aac · 128 kbps")
    }

    @Test("missing pieces drop out instead of rendering empty labels")
    func missingPiecesDropOut() {
        #expect(VideoFileFacts.videoStreamCompact(video(codec: nil, height: nil, bitrate: nil)) == nil)
        #expect(VideoFileFacts.fileSize(Video(youtubeId: "v")) == nil)
    }
}

@Suite("PleviFormatting.bitRate")
struct BitRateFormattingTests {
    private let us = Locale(identifier: "en_US_POSIX")
    private let no = Locale(identifier: "nb_NO")

    @Test("megabit rates read short, with the locale's own decimal separator")
    func megabitsUseLocaleSeparator() {
        #expect(PleviFormatting.bitRate(bitsPerSecond: 2_345_000, locale: us) == "2.3 Mbps")
        #expect(PleviFormatting.bitRate(bitsPerSecond: 2_345_000, locale: no) == "2,3 Mbps")
    }

    @Test("a large rate drops the decimal rather than reading 12,0")
    func largeRatesDropTheDecimal() {
        #expect(PleviFormatting.bitRate(bitsPerSecond: 12_400_000, locale: us) == "12 Mbps")
    }

    @Test("sub-megabit rates are whole kbps, and tiny ones bps")
    func smallerRates() {
        #expect(PleviFormatting.bitRate(bitsPerSecond: 128_000, locale: us) == "128 kbps")
        #expect(PleviFormatting.bitRate(bitsPerSecond: 999, locale: us) == "999 bps")
        #expect(PleviFormatting.bitRate(bitsPerSecond: 0, locale: us) == "0 kbps")
    }

    @Test("the binary byte-rate formatter is untouched — iPhone's card still uses it")
    func dataRateUnchanged() {
        #expect(PleviFormatting.dataRate(bitsPerSecond: 4_620_000).hasSuffix("KiB/s"))
    }

    @Test("the playlist video count says how many are shown out of how many Tube Archivist has")
    func videoCountText() {
        #expect(PleviFormatting.videoCountText(onServer: 12, showing: 12) == "12 videos")
        #expect(PleviFormatting.videoCountText(onServer: 1, showing: 1) == "1 video")
        #expect(PleviFormatting.videoCountText(onServer: 12, showing: 5) == "5 of 12 videos")
        #expect(PleviFormatting.videoCountText(onServer: 1, showing: 0) == "0 of 1 video")
        #expect(PleviFormatting.videoCountText(onServer: 0, showing: 0) == "0 videos")
    }
}
