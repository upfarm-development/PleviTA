
import Foundation
import Testing
@testable import PleviCore

private final class ProbeRecorder: @unchecked Sendable {
    private(set) var calledURLs: [URL] = []
    private let result: Bool

    init(returning result: Bool) {
        self.result = result
    }

    func callAsFunction(_ url: URL) async -> Bool {
        calledURLs.append(url)
        return result
    }
}

@Suite("ServerAddressResolver.resolve")
struct ServerAddressResolverTests {
    private let local = URL(string: "http://127.0.0.1:8081")!
    private let remote = URL(string: "https://remote.example.com")!
    private let loginServerURL = URL(string: "http://original-login.example.com")!

    // MARK: - Neither local nor remote configured (today's behavior)

    @Test("neither set falls back to the original login serverURL, for every mode, without probing", arguments: [
        ConnectionMode.automatic, .alwaysLocal, .alwaysRemote
    ])
    func neitherSetUsesLoginServerURL(mode: ConnectionMode) async {
        let probe = ProbeRecorder(returning: true)
        let result = await ServerAddressResolver.resolve(
            local: nil, remote: nil, mode: mode, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == loginServerURL)
        #expect(probe.calledURLs.isEmpty)
    }

    @Test("neither set and no login serverURL either resolves to nil")
    func neitherSetAndNoLoginURLResolvesToNil() async {
        let probe = ProbeRecorder(returning: true)
        let result = await ServerAddressResolver.resolve(
            local: nil, remote: nil, mode: .automatic, loginServerURL: nil, probe: probe.callAsFunction
        )
        #expect(result == nil)
        #expect(probe.calledURLs.isEmpty)
    }

    // MARK: - Exactly one of local/remote configured (mode is irrelevant — nothing to choose between)

    @Test("only local set resolves to local regardless of mode, without probing", arguments: [
        ConnectionMode.automatic, .alwaysLocal, .alwaysRemote
    ])
    func onlyLocalSetUsesLocal(mode: ConnectionMode) async {
        let probe = ProbeRecorder(returning: false)
        let result = await ServerAddressResolver.resolve(
            local: local, remote: nil, mode: mode, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == local)
        #expect(probe.calledURLs.isEmpty)
    }

    @Test("only remote set resolves to remote regardless of mode, without probing", arguments: [
        ConnectionMode.automatic, .alwaysLocal, .alwaysRemote
    ])
    func onlyRemoteSetUsesRemote(mode: ConnectionMode) async {
        let probe = ProbeRecorder(returning: false)
        let result = await ServerAddressResolver.resolve(
            local: nil, remote: remote, mode: mode, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == remote)
        #expect(probe.calledURLs.isEmpty)
    }

    // MARK: - Both configured: mode overrides bypass the probe entirely

    @Test("alwaysLocal with both set returns local without probing, even when the probe would fail")
    func alwaysLocalBypassesProbe() async {
        let probe = ProbeRecorder(returning: false)
        let result = await ServerAddressResolver.resolve(
            local: local, remote: remote, mode: .alwaysLocal, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == local)
        #expect(probe.calledURLs.isEmpty)
    }

    @Test("alwaysRemote with both set returns remote without probing, even when the probe would succeed")
    func alwaysRemoteBypassesProbe() async {
        let probe = ProbeRecorder(returning: true)
        let result = await ServerAddressResolver.resolve(
            local: local, remote: remote, mode: .alwaysRemote, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == remote)
        #expect(probe.calledURLs.isEmpty)
    }

    // MARK: - Automatic with both configured: the only path that actually probes

    @Test("automatic with both set and a successful probe returns local")
    func automaticProbeSuccessReturnsLocal() async {
        let probe = ProbeRecorder(returning: true)
        let result = await ServerAddressResolver.resolve(
            local: local, remote: remote, mode: .automatic, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == local)
        #expect(probe.calledURLs == [local])
    }

    @Test("automatic with both set and a failed probe falls back to remote silently")
    func automaticProbeFailureFallsBackToRemote() async {
        let probe = ProbeRecorder(returning: false)
        let result = await ServerAddressResolver.resolve(
            local: local, remote: remote, mode: .automatic, loginServerURL: loginServerURL, probe: probe.callAsFunction
        )
        #expect(result == remote)
        // Only local was ever probed — a failed local probe falls back
        // straight to remote, it does not also probe remote.
        #expect(probe.calledURLs == [local])
    }
}
