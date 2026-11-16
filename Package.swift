// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Slimreel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlimreelKit", targets: ["SlimreelKit"]),
    ],
    targets: [
        // Pure logic with unit tests: formatting, file naming, date ranges, shrink rules.
        .target(name: "SlimreelKit"),

        // The app. `make bundle` wraps this binary in the .app.
        // AVKit is linked explicitly: SwiftPM doesn't autolink it, and AVPlayerView needs it.
        .executableTarget(
            name: "SlimreelApp",
            dependencies: ["SlimreelKit"],
            linkerSettings: [.linkedFramework("AVKit")]
        ),

        .testTarget(name: "SlimreelKitTests", dependencies: ["SlimreelKit"]),
    ],
    swiftLanguageModes: [.v5]
)
