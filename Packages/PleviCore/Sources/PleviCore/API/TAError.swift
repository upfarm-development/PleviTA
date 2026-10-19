
import Foundation

public enum TAError: Error, Sendable, Equatable {
    case invalidServerURL
    case unauthorized
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case network(String)
    /// An API path answered with a web page rather than Tube Archivist data.
    case interceptedByProxy

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

extension TAError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "That doesn't look like a valid server URL."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "Not found."
        case .server(let status, let message):
            return message ?? "The server returned an error (\(status))."
        case .decoding:
            return "Couldn't understand the server's response."
        case .network(let message):
            return message.isEmpty ? "Network error." : message
        case .interceptedByProxy:
            // Platform-split because the remedy differs, and naming one that doesn't exist is worse than naming none: `SSOLoginSheet`.
            #if os(tvOS)
            return "That address answered with a web page instead of Tube Archivist data, so something is sitting in front of your server. Apple TV can't sign in through that login page — use an address that doesn't go through it, such as your server's address on your local network."
            #else
            return "That address answered with a web page instead of Tube Archivist data, so something is sitting in front of your server. If it's behind an SSO or login page, use \"Sign in via browser\" first."
            #endif
        }
    }
}
