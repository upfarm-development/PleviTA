// Pure decision logic for whether a manual "Play" tap should resume, start over, or ask.

import Foundation

/// User preference (Settings → Playback → "Resuming videos"). Persisted by
/// `AppSettings.resumeBehavior`.
public enum ResumeBehavior: String, CaseIterable, Codable, Sendable {
    /// Resume silently whenever a saved position qualifies. The default.
    case alwaysResume
    /// Ask before resuming a saved position past `minimumAskPosition`.
    case ask
}

public enum ResumeDecision: Sendable, Equatable {
    case startFromBeginning
    case resume(position: Double)
    case ask(position: Double)
}

public enum ResumePolicy {
    /// Mirrors `ProgressReporter.isReportablePosition`'s own floor (ProgressReporter.swift
    /// :62-66) — the server never writes a position below it, so anything under it is stale
    /// or foreign, and resuming at 0:07 is indistinguishable from starting over.
    public static let minimumResumePosition: Double = 10
    /// The threshold Apple TV has always used. Below it a saved position still resumes, it
    /// just isn't worth a dialog.
    public static let minimumAskPosition: Double = 30
    /// Mirrors the same reporter's final-5% cut-off.
    public static let endOfVideoFraction: Double = 0.95

    public static func decide(
        behavior: ResumeBehavior, isWatched: Bool, position: Double?, duration: Double?
    ) -> ResumeDecision {
        guard !isWatched else { return .startFromBeginning }
        guard let position, position >= minimumResumePosition else { return .startFromBeginning }
        if let duration, duration > 0, position >= duration * endOfVideoFraction {
            return .startFromBeginning
        }
        // Strictly greater, matching today's tvOS rule (VideoDetailView.swift:782) exactly,
        // so no Apple TV user sees a prompt they would not have seen before.
        guard behavior == .ask, position > minimumAskPosition else { return .resume(position: position) }
        return .ask(position: position)
    }

    /// For the entry points that must never prompt — auto-advance — so they share these
    /// thresholds instead of re-deriving the rule by hand.
    public static func silentStartPosition(isWatched: Bool, position: Double?, duration: Double?) -> Double? {
        if case .resume(let position) = decide(
            behavior: .alwaysResume, isWatched: isWatched, position: position, duration: duration) {
            return position
        }
        return nil
    }
}
