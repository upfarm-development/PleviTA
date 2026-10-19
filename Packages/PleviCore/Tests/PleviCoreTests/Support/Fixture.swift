
import Foundation

enum Fixture {
    /// `Packages/PleviCore/Tests/PleviCoreTests/Support/Fixture.swift` -> repo root.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Fixture.swift -> Support/
            .deletingLastPathComponent() // Support -> PleviCoreTests/
            .deletingLastPathComponent() // PleviCoreTests -> Tests/
            .deletingLastPathComponent() // Tests -> PleviCore/
            .deletingLastPathComponent() // PleviCore -> Packages/
            .deletingLastPathComponent() // Packages -> repo root
    }

    static var directory: URL {
        repoRoot.appendingPathComponent("Fixtures")
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}
