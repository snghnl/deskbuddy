import XCTest
@testable import DeskBuddyCore

@MainActor
final class SurfaceManagerTests: XCTestCase {
    private let alert = SurfaceID("test.alert")

    func testPresentUpdateDismissReachTheWindows() {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)

        surfaces.present(.bubble("in 5 min"), id: alert)
        surfaces.update(alert, to: .bubble("in 4 min"))
        XCTAssertTrue(surfaces.isPresented(alert))
        surfaces.dismiss(alert)

        XCTAssertEqual(presenter.log, ["show test.alert bubble in 5 min", "update test.alert bubble in 4 min", "hide test.alert"])
        XCTAssertFalse(surfaces.isPresented(alert))
    }

    func testUpdatingOrDismissingWhatIsNotUpDoesNothing() {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)

        surfaces.update(alert, to: .bubble("late"))
        surfaces.dismiss(alert)

        XCTAssertEqual(presenter.log, [])
    }

    func testOnCloseRunsWhenTheUserClosesItButNotOnDismiss() throws {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)
        var closed: [String] = []
        surfaces.present(.panel(FormView()), id: alert) { closed.append("first") }
        let end = try XCTUnwrap(presenter.endings[alert])

        end(.closedByUser)
        end(.closedByUser)   // reported twice: still one close

        XCTAssertEqual(closed, ["first"])
        XCTAssertFalse(surfaces.isPresented(alert))

        surfaces.present(.panel(FormView()), id: alert) { closed.append("second") }
        surfaces.dismiss(alert)
        XCTAssertEqual(closed, ["first"])
    }

    func testABubbleThatWentAwayIsNoLongerPresentedButIsNotAClose() throws {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)
        var closed = false
        surfaces.present(.bubble("in 5 min"), id: alert) { closed = true }

        // Timed out, or another message took the bubble
        try XCTUnwrap(presenter.endings[alert])(.wentAway)
        surfaces.update(alert, to: .bubble("in 4 min"))

        XCTAssertFalse(surfaces.isPresented(alert))
        XCTAssertFalse(closed)
        XCTAssertEqual(presenter.log, ["show test.alert bubble in 5 min"], "nothing left to update")
    }

    func testACloseFromAnEarlierPresentationIsIgnored() throws {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)
        var closed: [String] = []
        surfaces.present(.bubble("old"), id: alert) { closed.append("old") }
        let staleEnd = try XCTUnwrap(presenter.endings[alert])
        surfaces.present(.bubble("new"), id: alert) { closed.append("new") }

        staleEnd(.closedByUser)

        XCTAssertEqual(closed, [])
        XCTAssertTrue(surfaces.isPresented(alert))
    }
}

/// Stands in for a panel's content; Core never looks inside
private struct FormView: PlatformView {}
