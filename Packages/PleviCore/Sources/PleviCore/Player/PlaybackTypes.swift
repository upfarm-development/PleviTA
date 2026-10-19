// Playback types shared with the rest of the core package. The playback engines that use them are not published.

import Foundation

/// User preference (Settings > Playback > "Compatibility player") for when the fallback engine is used.
public enum FallbackPlayerMode: String, CaseIterable, Codable, Sendable {
    /// Use the fallback only for a file the built-in player cannot handle. The default.
    case automatic
    /// Always use the fallback engine when one is available.
    case always
    /// Never use the fallback engine.
    case never
}

/// One subtitle sidecar available for a playable item.
public struct ExternalSubtitle: Sendable, Equatable {
    public var url: URL
    public var name: String
    /// BCP-47-style language tag, if known.
    public var language: String?

    public init(url: URL, name: String, language: String? = nil) {
        self.url = url
        self.name = name
        self.language = language
    }
}
