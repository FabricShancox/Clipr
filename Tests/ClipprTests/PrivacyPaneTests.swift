import XCTest
@testable import Clipr

final class PrivacyPaneTests: XCTestCase {
    func testScreenRecordingURLTargetsTheScreenCapturePane() {
        XCTAssertEqual(PrivacyPane.screenRecording.settingsURLString, "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func testAccessibilityURLTargetsTheAccessibilityPane() {
        XCTAssertEqual(PrivacyPane.accessibility.settingsURLString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func testEachPaneProducesAValidURL() {
        XCTAssertNotNil(URL(string: PrivacyPane.screenRecording.settingsURLString))
        XCTAssertNotNil(URL(string: PrivacyPane.accessibility.settingsURLString))
    }
}
