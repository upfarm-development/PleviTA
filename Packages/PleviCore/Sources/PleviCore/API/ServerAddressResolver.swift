
import Foundation

public enum ServerAddressResolver {
    public static func resolve(
        local: URL?,
        remote: URL?,
        mode: ConnectionMode,
        loginServerURL: URL?,
        probe: (URL) async -> Bool
    ) async -> URL? {
        switch (local, remote) {
        case (.some(let local), .some(let remote)):
            switch mode {
            case .alwaysLocal:
                return local
            case .alwaysRemote:
                return remote
            case .automatic:
                if await probe(local) {
                    return local
                }
                return remote
            }
        case (.some(let local), nil):
            return local
        case (nil, .some(let remote)):
            return remote
        case (nil, nil):
            return loginServerURL
        }
    }
}
