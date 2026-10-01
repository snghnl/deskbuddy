import SwiftUI
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
        surfaces.present(.panel(AnyView(Text("form"))), id: alert) { closed.append("first") }
        let close = try XCTUnwrap(presenter.closers[alert])

        close()
        close()   // reported twice: still one close

        XCTAssertEqual(closed, ["first"])
        XCTAssertFalse(surfaces.isPresented(alert))

        surfaces.present(.panel(AnyView(Text("form"))), id: alert) { closed.append("second") }
        surfaces.dismiss(alert)
        XCTAssertEqual(closed, ["first"])
    }

    func testACloseFromAnEarlierPresentationIsIgnored() throws {
        let presenter = RecordingPresenter()
        let surfaces = SurfaceManager(presenter: presenter)
        var closed: [String] = []
        surfaces.present(.bubble("old"), id: alert) { closed.append("old") }
        let staleClose = try XCTUnwrap(presenter.closers[alert])
        surfaces.present(.bubble("new"), id: alert) { closed.append("new") }

        staleClose()

        XCTAssertEqual(closed, [])
        XCTAssertTrue(surfaces.isPresented(alert))
    }
}
