// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        // Plugin infrastructure, plus what every feature shares (the localized strings).
        // Must not depend on any feature or on the app target.
        .target(
            name: "DeskBuddyCore",
            dependencies: ["Yams"],
            path: "Sources/DeskBuddyCore",
            resources: [
                .copy("Resources/Localizations")
            ]
        ),
        // The to-do feature's public API: types and protocols other features may depend on
        .target(
            name: "TodoAPI",
            dependencies: ["DeskBuddyCore"],
            path: "Sources/TodoAPI"
        ),
        // Countdown timers, optionally linked to to-dos
        .target(
            name: "PomodoroPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/PomodoroPlugin"
        ),
        .executableTarget(
            name: "DeskBuddy",
            dependencies: ["DeskBuddyCore", "TodoAPI", "PomodoroPlugin"],
            path: "Sources/DeskBuddy"
        ),
        .testTarget(
            name: "DeskBuddyCoreTests",
            dependencies: ["DeskBuddyCore"],
            path: "Tests/DeskBuddyCoreTests"
        ),
        .testTarget(
            name: "PomodoroPluginTests",
            dependencies: ["PomodoroPlugin", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/PomodoroPluginTests"
        ),
    ]
)
