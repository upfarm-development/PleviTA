// Whether a saved place in the app is still worth returning the user to.

import Foundation

public enum NavigationRestorePolicy {
    /// How long a saved place stays worth returning to.
    public static let maxAge: TimeInterval = 30 * 60

    public enum Decision: Equatable, Sendable {
        /// The saved place still describes what the user was doing.
        case restore
        /// Saved too long ago to be about this session.
        case discardStale
        /// Saved by a different build.
        case discardUpdatedBuild
    }

    public static func decide(
        savedAt: Date,
        savedBuild: String,
        now: Date,
        currentBuild: String,
        maxAge: TimeInterval = NavigationRestorePolicy.maxAge
    ) -> Decision {
        guard savedBuild == currentBuild else { return .discardUpdatedBuild }
        let age = now.timeIntervalSince(savedAt)
        // A snapshot stamped in the future means the clock moved, not that the user did
        // something strange. Landing them where they were is the milder of the two wrong
        // answers, so a negative age counts as fresh rather than stale.
        guard age > maxAge else { return .restore }
        return .discardStale
    }
}
