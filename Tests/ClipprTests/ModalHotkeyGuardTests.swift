import XCTest
import Cocoa
@testable import Clipr

final class ModalHotkeyGuardTests: XCTestCase {
    func testAllowedWhenNothingModalIsUp() {
        XCTAssertFalse(ModalHotkeyGuard.shouldIgnore(hasModalWindow: false, keyWindowHasSheet: false, keyWindowIsSheet: false))
    }

    func testIgnoredWhileAModalAlertOrPanelRuns() {
        XCTAssertTrue(ModalHotkeyGuard.shouldIgnore(hasModalWindow: true, keyWindowHasSheet: false, keyWindowIsSheet: false))
    }

    func testIgnoredWhileTheKeyWindowHasASheet() {
        XCTAssertTrue(ModalHotkeyGuard.shouldIgnore(hasModalWindow: false, keyWindowHasSheet: true, keyWindowIsSheet: false))
        XCTAssertTrue(ModalHotkeyGuard.shouldIgnore(hasModalWindow: false, keyWindowHasSheet: false, keyWindowIsSheet: true))
    }

    func testLiveCheckIsQuietWithNoModalSession() {
        _ = NSApplication.shared
        XCTAssertFalse(ModalHotkeyGuard.shouldIgnoreNow())
    }
}
