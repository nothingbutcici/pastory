// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pastory",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Pastory",
            path: "Sources/Pastory",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
