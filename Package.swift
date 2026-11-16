// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShrinkEm",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShrinkEmKit", targets: ["ShrinkEmKit"]),
    ],
    targets: [
        // Pure logic with unit tests: formatting, file naming, date ranges, shrink rules.
        .target(name: "ShrinkEmKit"),

        // The app. `make bundle` wraps this binary in the .app.
        // AVKit is linked explicitly: SwiftPM doesn't autolink it, and AVPlayerView needs it.
        .executableTarget(
            name: "ShrinkEmApp",
            dependencies: ["ShrinkEmKit"],
            linkerSettings: [.linkedFramework("AVKit")]
        ),

        .testTarget(name: "ShrinkEmKitTests", dependencies: ["ShrinkEmKit"]),
    ],
    swiftLanguageModes: [.v5]
)
