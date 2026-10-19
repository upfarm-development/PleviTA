import Foundation
import Testing
@testable import PleviCore

@Suite("OfflineNetworkPolicy")
struct OfflineNetworkPolicyTests {
    @Test("cellular allowed always starts, whatever the connection")
    func cellularAllowedAlwaysStarts() {
        #expect(OfflineNetworkPolicy.shouldStartNow(allowsCellular: true, isExpensiveConnection: true))
        #expect(OfflineNetworkPolicy.shouldStartNow(allowsCellular: true, isExpensiveConnection: false))
    }

    @Test("cellular disallowed still starts on a non-expensive connection")
    func disallowedStillStartsOnWiFi() {
        #expect(OfflineNetworkPolicy.shouldStartNow(allowsCellular: false, isExpensiveConnection: false))
    }

    @Test("cellular disallowed on an expensive connection blocks the start")
    func disallowedBlocksOnCellular() {
        #expect(!OfflineNetworkPolicy.shouldStartNow(allowsCellular: false, isExpensiveConnection: true))
    }
}
