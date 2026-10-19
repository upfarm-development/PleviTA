import Foundation
import Testing
@testable import PleviCore

@Suite("DownloadValidation")
struct DownloadValidationTests {
    private let mp4Bytes = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32])

    @Test("a normal 200 with matching byte count is ok")
    func okOnMatchingDownload() {
        let verdict = DownloadValidation.validate(
            status: 200, contentType: "video/mp4", first12Bytes: mp4Bytes, byteCount: 1000, expected: 1000)
        #expect(verdict == .ok)
    }

    @Test("no expected byte count at all still validates on content alone")
    func okWithNoExpectedCount() {
        let verdict = DownloadValidation.validate(
            status: 200, contentType: "video/mp4", first12Bytes: mp4Bytes, byteCount: 1000, expected: nil)
        #expect(verdict == .ok)
    }

    @Test("401/403 is a retryable auth failure, not a corrupt file")
    func gateStatusIsRetryableAuth() {
        #expect(DownloadValidation.validate(status: 401, contentType: nil, first12Bytes: Data(), byteCount: 0, expected: nil) == .retryableAuthFailure)
        #expect(DownloadValidation.validate(status: 403, contentType: nil, first12Bytes: Data(), byteCount: 0, expected: nil) == .retryableAuthFailure)
    }

    @Test("an HTML content type is never the file we asked for, even on 200")
    func htmlContentTypeIsRejected() {
        let verdict = DownloadValidation.validate(
            status: 200, contentType: "text/html; charset=utf-8", first12Bytes: mp4Bytes, byteCount: 303_000, expected: 77_374_235)
        guard case .notTheFileWeAskedFor = verdict else {
            Issue.record("expected .notTheFileWeAskedFor, got \(verdict)")
            return
        }
    }

    @Test("a login page's leading '<' is caught even with a misleading Content-Type")
    func sniffedHTMLBodyIsRejected() {
        let loginPage = Data("<!DOCTYPE html><html>sign in</html>".utf8)
        let verdict = DownloadValidation.validate(
            status: 200, contentType: "video/mp4", first12Bytes: loginPage.prefix(12), byteCount: loginPage.count, expected: nil)
        guard case .notTheFileWeAskedFor = verdict else {
            Issue.record("expected .notTheFileWeAskedFor, got \(verdict)")
            return
        }
    }

    @Test("a byte count that disagrees with Content-Length is rejected, even on 200")
    func mismatchedByteCountIsRejected() {
        let verdict = DownloadValidation.validate(
            status: 200, contentType: "video/mp4", first12Bytes: mp4Bytes, byteCount: 500, expected: 1000)
        guard case .notTheFileWeAskedFor = verdict else {
            Issue.record("expected .notTheFileWeAskedFor, got \(verdict)")
            return
        }
    }

    @Test("a non-2xx, non-auth status is rejected with the status in the reason")
    func serverErrorIsRejected() {
        let verdict = DownloadValidation.validate(status: 500, contentType: nil, first12Bytes: Data(), byteCount: 0, expected: nil)
        guard case .notTheFileWeAskedFor(let reason) = verdict else {
            Issue.record("expected .notTheFileWeAskedFor, got \(verdict)")
            return
        }
        #expect(reason.contains("500"))
    }
}
