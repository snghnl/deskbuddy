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
        // What macOS needs on top of Core to draw plugins' UI: SwiftUI views as PlatformView,
        // the list panel's environment, the Liquid Glass look
        .target(
            name: "DeskBuddyMacUI",
            dependencies: ["DeskBuddyCore"],
            path: "Sources/DeskBuddyMacUI"
        ),
        // The to-do feature's public API: types and protocols other features may depend on
        .target(
            name: "TodoAPI",
            dependencies: ["DeskBuddyCore"],
            path: "Sources/TodoAPI"
        ),
        // To-dos: keeping them, the commands, the logic, on any platform
        .target(
            name: "TodoPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/TodoPlugin",
            resources: [.copy("Resources/Localizations")]
        ),
        // To-dos on macOS: the tabs, the detail page, the history in Settings
        .target(
            name: "TodoMac",
            dependencies: ["DeskBuddyCore", "DeskBuddyMacUI", "TodoAPI", "TodoPlugin"],
            path: "Sources/TodoMac"
        ),
        // Countdown timers, optionally linked to to-dos: the logic, on any platform
        .target(
            name: "PomodoroPlugin",
            dependencies: ["DeskBuddyCore", "TodoAPI"],
            path: "Sources/PomodoroPlugin",
            resources: [.copy("Resources/Localizations")]
        ),
        // The timers on macOS: the Timer tab, the to-do row icon, the sound
        .target(
            name: "PomodoroMac",
            dependencies: ["DeskBuddyCore", "DeskBuddyMacUI", "TodoAPI", "PomodoroPlugin"],
            path: "Sources/PomodoroMac"
        ),
        // The calendar's logic on any platform: event alerts, preferences, the event model
        .target(
            name: "CalendarPlugin",
            dependencies: ["DeskBuddyCore"],
            path: "Sources/CalendarPlugin",
            resources: [.copy("Resources/Localizations")]
        ),
        // The calendar on macOS: EventKit, the Calendar tab, the Settings rows; reads to-dos through TodoAPI
        .target(
            name: "CalendarMac",
            dependencies: ["DeskBuddyCore", "DeskBuddyMacUI", "TodoAPI", "CalendarPlugin"],
            path: "Sources/CalendarMac"
        ),
        // What the A2UI feature offers others: show a described UI, hear what the user did
        .target(
            name: "A2UIAPI",
            path: "Sources/A2UIAPI"
        ),
        // Shows UI described in DeskBuddy's A2UI subset as panels: parsing, inputs, actions
        .target(
            name: "A2UIPlugin",
            dependencies: ["DeskBuddyCore", "A2UIAPI"],
            path: "Sources/A2UIPlugin"
        ),
        // A2UI panels on macOS: the components as SwiftUI controls
        .target(
            name: "A2UIMac",
            dependencies: ["DeskBuddyCore", "DeskBuddyMacUI", "A2UIAPI", "A2UIPlugin"],
            path: "Sources/A2UIMac"
        ),
        // Claude Code's questions to the user, shown through A2UI
        .target(
            name: "ClaudePlugin",
            dependencies: ["DeskBuddyCore", "A2UIAPI"],
            path: "Sources/ClaudePlugin",
            resources: [.copy("Resources/Localizations")]
        ),
        // Puts the plugins together: registers them and hosts the UI they contribute to
        .executableTarget(
            name: "DeskBuddy",
            dependencies: ["DeskBuddyCore", "DeskBuddyMacUI", "TodoPlugin", "TodoMac", "PomodoroPlugin", "PomodoroMac", "CalendarPlugin",
                           "CalendarMac", "A2UIPlugin", "A2UIMac", "ClaudePlugin"],
            path: "Sources/DeskBuddy",
            resources: [.copy("Resources/Localizations")]
        ),
        // The app's own logic, such as moving old data into plugin storage
        .testTarget(
            name: "DeskBuddyTests",
            dependencies: ["DeskBuddy", "DeskBuddyCore", "TodoPlugin", "PomodoroPlugin"],
            path: "Tests/DeskBuddyTests"
        ),
        .testTarget(
            name: "DeskBuddyCoreTests",
            dependencies: ["DeskBuddyCore"],
            path: "Tests/DeskBuddyCoreTests",
            resources: [.copy("Resources/Localizations")]
        ),
        .testTarget(
            name: "TodoPluginTests",
            dependencies: ["TodoPlugin", "TodoMac", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/TodoPluginTests"
        ),
        .testTarget(
            name: "A2UIPluginTests",
            dependencies: ["A2UIPlugin", "A2UIMac", "A2UIAPI", "DeskBuddyCore"],
            path: "Tests/A2UIPluginTests"
        ),
        // Runs a question through the real A2UI plugin, the way the app wires them
        .testTarget(
            name: "ClaudePluginTests",
            dependencies: ["ClaudePlugin", "A2UIPlugin", "A2UIMac", "A2UIAPI", "DeskBuddyCore"],
            path: "Tests/ClaudePluginTests"
        ),
        .testTarget(
            name: "CalendarPluginTests",
            dependencies: ["CalendarPlugin", "CalendarMac", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/CalendarPluginTests"
        ),
        .testTarget(
            name: "PomodoroPluginTests",
            dependencies: ["PomodoroPlugin", "PomodoroMac", "DeskBuddyCore", "TodoAPI"],
            path: "Tests/PomodoroPluginTests"
        ),
    ]
)
