// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PleviCore",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PleviCore", targets: ["PleviCore"])
    ],
    targets: [
        .target(
            name: "PleviCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PleviCoreTests",
            dependencies: ["PleviCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
