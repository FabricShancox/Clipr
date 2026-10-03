import XCTest
@testable import Clipr

final class AdvancedModeSettingsTests: XCTestCase {
    func testDefaultsAreTunedForGuides() {
        let s = AdvancedModeSettings.default
        XCTAssertTrue(s.clickMarker)
        XCTAssertEqual(s.markerStyle, .ring)
        XCTAssertTrue(s.autoCaptions)
        XCTAssertFalse(s.cursorTrail)
        XCTAssertFalse(s.zoomOnClick)
        XCTAssertFalse(s.typingSteps)
        XCTAssertEqual(s.scope, .window)
        XCTAssertEqual(s.captureDelay, 0.3, accuracy: 0.0001)
        XCTAssertNil(s.stepHotkey)
    }

    func testEffectiveDelayIsClampedBetweenDebounceFloorAndMax() {
        var s = AdvancedModeSettings.default
        s.captureDelay = 0
        XCTAssertEqual(s.effectiveDelay, 0.2, accuracy: 0.0001)
        s.captureDelay = 5
        XCTAssertEqual(s.effectiveDelay, 2, accuracy: 0.0001)
        s.captureDelay = 0.7
        XCTAssertEqual(s.effectiveDelay, 0.7, accuracy: 0.0001)
    }

    func testDecodingMissingKeysFallsBackToDefaults() throws {
        let json = #"{"cursorTrail": true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AdvancedModeSettings.self, from: json)
        XCTAssertTrue(s.cursorTrail)
        XCTAssertTrue(s.clickMarker)
        XCTAssertEqual(s.scope, .window)
        XCTAssertEqual(s.captureDelay, 0.3, accuracy: 0.0001)
    }

    func testSettingsStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.advancedMode, .default)
        var custom = AdvancedModeSettings.default
        custom.scope = .fixedArea
        custom.markerStyle = .dot
        custom.stepHotkey = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.option.rawValue)
        store.advancedMode = custom
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedMode, custom)
    }
}
