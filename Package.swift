// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnipClip",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SnipClip",
            path: "Sources/SnipClip",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
