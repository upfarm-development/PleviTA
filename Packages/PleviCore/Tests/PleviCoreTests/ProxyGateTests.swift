
import Foundation
import Testing
@testable import PleviCore

@Suite("Proxy gate detection")
struct ProxyGateTests {
    private func response(contentType: String?, status: Int = 200) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        return HTTPURLResponse(
            url: URL(string: "https://ta.example.com/api/ping/")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    // MARK: - TAClient.looksLikeWebPage

    @Test("an HTML content type is a gate, whatever the status code")
    func htmlContentTypeIsAGate() {
        let body = Data("<!DOCTYPE html><html><body>Sign in</body></html>".utf8)
        #expect(TAClient.looksLikeWebPage(data: body, response: response(contentType: "text/html; charset=utf-8")))
        // A gate is free to answer 200 with its login page, or 401/403 of its
        // own — the point is that none of those came from Tube Archivist.
        #expect(TAClient.looksLikeWebPage(data: body, response: response(contentType: "text/html", status: 401)))
        #expect(TAClient.looksLikeWebPage(data: body, response: response(contentType: "text/html", status: 302)))
    }

    @Test("HTML with no declared content type is sniffed from the body")
    func htmlWithoutContentTypeIsSniffed() {
        let body = Data("\n  <html><head><title>Login</title></head></html>".utf8)
        #expect(TAClient.looksLikeWebPage(data: body, response: response(contentType: nil)))
    }

    @Test("real Tube Archivist JSON is never mistaken for a gate")
    func jsonIsNotAGate() {
        let pong = Data(#"{"response":"pong","user":1}"#.utf8)
        #expect(!TAClient.looksLikeWebPage(data: pong, response: response(contentType: "application/json")))

        // The unauthenticated case: DRF's own 401 body. Misreading this as a
        // gate would turn every ordinary expired session into misleading
        // advice about SSO.
        let detail = Data(#"{"detail":"Authentication credentials were not provided."}"#.utf8)
        #expect(!TAClient.looksLikeWebPage(data: detail, response: response(contentType: "application/json", status: 401)))
    }

    @Test("an empty body is not a gate")
    func emptyBodyIsNotAGate() {
        #expect(!TAClient.looksLikeWebPage(data: Data(), response: response(contentType: nil)))
    }

    // MARK: - TAClient.isGateStatus

    @Test("only the statuses a gate answers with treat HTML as a gate")
    func gateStatuses() {
        // A login page served as 200, or a redirect body, or the gate's own 401/403.
        #expect(TAClient.isGateStatus(200))
        #expect(TAClient.isGateStatus(302))
        #expect(TAClient.isGateStatus(401))
        #expect(TAClient.isGateStatus(403))

        #expect(!TAClient.isGateStatus(404))
        #expect(!TAClient.isGateStatus(405))
        #expect(!TAClient.isGateStatus(500))
    }

    // MARK: - APIGateProbe's JSON test

    @Test("an unauthenticated 401 body counts as through the gate")
    func unauthenticatedJSONCountsAsThrough() {
        let detail = Data(#"{"detail":"Authentication credentials were not provided."}"#.utf8)
        #expect(APIGateProbe.isJSONObject(detail))
    }

    @Test("a pong counts as through the gate")
    func pongCountsAsThrough() {
        #expect(APIGateProbe.isJSONObject(Data(#"{"response":"pong"}"#.utf8)))
    }

    @Test("a login page does not count as through the gate")
    func htmlDoesNotCountAsThrough() {
        #expect(!APIGateProbe.isJSONObject(Data("<!DOCTYPE html><html></html>".utf8)))
        #expect(!APIGateProbe.isJSONObject(Data()))
    }

    @Test("a bare JSON string does not count as through the gate")
    func bareJSONStringDoesNotCount() {
        // Valid JSON, but no Tube Archivist endpoint answers with a bare
        // scalar — requiring an object keeps a proxy that replies
        // `"unauthorized"` from being mistaken for the real server.
        #expect(!APIGateProbe.isJSONObject(Data(#""unauthorized""#.utf8)))
    }

    // MARK: - Ping URL construction

    @Test("the ping URL keeps a base path, port and scheme")
    func pingURLKeepsBasePath() {
        #expect(APIGateProbe.pingURL(for: URL(string: "https://ta.example.com")!)?.absoluteString
            == "https://ta.example.com/api/ping/")
        #expect(APIGateProbe.pingURL(for: URL(string: "https://ta.example.com/")!)?.absoluteString
            == "https://ta.example.com/api/ping/")
        #expect(APIGateProbe.pingURL(for: URL(string: "http://192.168.1.50:8000")!)?.absoluteString
            == "http://192.168.1.50:8000/api/ping/")
        #expect(APIGateProbe.pingURL(for: URL(string: "https://example.com/tubearchivist")!)?.absoluteString
            == "https://example.com/tubearchivist/api/ping/")
    }
}
