
import Foundation

public enum ServerAddressKind: Sendable, Equatable {
    /// A loopback, private-range, link-local or `.local` address — reachable
    /// only from the same network.
    case local
    /// A public hostname or public IP — reachable from anywhere.
    case remote
    /// Not confidently either. Callers must leave the settings alone.
    case indeterminate
}

public enum ServerAddressClassifier {
    public static func classify(_ url: URL) -> ServerAddressKind {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .indeterminate }

        if host == "localhost" { return .local }
        if host.hasSuffix(".local") { return .local }

        if let octets = ipv4Octets(host) {
            return isPrivateIPv4(octets) ? .local : .remote
        }

        if host.contains(":") {
            // IPv6. `fe80::/10` is link-local and `fc00::/7` unique-local;
            // everything else routable is treated as remote, the same way a
            // public IPv4 is.
            if host == "::1" { return .local }
            if host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb") {
                return .local
            }
            if host.hasPrefix("fc") || host.hasPrefix("fd") { return .local }
            return .remote
        }

        // A dotted name that isn't an IP — ta.example.com.
        return host.contains(".") ? .remote : .indeterminate
    }

    static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part), (0...255).contains(value) else {
                return nil
            }
            octets.append(value)
        }
        return octets
    }

    /// RFC 1918 private ranges, plus loopback (127/8) and link-local
    /// (169.254/16), which are equally "only from here".
    static func isPrivateIPv4(_ octets: [Int]) -> Bool {
        switch octets[0] {
        case 10, 127:
            return true
        case 172:
            return (16...31).contains(octets[1])
        case 192:
            return octets[1] == 168
        case 169:
            return octets[1] == 254
        default:
            return false
        }
    }
}
