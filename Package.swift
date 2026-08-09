// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DeskBuddy",
            path: "Sources/DeskBuddy"
        )
    ]
)
