// swift-tools-version: 6.0
import PackageDescription

// Kept so the project opens directly in Xcode once it is installed.
// The working build today is Scripts/build-app.sh — this machine's SwiftPM is broken
// (see README, "Toolchain note").
let package = Package(
    name: "SpaceSwitcher",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "SpaceSwitcher",
            path: "Sources/SpaceSwitcher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
