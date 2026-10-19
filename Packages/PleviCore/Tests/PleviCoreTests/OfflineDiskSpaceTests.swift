import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineDiskSpace")
struct OfflineDiskSpaceTests {
    @Test("plenty of free space passes")
    func plentyOfSpacePasses() {
        #expect(OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: 1_000_000, availableCapacity: 1_000_000_000))
    }

    @Test("clearly not enough space fails")
    func notEnoughSpaceFails() {
        #expect(!OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: 1_000_000_000, availableCapacity: 1_000_000))
    }

    @Test("exactly the estimated size fails — the safety margin must actually apply")
    func exactSizeFailsMargin() {
        #expect(!OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: 1_000_000, availableCapacity: 1_000_000))
    }

    @Test("space at 10% over the estimate passes")
    func marginItselfPasses() {
        #expect(OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: 1_000_000, availableCapacity: 1_100_000))
    }

    @Test("no estimated size at all always passes — nothing to precheck against")
    func noEstimateAlwaysPasses() {
        #expect(OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: nil, availableCapacity: 0))
    }

    @Test("a zero or negative estimate always passes")
    func nonPositiveEstimateAlwaysPasses() {
        #expect(OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: 0, availableCapacity: 0))
        #expect(OfflineDiskSpace.hasEnoughFreeSpace(estimatedByteCount: -5, availableCapacity: 0))
    }
}
