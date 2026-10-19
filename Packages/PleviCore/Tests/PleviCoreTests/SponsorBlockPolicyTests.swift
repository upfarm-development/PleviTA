
import Foundation
import Testing
@testable import PleviCore

@Suite("SponsorBlockPolicy")
struct SponsorBlockPolicyTests {
    private func segment(
        id: String = "seg1", category: SponsorCategory? = .sponsor, start: Double = 100, end: Double = 110
    ) -> SponsorSegment {
        SponsorSegment(id: id, category: category, start: start, end: end)
    }

    private func raw(
        id: String? = "u1", category: String? = "sponsor", segment: [Double]? = [10, 20], locked: Int? = 0
    ) -> SponsorBlockSegment {
        SponsorBlockSegment(
            segmentID: id, category: category, actionType: "none", segment: segment,
            videoDuration: 1000, votes: 0, locked: locked)
    }

    // MARK: - decide: enabled / disabled

    @Test("disabled never skips, regardless of position, category or handled state")
    func disabledNeverSkips() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment()], currentTime: 105, duration: 1000, isEnabled: false,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    // MARK: - decide: position matrix (half-open containment)

    @Test("before a segment's start does not skip")
    func beforeStartDoesNotSkip() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(start: 100, end: 110)], currentTime: 99.9, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    @Test("exactly at a segment's start skips")
    func atStartSkips() {
        let seg = segment(start: 100, end: 110)
        let decision = SponsorBlockPolicy.decide(
            segments: [seg], currentTime: 100, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .skip(to: 110, segment: seg))
    }

    @Test("inside a segment skips")
    func insideSkips() {
        let seg = segment(start: 100, end: 110)
        let decision = SponsorBlockPolicy.decide(
            segments: [seg], currentTime: 105, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .skip(to: 110, segment: seg))
    }

    @Test("exactly at a segment's end does not re-enter it — half-open containment")
    func atEndDoesNotSkip() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(start: 100, end: 110)], currentTime: 110, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    @Test("after a segment's end does not skip")
    func afterEndDoesNotSkip() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(start: 100, end: 110)], currentTime: 110.1, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    // MARK: - decide: category and handled gates

    @Test("a category outside enabledCategories is never skipped")
    func disabledCategoryNeverSkips() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(category: .interaction, start: 100, end: 110)], currentTime: 105, duration: 1000,
            isEnabled: true, enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    @Test("a known-but-not-skipped category (intro) is never skipped, even though it's recognised")
    func introIsNeverSkipped() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(category: .intro, start: 100, end: 110)], currentTime: 105, duration: 1000,
            isEnabled: true, enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    @Test("a segment with no recognised category (nil) is never skipped")
    func unrecognisedCategoryNeverSkips() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(category: nil, start: 100, end: 110)], currentTime: 105, duration: 1000,
            isEnabled: true, enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    @Test("an already-handled id is never skipped again")
    func handledIDNeverSkipsAgain() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(id: "seg1", start: 100, end: 110)], currentTime: 105, duration: 1000,
            isEnabled: true, enabledCategories: SponsorBlockPolicy.defaultCategories, handled: ["seg1"])
        #expect(decision == .none)
    }

    // MARK: - end-of-video rule

    @Test("a segment whose clamped end lands at or past 95% of duration is never skipped, and short of it skips normally")
    func endOfVideoRuleSuppressesSkip() {
        // duration 1000, threshold 950 — end exactly at the threshold must suppress.
        let atThreshold = segment(start: 900, end: 950)
        #expect(SponsorBlockPolicy.decide(
            segments: [atThreshold], currentTime: 905, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: []) == .none)
        // Just short of the threshold still skips normally.
        let justShort = segment(start: 900, end: 949)
        #expect(SponsorBlockPolicy.decide(
            segments: [justShort], currentTime: 905, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
            == .skip(to: 949, segment: justShort))
    }

    // MARK: - nil duration

    @Test("nil duration never skips, even with an otherwise fully-valid segment")
    func nilDurationNeverSkips() {
        let decision = SponsorBlockPolicy.decide(
            segments: [segment(start: 100, end: 110)], currentTime: 105, duration: nil, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    // MARK: - decide re-clamps against its own duration

    @Test("a segment whose end exceeds the duration passed to decide never produces a plain skip")
    func decideNeverSkipsPastItsOwnDuration() {
        let seg = segment(start: 100, end: 500)
        let decision = SponsorBlockPolicy.decide(
            segments: [seg], currentTime: 105, duration: 200, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(decision == .none)
    }

    // MARK: - playableSegments: hostile input

    @Test("NaN or infinite times are dropped")
    func nonFiniteTimesDropped() {
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(segment: [.nan, 20])], duration: 1000).isEmpty)
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(segment: [10, .infinity])], duration: 1000).isEmpty)
    }

    @Test("a negative start is dropped")
    func negativeStartDropped() {
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(segment: [-5, 20])], duration: 1000).isEmpty)
    }

    @Test("end <= start is dropped, including a zero-length poi_highlight segment")
    func endNotAfterStartDropped() {
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(segment: [20, 10])], duration: 1000).isEmpty)
        // poi_highlight segments are zero-length on the wire by construction (confirmed live).
        #expect(SponsorBlockPolicy.playableSegments(
            from: [raw(category: "poi_highlight", segment: [50, 50])], duration: 1000
        ).isEmpty)
    }

    @Test("a segment shorter than minimumSegmentDuration is dropped")
    func tooShortSegmentDropped() {
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(segment: [10, 10.5])], duration: 1000).isEmpty)
    }

    @Test("a segment longer than the video is kept, clamped to duration")
    func longerThanVideoClamped() {
        let result = SponsorBlockPolicy.playableSegments(from: [raw(segment: [10, 5000])], duration: 1000)
        #expect(result.count == 1)
        #expect(result.first?.end == 1000)
    }

    @Test("a nil duration leaves a segment unclamped")
    func nilDurationLeavesUnclamped() {
        let result = SponsorBlockPolicy.playableSegments(from: [raw(segment: [10, 5000])], duration: nil)
        #expect(result.count == 1)
        #expect(result.first?.end == 5000)
    }

    @Test("overlapping segments of the same category merge into one")
    func overlappingSegmentsMerge() {
        let result = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", segment: [10, 50]), raw(id: "b", segment: [40, 80])], duration: 1000)
        #expect(result.count == 1)
        #expect(result.first?.start == 10)
        #expect(result.first?.end == 80)
    }

    @Test("near-adjacent segments of the same category (within minimumSegmentDuration) merge into one")
    func nearAdjacentSegmentsMerge() {
        let result = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", segment: [10, 20]), raw(id: "b", segment: [20.9, 30])], duration: 1000)
        #expect(result.count == 1)
        #expect(result.first?.start == 10)
        #expect(result.first?.end == 30)
    }

    @Test("segments of different categories never merge, however close they sit")
    func differentCategoriesDoNotMerge() {
        // The exact shape that made this a bug: a skippable category ending a moment before a
        // never-skipped one. Merging would produce one span carrying the first's category, so
        // the outro would be skipped under selfpromo's name.
        let result = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", category: "selfpromo", segment: [10, 20]),
                   raw(id: "b", category: "outro", segment: [20.5, 40])],
            duration: 1000)
        #expect(result.count == 2)
        #expect(result.first?.category == .selfpromo)
        #expect(result.first?.end == 20)
        #expect(result.last?.category == .outro)
        #expect(result.last?.start == 20.5)
    }

    @Test("a never-skipped category abutting a skippable one is not dragged into the skip")
    func adjacentIntroIsNotSkippedWithSponsor() {
        // End to end through `decide`, not just the normalizer: the guarantee that matters is
        // "intros are never skipped", and it has to survive adjacency.
        let segments = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", category: "sponsor", segment: [0, 30]),
                   raw(id: "b", category: "intro", segment: [30.5, 60])],
            duration: 1000)
        let atSponsor = SponsorBlockPolicy.decide(
            segments: segments, currentTime: 5, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: [])
        #expect(atSponsor == .skip(to: 30, segment: segments[0]))

        // Inside the intro, with the sponsor already handled: nothing more to do.
        let atIntro = SponsorBlockPolicy.decide(
            segments: segments, currentTime: 40, duration: 1000, isEnabled: true,
            enabledCategories: SponsorBlockPolicy.defaultCategories, handled: ["a"])
        #expect(atIntro == .none)
    }

    @Test("segments well apart do not merge")
    func farApartSegmentsDoNotMerge() {
        let result = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", segment: [10, 20]), raw(id: "b", segment: [25, 30])], duration: 1000)
        #expect(result.count == 2)
    }

    @Test("a nil or empty segment id is dropped")
    func nilOrEmptyIDDropped() {
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(id: nil, segment: [10, 20])], duration: 1000).isEmpty)
        #expect(SponsorBlockPolicy.playableSegments(from: [raw(id: "", segment: [10, 20])], duration: 1000).isEmpty)
    }

    @Test("a duplicate id keeps only the first occurrence")
    func duplicateIDKeepsFirst() {
        let result = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "dup", segment: [10, 20]), raw(id: "dup", segment: [100, 110])], duration: 1000)
        #expect(result.count == 1)
        #expect(result.first?.start == 10)
    }

    @Test("an unrecognised category string survives as category: nil, not discarded")
    func unrecognisedCategoryStringSurvivesAsNil() {
        let result = SponsorBlockPolicy.playableSegments(from: [raw(category: "foobar", segment: [10, 20])], duration: 1000)
        #expect(result.count == 1)
        #expect(result.first?.category == nil)
    }

    // An entirely absent `SponsorBlockInfo` reaches this function the same way, via a caller
    // doing `video.sponsorblock?.segments ?? []` — there is no separate code path to test.
    @Test("an empty segment array produces no output")
    func emptyInputProducesNoOutput() {
        #expect(SponsorBlockPolicy.playableSegments(from: [], duration: 1000).isEmpty)
    }

    // MARK: - raw values and constants, pinned

    @Test("SponsorCategory raw values match every one of the nine strings Tube Archivist requests")
    func categoryRawValuesPinned() {
        #expect(SponsorCategory(rawValue: "sponsor") == .sponsor)
        #expect(SponsorCategory(rawValue: "selfpromo") == .selfpromo)
        #expect(SponsorCategory(rawValue: "interaction") == .interaction)
        #expect(SponsorCategory(rawValue: "intro") == .intro)
        #expect(SponsorCategory(rawValue: "outro") == .outro)
        #expect(SponsorCategory(rawValue: "preview") == .preview)
        #expect(SponsorCategory(rawValue: "filler") == .filler)
        #expect(SponsorCategory(rawValue: "music_offtopic") == .musicOfftopic)
        #expect(SponsorCategory(rawValue: "poi_highlight") == .poiHighlight)
        #expect(SponsorCategory.allCases.count == 9)
    }

    @Test("defaultCategories is exactly sponsor and selfpromo — intros and outros start off")
    func defaultCategoriesPinned() {
        #expect(SponsorBlockPolicy.defaultCategories == [.sponsor, .selfpromo])
        // Deliberately not the default, though they can now be chosen: an app that starts
        // cutting the opening seconds of every video without being asked is a worse first
        // impression than one that skips nothing.
        #expect(!SponsorBlockPolicy.defaultCategories.contains(.intro))
        #expect(!SponsorBlockPolicy.defaultCategories.contains(.outro))
    }

    @Test("userSelectableCategories are the four offered, in order, and all are real wire values")
    func userSelectableCategoriesPinned() {
        #expect(SponsorBlockPolicy.userSelectableCategories == [.sponsor, .selfpromo, .intro, .outro])
        // A category that cannot be a skip range must never reach Settings: poi_highlight is
        // zero-length on the wire and `playableSegments` drops it, so a row for it would be a
        // control that provably does nothing.
        #expect(!SponsorBlockPolicy.userSelectableCategories.contains(.poiHighlight))
    }

    @Test("category display names are SponsorBlock's own, not paraphrases")
    func displayNamesMatchSponsorBlock() {
        // Verbatim from ajayyy/ExtensionTranslations en/messages.json — the submodule the
        // extension ships as public/_locales. Pinned so a later tidy-up of the slashes is a
        // deliberate divergence from SponsorBlock rather than an accident.
        #expect(SponsorCategory.sponsor.displayName == "Sponsor")
        #expect(SponsorCategory.selfpromo.displayName == "Unpaid/Self Promotion")
        #expect(SponsorCategory.intro.displayName == "Intermission/Intro Animation")
        #expect(SponsorCategory.outro.displayName == "Endcards/Credits")
    }

    @Test("an enabled intro is skipped, and a disabled sponsor is not — the set is what decides")
    func categorySetDrivesTheDecision() {
        let segments = SponsorBlockPolicy.playableSegments(
            from: [raw(id: "a", category: "intro", segment: [0, 30])], duration: 1000)
        #expect(SponsorBlockPolicy.decide(
            segments: segments, currentTime: 5, duration: 1000, isEnabled: true,
            enabledCategories: [.intro], handled: []) == .skip(to: 30, segment: segments[0]))
        #expect(SponsorBlockPolicy.decide(
            segments: segments, currentTime: 5, duration: 1000, isEnabled: true,
            enabledCategories: [.sponsor], handled: []) == .none)
    }

    @Test("minimumSegmentDuration mirrors both engines' ~1Hz tick rate")
    func minimumSegmentDurationPinned() {
        #expect(SponsorBlockPolicy.minimumSegmentDuration == 1.0)
    }

    @Test("endOfVideoFraction takes the lower of ProgressReporter's 0.95 and VLCPlayerEngine's 0.98")
    func endOfVideoFractionPinned() {
        #expect(SponsorBlockPolicy.endOfVideoFraction == 0.95)
    }
    // MARK: - Re-arming after scrubbing back

    private func seg(_ id: String, _ start: Double, _ end: Double) -> SponsorSegment {
        SponsorSegment(id: id, category: .sponsor, start: start, end: end)
    }

    @Test("scrubbing back in front of a skipped segment arms it again")
    func rearmsWhenPlayheadMovesBackBefore() {
        let segments = [seg("a", 0, 5.28), seg("b", 356.573, 442.578)]
        let rearmed = SponsorBlockPolicy.rearmed(
            handled: ["a", "b"], segments: segments, currentTime: 300)
        #expect(rearmed == ["a"], "b starts after 300, so it should be armed again")

        // And it really does skip once armed.
        let decision = SponsorBlockPolicy.decide(
            segments: segments, currentTime: 360, duration: 907,
            isEnabled: true, enabledCategories: [.sponsor], handled: rearmed)
        #expect(decision == .skip(to: 442.578, segment: segments[1]))
    }

    @Test("a playhead still past a segment leaves it handled")
    func doesNotRearmWhatIsBehindThePlayhead() {
        let segments = [seg("a", 0, 5.28), seg("b", 356.573, 442.578)]
        #expect(SponsorBlockPolicy.rearmed(handled: ["a", "b"], segments: segments, currentTime: 500)
                == ["a", "b"])
    }

    @Test("seeking into the middle of a segment does not arm it")
    func seekingInsideDoesNotRearm() {
        // Same rule `start` applies to a resume position landing inside a segment: a user
        // who puts the playhead there is not asking to be moved out of it.
        let segments = [seg("b", 356.573, 442.578)]
        #expect(SponsorBlockPolicy.rearmed(handled: ["b"], segments: segments, currentTime: 400)
                == ["b"])
    }

    @Test("a playhead exactly at a segment's start arms it")
    func rearmsExactlyAtStart() {
        let segments = [seg("b", 356.573, 442.578)]
        #expect(SponsorBlockPolicy.rearmed(handled: ["b"], segments: segments, currentTime: 356.573)
                .isEmpty)
    }

    @Test("scrubbing to the very start arms the opening segment")
    func rearmsOpeningSegmentAtZero() {
        let segments = [seg("a", 0, 5.28)]
        #expect(SponsorBlockPolicy.rearmed(handled: ["a"], segments: segments, currentTime: 0)
                .isEmpty)
    }

}
