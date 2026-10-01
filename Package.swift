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
        // To-dos: the To Do and Done tabs, the detail page, the history in Settings
        .target(
            name: "TodoPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/TodoPlugin"
        ),
        // Countdown timers, optionally linked to to-dos
        .target(
            name: "PomodoroPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/PomodoroPlugin"
        ),
        // The Calendar tab, calendar settings and event alerts; reads to-dos through TodoAPI
        .target(
            name: "CalendarPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/CalendarPlugin"
        ),
        // Puts the plugins together: registers them and hosts the UI they contribute to
        .executableTarget(
            name: "DeskBuddy",
            dependencies: ["DeskBuddyCore", "TodoPlugin", "PomodoroPlugin", "CalendarPlugin"],
            path: "Sources/DeskBuddy"
        ),
        .testTarget(
            name: "DeskBuddyCoreTests",
            dependencies: ["DeskBuddyCore"],
            path: "Tests/DeskBuddyCoreTests"
        ),
        .testTarget(
            name: "TodoPluginTests",
            dependencies: ["TodoPlugin", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/TodoPluginTests"
        ),
        .testTarget(
            name: "CalendarPluginTests",
            dependencies: ["CalendarPlugin", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/CalendarPluginTests"
        ),
        .testTarget(
            name: "PomodoroPluginTests",
            dependencies: ["PomodoroPlugin", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/PomodoroPluginTests"
        ),
    ]
)
