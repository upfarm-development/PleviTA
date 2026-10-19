
import Foundation
import Testing
@testable import PleviCore

@Suite("ResumePolicy")
struct ResumePolicyTests {
    @Test("a watched video always starts from the beginning, regardless of behavior or position")
    func watchedVideoAlwaysStartsFromBeginning() {
        for behavior in ResumeBehavior.allCases {
            #expect(
                ResumePolicy.decide(behavior: behavior, isWatched: true, position: 600, duration: 1000)
                    == .startFromBeginning
            )
        }
    }

    @Test("nil or a position under the 10s floor starts from the beginning; 10s itself does not")
    func nilOrTinyPositionStartsFromBeginning() {
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: nil, duration: 1000)
                == .startFromBeginning
        )
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 0, duration: 1000)
                == .startFromBeginning
        )
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 9.9, duration: 1000)
                == .startFromBeginning
        )
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 10, duration: 1000)
                != .startFromBeginning
        )
    }

    @Test("a position at or past 95% of duration starts from the beginning; short of it does not")
    func positionNearTheEndStartsFromBeginning() {
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 950, duration: 1000)
                == .startFromBeginning
        )
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 999, duration: 1000)
                == .startFromBeginning
        )
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 949, duration: 1000)
                != .startFromBeginning
        )
        // The end guard can't fire without a duration to compare against.
        #expect(
            ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: 999_999, duration: nil)
                != .startFromBeginning
        )
    }

    @Test("alwaysResume never asks, at any qualifying position")
    func alwaysResumeNeverAsks() {
        for position in [10.0, 29.9, 30.0, 31.0, 600.0] {
            #expect(
                ResumePolicy.decide(behavior: .alwaysResume, isWatched: false, position: position, duration: 1000)
                    == .resume(position: position)
            )
        }
    }

    @Test("ask only fires strictly above 30 seconds — matching the pre-existing tvOS rule exactly")
    func askOnlyAboveThirtySeconds() {
        #expect(
            ResumePolicy.decide(behavior: .ask, isWatched: false, position: 30, duration: 1000)
                == .resume(position: 30)
        )
        #expect(
            ResumePolicy.decide(behavior: .ask, isWatched: false, position: 30.1, duration: 1000)
                == .ask(position: 30.1)
        )
    }

    @Test("the label's decision and the tap action's decision always agree")
    func labelAndActionAgree() {
        for position in [9.9, 10.0, 949.0, 950.0] {
            let alwaysResumeDecision = ResumePolicy.decide(
                behavior: .alwaysResume, isWatched: false, position: position, duration: 1000)
            let askDecision = ResumePolicy.decide(
                behavior: .ask, isWatched: false, position: position, duration: 1000)
            // Both behaviors are computed from the same call `playLabelText` and `tapPlay` both
            // make — this just pins that the two thresholds (10s floor, 95% ceiling) apply
            // identically regardless of which behavior is in effect.
            switch (alwaysResumeDecision, askDecision) {
            case (.startFromBeginning, .startFromBeginning):
                break
            case (.resume(let p1), .resume(let p2)), (.resume(let p1), .ask(let p2)):
                #expect(p1 == p2)
            default:
                Issue.record("alwaysResume=\(alwaysResumeDecision) ask=\(askDecision) disagree on position \(position)")
            }
        }
    }

    @Test("silentStartPosition returns nil exactly where alwaysResume would start from the beginning")
    func silentStartPositionMatchesAlwaysResume() {
        let cases: [(isWatched: Bool, position: Double?, duration: Double?)] = [
            (true, 600, 1000),
            (false, nil, 1000),
            (false, 9.9, 1000),
            (false, 10, 1000),
            (false, 950, 1000),
            (false, 949, 1000),
            (false, 600, nil),
        ]
        for testCase in cases {
            let decision = ResumePolicy.decide(
                behavior: .alwaysResume, isWatched: testCase.isWatched, position: testCase.position,
                duration: testCase.duration)
            let silent = ResumePolicy.silentStartPosition(
                isWatched: testCase.isWatched, position: testCase.position, duration: testCase.duration)
            if case .resume(let position) = decision {
                #expect(silent == position)
            } else {
                #expect(silent == nil)
            }
        }
    }
}
