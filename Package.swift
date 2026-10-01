// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        // Plugin infrastructure. Must not depend on any feature or on the app target.
        .target(
            name: "DeskBuddyCore",
            path: "Sources/DeskBuddyCore"
        ),
        .executableTarget(
            name: "DeskBuddy",
            dependencies: ["DeskBuddyCore", "Yams"],
            path: "Sources/DeskBuddy",
            resources: [
                .copy("Resources/Localizations")
            ]
        ),
        .testTarget(
            name: "DeskBuddyCoreTests",
            dependencies: ["DeskBuddyCore"],
            path: "Tests/DeskBuddyCoreTests"
        ),
    ]
)
