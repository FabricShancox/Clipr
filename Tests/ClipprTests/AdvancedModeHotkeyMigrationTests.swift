import XCTest
@testable import Clipr

/// The old Advanced Mode default, ⌘⇧3, is macOS's own "save screenshot" shortcut. The new
/// default is ⌃⇧⌘S, and a stored ⌘⇧3 is moved to it once.
final class AdvancedModeHotkeyMigrationTests: XCTestCase {
    var defaults: UserDefaults!
    private let mods = HotkeyBinding.Modifier.self

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
    }

    private func store(_ binding: HotkeyBinding) {
        defaults.set(try! JSONEncoder().encode(binding), forKey: "advancedModeHotkey")
    }

    func testNewDefaultIsControlShiftCommandS() {
        XCTAssertEqual(HotkeyBinding.defaultAdvancedMode,
                       HotkeyBinding(keyCode: 1, modifiers: mods.control.rawValue | mods.shift.rawValue | mods.command.rawValue))
        XCTAssertNotEqual(HotkeyBinding.defaultAdvancedMode, HotkeyBinding.legacyDefaultAdvancedMode)
        XCTAssertEqual(HotkeyBinding.legacyDefaultAdvancedMode,
                       HotkeyBinding(keyCode: 20, modifiers: mods.command.rawValue | mods.shift.rawValue))
    }

    func testFreshInstallGetsNewDefault() {
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedModeHotkey, .defaultAdvancedMode)
    }

    func testStoredOldDefaultIsMigrated() {
        store(.legacyDefaultAdvancedMode)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.advancedModeHotkey, .defaultAdvancedMode)
        // Persisted, not just masked in memory.
        let data = try! XCTUnwrap(defaults.data(forKey: "advancedModeHotkey"))
        XCTAssertEqual(try JSONDecoder().decode(HotkeyBinding.self, from: data), .defaultAdvancedMode)
    }

    func testCustomBindingIsLeftAlone() {
        let custom = HotkeyBinding(keyCode: 0, modifiers: mods.control.rawValue | mods.option.rawValue)
        store(custom)
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedModeHotkey, custom)
    }

    func testMigrationRunsOnlyOnce() {
        store(.legacyDefaultAdvancedMode)
        _ = SettingsStore(defaults: defaults)
        // The user deliberately picks ⌘⇧3 again afterwards; a later launch must respect that.
        let settings = SettingsStore(defaults: defaults)
        settings.advancedModeHotkey = .legacyDefaultAdvancedMode
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedModeHotkey, .legacyDefaultAdvancedMode)
    }

    func testFreshInstallRecordsMigrationSoALaterChoiceOfOldComboSticks() {
        let settings = SettingsStore(defaults: defaults)
        settings.advancedModeHotkey = .legacyDefaultAdvancedMode
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedModeHotkey, .legacyDefaultAdvancedMode)
    }
}
