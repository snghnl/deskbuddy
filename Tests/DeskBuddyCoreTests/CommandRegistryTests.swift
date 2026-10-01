import XCTest
@testable import DeskBuddyCore

@MainActor
final class CommandRegistryTests: XCTestCase {
    func testRunsTheHandlerRegisteredUnderTheName() throws {
        let commands = CommandRegistry()
        var received: String?
        commands.register("todo.add") { received = $0["title"] }

        try commands.execute("todo.add", CommandArguments(["title": "Buy milk"]))

        XCTAssertEqual(received, "Buy milk")
    }

    func testUnknownCommandThrows() {
        XCTAssertThrowsError(try CommandRegistry().execute("nope.nothing")) { error in
            XCTAssertEqual(error as? CommandError, .unknownCommand("nope.nothing"))
        }
    }

    func testHandlerErrorsReachTheCaller() {
        let commands = CommandRegistry()
        commands.register("todo.add") { _ in throw CommandError.missingArgument("title") }

        XCTAssertThrowsError(try commands.execute("todo.add")) { error in
            XCTAssertEqual(error as? CommandError, .missingArgument("title"))
        }
    }

    func testArgumentsReadAsNumbersOnlyWhenTheyAreNumbers() {
        let arguments = CommandArguments(["minutes": "25", "autohide": "2.5", "label": "focus"])

        XCTAssertEqual(arguments.int("minutes"), 25)
        XCTAssertEqual(arguments.double("autohide"), 2.5)
        XCTAssertNil(arguments.int("label"))
        XCTAssertNil(arguments.int("missing"))
        XCTAssertEqual(arguments["label"], "focus")
    }

    func testPluginsRegisterThroughTheirContext() throws {
        let manager = PluginManager(buddy: RecordingBuddy())
        manager.register(GreeterPlugin())
        manager.activateAll()

        try manager.commands.execute("greeter.hello", CommandArguments(["name": "buddy"]))

        XCTAssertEqual((manager.buddy as? RecordingBuddy)?.said, ["hello buddy"])
    }
}

@MainActor
private final class GreeterPlugin: DeskBuddyPlugin {
    let manifest = PluginManifest(id: "greeter", name: "Greeter", version: "0.0.0")

    func activate(_ context: PluginContext) throws {
        context.commands.register("greeter.hello") { [buddy = context.buddy] arguments in
            buddy.say("hello \(arguments["name"] ?? "")")
        }
    }

    func deactivate() {}
}
