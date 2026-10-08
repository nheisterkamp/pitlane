// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TMLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TMLauncher",
            path: "Sources/TMLauncher",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ]
)
