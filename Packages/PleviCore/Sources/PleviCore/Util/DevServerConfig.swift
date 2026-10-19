// `Config/Local.xcconfig` (gitignored) may define `TA_DEV_SERVER_URL` / `TA_DEV_TOKEN`.

import Foundation

public enum DevServerConfig {
    public static var serverURL: String? {
        #if DEBUG
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "TADevServerURL") as? String)
        #else
        nil
        #endif
    }

    public static var token: String? {
        #if DEBUG
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "TADevToken") as? String)
        #else
        nil
        #endif
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
