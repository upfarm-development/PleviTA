// The rules behind "go back to where I was, but not forever" — see the policy's own doc comment for the report these come from.

import Foundation
import Testing
@testable import PleviCore

@Suite("NavigationRestorePolicy")
struct NavigationRestorePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a place saved moments ago on the same build is restored")
    func freshSameBuildRestores() {
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(-30),
            savedBuild: "119",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .restore)
    }

    @Test("a different build forgets, however recently it was saved")
    func updatedBuildDiscards() {
        // "When the app is force quit or updated forget all positions." The build number
        // moves on every commit, so any update at all counts.
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(-1),
            savedBuild: "118",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .discardUpdatedBuild)
    }

    @Test("too old forgets — the app fell out of memory while the user was elsewhere")
    func staleDiscards() {
        let justOver = NavigationRestorePolicy.maxAge + 1
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(-justOver),
            savedBuild: "119",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .discardStale)
    }

    @Test("the boundary itself still restores")
    func boundaryRestores() {
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(-NavigationRestorePolicy.maxAge),
            savedBuild: "119",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .restore, "exactly maxAge old is not yet too old")
    }

    @Test("the build check wins over the age check")
    func buildBeatsAge() {
        // Both reasons apply; which one is reported matters only for reading a log, but
        // the decision must be a discard either way rather than falling through.
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(-(NavigationRestorePolicy.maxAge * 10)),
            savedBuild: "100",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .discardUpdatedBuild)
    }

    @Test("a snapshot stamped in the future is treated as fresh, not as stale")
    func clockMovedBackwards() {
        // A device whose clock moved should not lose the user's place: landing them where
        // they were is the milder of the two wrong answers.
        let decision = NavigationRestorePolicy.decide(
            savedAt: now.addingTimeInterval(3600),
            savedBuild: "119",
            now: now,
            currentBuild: "119"
        )
        #expect(decision == .restore)
    }
}
