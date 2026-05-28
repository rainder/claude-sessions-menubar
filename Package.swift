// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessionsMenubar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeSessionsMenubar",
            path: "Sources/ClaudeSessionsMenubar"
        )
    ]
)
