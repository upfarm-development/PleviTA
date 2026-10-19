// Pure decision logic for which SponsorBlock segment (if any) to skip right now.

import Foundation

/// Every category Tube Archivist requests from SponsorBlock (all nine, since TA v0.5.6).
public enum SponsorCategory: String, CaseIterable, Codable, Sendable {
    case sponsor, selfpromo, interaction, intro, outro, preview, filler
    case musicOfftopic = "music_offtopic"
    case poiHighlight = "poi_highlight"

    public var displayName: String {
        switch self {
        case .sponsor: "Sponsor"
        case .selfpromo: "Unpaid/Self Promotion"
        case .interaction: "Interaction Reminder (Subscribe)"
        case .intro: "Intermission/Intro Animation"
        case .outro: "Endcards/Credits"
        case .preview: "Preview/Recap"
        case .filler: "Tangents/Jokes"
        case .musicOfftopic: "Music: Non-Music Section"
        case .poiHighlight: "Highlight"
        }
    }
}

/// A normalized, playable segment — the output of `SponsorBlockPolicy.playableSegments`, never
/// decoded directly from the wire. `category` is `nil` for a category string this build doesn't
/// recognise, kept rather than discarded so it can be surfaced as known-but-not-skipped.
public struct SponsorSegment: Sendable, Equatable, Identifiable {
    public var id: String
    public var category: SponsorCategory?
    public var start: Double
    public var end: Double

    public init(id: String, category: SponsorCategory?, start: Double, end: Double) {
        self.id = id
        self.category = category
        self.start = start
        self.end = end
    }
}

public enum SponsorBlockDecision: Sendable, Equatable {
    case none
    case skip(to: Double, segment: SponsorSegment)
}

public enum SponsorBlockPolicy {
    /// The categories offered in Settings, in the order they are drawn.
    public static let userSelectableCategories: [SponsorCategory] = [.sponsor, .selfpromo, .intro, .outro]

    /// What a fresh install skips until the user says otherwise: the two promotional categories.
    public static let defaultCategories: Set<SponsorCategory> = [.sponsor, .selfpromo]

    /// Below tick resolution a skip is more jarring than the thing it removes. Both engines
    /// tick at about 1 Hz (`AVPlayerEngine.swift:73-74`; VLCKit's `timeChangeUpdateInterval`
    /// defaults to 1.0). Also used as the merge-adjacency threshold below.
    public static let minimumSegmentDuration: Double = 1.0

    /// Mirrors two different values and deliberately takes the lower.
    public static let endOfVideoFraction: Double = 0.95

    public static func playableSegments(
        from segments: [SponsorBlockSegment], duration: Double?
    ) -> [SponsorSegment] {
        var seenIDs = Set<String>()
        var candidates: [SponsorSegment] = []
        for segment in segments {
            guard let start = segment.start, let end = segment.end,
                  start.isFinite, end.isFinite, start >= 0, end > start,
                  end - start >= minimumSegmentDuration
            else { continue }
            guard let id = segment.segmentID, !id.isEmpty, !seenIDs.contains(id) else { continue }
            let clampedEnd = duration.map { min(end, $0) } ?? end
            guard clampedEnd > start else { continue }
            seenIDs.insert(id)
            candidates.append(SponsorSegment(
                id: id,
                category: segment.category.flatMap(SponsorCategory.init(rawValue:)),
                start: start,
                end: clampedEnd
            ))
        }
        candidates.sort { $0.start < $1.start }
        return mergeAdjacent(candidates)
    }

    /// Merges only segments of the **same** category.
    private static func mergeAdjacent(_ sorted: [SponsorSegment]) -> [SponsorSegment] {
        var merged: [SponsorSegment] = []
        for segment in sorted {
            if let last = merged.last,
               last.category == segment.category,
               segment.start <= last.end + minimumSegmentDuration {
                merged[merged.count - 1] = SponsorSegment(
                    id: last.id, category: last.category, start: last.start,
                    end: max(last.end, segment.end))
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    /// Drops from the ledger any segment the playhead has moved back in front of, so scrubbing backwards into a segment skips it again.
    public static func rearmed(
        handled: Set<String>, segments: [SponsorSegment], currentTime: Double
    ) -> Set<String> {
        guard !handled.isEmpty else { return handled }
        var result = handled
        for segment in segments where handled.contains(segment.id) && currentTime <= segment.start {
            result.remove(segment.id)
        }
        return result
    }

    public static func decide(
        segments: [SponsorSegment],
        currentTime: Double,
        duration: Double?,
        isEnabled: Bool,
        enabledCategories: Set<SponsorCategory>,
        handled: Set<String>
    ) -> SponsorBlockDecision {
        guard isEnabled else { return .none }
        // `PlayerEngine.duration` is `Double?` and arrives late on the fallback engine.
        guard let duration, duration > 0 else { return .none }
        for segment in segments {
            // Half-open: a tick at exactly `end` must not re-enter the segment its own seek
            // just landed in.
            guard segment.start <= currentTime, currentTime < segment.end else { continue }
            guard !handled.contains(segment.id) else { continue }
            guard let category = segment.category, enabledCategories.contains(category) else { continue }
            // Re-clamp against the duration supplied here, not only at normalization time —
            // `playableSegments` may have clamped against a different (TA metadata) duration.
            let clampedEnd = min(segment.end, duration)
            guard clampedEnd > currentTime else { continue }
            if clampedEnd >= duration * endOfVideoFraction { return .none }
            return .skip(to: clampedEnd, segment: segment)
        }
        return .none
    }
}
