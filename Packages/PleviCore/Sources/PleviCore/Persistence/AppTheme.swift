// The user's explicit light/dark override for the whole app, backed by `AppSettings.appTheme`.

import Foundation

public enum AppTheme: String, CaseIterable, Sendable, Codable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
