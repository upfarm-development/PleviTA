
import Foundation
import CryptoKit

public enum ServerScope {
    /// SHA-256 of `loginURL`, first 8 bytes, hex-encoded — stable across relaunches and
    /// resolver flip-flops, and short enough to use as a directory name.
    public static func digest(of loginURL: String) -> String {
        SHA256.hash(data: Data(loginURL.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func syncScope(local: URL?, remote: URL?, login: URL?) -> String? {
        (local ?? remote ?? login)?.absoluteString
    }
}

extension CredentialStoring {
    /// See `ServerScope.syncScope`. `nil` only when nothing is stored at all.
    public func syncScope() -> String? {
        ServerScope.syncScope(local: localServerURL(), remote: remoteServerURL(), login: serverURL())
    }
}
