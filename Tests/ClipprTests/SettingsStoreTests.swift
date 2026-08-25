import XCTest
@testable import Clipr

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
        store = SettingsStore(defaults: defaults)
    }

    func testDefaultsWhenUnset() {
        XCTAssertEqual(store.captureHotkey, HotkeyBinding.defaultCapture)
        XCTAssertEqual(store.advancedModeHotkey, HotkeyBinding.defaultAdvancedMode)
        XCTAssertEqual(store.saveFolder, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots"))
        XCTAssertFalse(store.launchAtLogin)
    }

    func testCaptureHotkeyPersists() {
        let custom = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.option.rawValue)
        store.captureHotkey = custom
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.captureHotkey, custom)
    }

    func testSaveFolderPersists() {
        let custom = URL(fileURLWithPath: "/tmp/clipr-test-folder")
        store.saveFolder = custom
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.saveFolder, custom)
    }

    func testLaunchAtLoginPersists() {
        store.launchAtLogin = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.launchAtLogin)
    }
}
