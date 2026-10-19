import Testing
@testable import PleviCore

@Suite("PleviCore bootstrap")
struct PleviCoreTests {
    @Test("Package builds and exposes a version")
    func packageBuilds() {
        #expect(PleviCoreInfo.version == "0.1.0")
    }
}
