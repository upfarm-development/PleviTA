import Testing
import Foundation
@testable import PleviCore

@Suite("PlaybackLog", .serialized)
struct PlaybackLogTests {
    private func makeLog(maxFileBytes: UInt64 = 4_000_000, keptFiles: Int = 4) -> (log: PlaybackLog, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("playbacklog-\(UUID().uuidString)")
        return (PlaybackLog(directory: directory, maxFileBytes: maxFileBytes, keptFiles: keptFiles), directory)
    }

    private func exported(_ log: PlaybackLog) throws -> String {
        let url = try #require(log.exportCombined())
        defer { try? FileManager.default.removeItem(at: url) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("a logged line carries its category, message, launch id and a boot-relative timestamp")
    func writesLine() throws {
        let (log, _) = makeLog()
        log.log("av.STALL", "buffer empty ahead=0.0s", force: true)
        let text = try exported(log)
        #expect(text.contains(" av.STALL buffer empty ahead=0.0s\n"))
        #expect(text.contains(" u="))
        #expect(text.contains(log.launchID))
    }

    @Test("the file rotates at the size cap and never keeps more files than asked")
    func rotatesAndCaps() throws {
        let (log, directory) = makeLog(maxFileBytes: 400, keptFiles: 3)
        for index in 0..<120 { log.log("t", "line \(index)", force: true) }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count <= 3)
        let text = try exported(log)
        #expect(text.contains("line 119"))
        #expect(!text.contains(" line 0\n"))
    }

    @Test("the combined export is oldest first")
    func exportIsChronological() throws {
        let (log, _) = makeLog(maxFileBytes: 400, keptFiles: 4)
        for index in 0..<60 { log.log("t", "line \(index)", force: true) }
        let lines = try exported(log).split(separator: "\n").compactMap { line -> Int? in
            line.split(separator: " ").last.flatMap { Int($0) }
        }
        #expect(lines == lines.sorted())
        #expect(lines.last == 59)
    }

    @Test("clearing removes every file and the log keeps working afterwards")
    func clearRemovesEverything() throws {
        let (log, _) = makeLog(maxFileBytes: 400, keptFiles: 3)
        for index in 0..<50 { log.log("t", "line \(index)", force: true) }
        log.clear()
        #expect(log.sizeOnDisk() == 0)
        #expect(log.exportCombined() == nil)
        log.log("t", "after clear", force: true)
        #expect(try exported(log).contains("after clear"))
    }

    @Test("a URL is logged without credentials, query or fragment")
    func redactsURLs() {
        let url = URL(string: "https://user:secret@ta.example.com:8443/media/abc/video.mp4?token=SECRET&x=1#frag")
        #expect(PlaybackLog.redacted(url) == "https://ta.example.com:8443/media/abc/video.mp4")
        #expect(PlaybackLog.redacted(nil) == "nil")
    }

    @Test("header names are logged, never their values")
    func headerNamesOnly() {
        let text = PlaybackLog.headerNames(["Authorization": "Token SECRET", "Cookie": "sessionid=SECRET"])
        #expect(text == "Authorization,Cookie")
        #expect(!text.contains("SECRET"))
        #expect(PlaybackLog.headerNames([:]) == "none")
    }

    @Test("the throttle allows a key once per interval and keys are independent")
    func throttle() {
        let throttle = LogThrottle()
        #expect(throttle.allows("a", every: 60))
        #expect(!throttle.allows("a", every: 60))
        #expect(throttle.allows("b", every: 60))
        #expect(throttle.allows("c", every: 0))
        #expect(throttle.allows("c", every: 0))
    }
}
