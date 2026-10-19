import XCTest
import ObjectiveC
@testable import FraloApp

final class UpdateControllerTests: XCTestCase {
    func testSparkleCanCallTheOptionalRelaunchDelegate() {
        let selector = NSSelectorFromString("updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")
        XCTAssertNotNil(class_getInstanceMethod(UpdateController.self, selector))
    }

    @MainActor
    func testExportFinishesBeforeInstallAndCallbackRunsOnlyOnce() async {
        let gate = UpdateInstallationGate()
        var installs = 0
        XCTAssertTrue(gate.postpone(whileBusy: true) { installs += 1 })
        XCTAssertTrue(gate.isWaiting)
        XCTAssertEqual(installs, 0)
        XCTAssertFalse(gate.resumeIfIdle(whileBusy: true))
        XCTAssertEqual(installs, 0, "A still-open completion sheet must also postpone restart")
        XCTAssertTrue(gate.resumeIfIdle(whileBusy: false))
        XCTAssertEqual(installs, 1)
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.resumeIfIdle(whileBusy: false))
        XCTAssertEqual(installs, 1)
    }

    @MainActor
    func testIdleAppLeavesInstallationToSparkle() async {
        let gate = UpdateInstallationGate()
        XCTAssertFalse(gate.postpone(whileBusy: false) { XCTFail("Sparkle owns immediate installation") })
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.resumeIfIdle(whileBusy: false))
    }

    @MainActor
    func testAbortedUpdateCannotInstallAfterExport() async {
        let gate = UpdateInstallationGate()
        XCTAssertTrue(gate.postpone(whileBusy: true) { XCTFail("Aborted update must not install") })
        gate.cancel()
        XCTAssertFalse(gate.resumeIfIdle(whileBusy: false))
        XCTAssertFalse(gate.isWaiting)
    }
}
