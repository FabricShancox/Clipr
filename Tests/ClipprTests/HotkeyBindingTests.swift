import XCTest
@testable import Clipr

final class HotkeyBindingTests: XCTestCase {
    func testRoundTripCodable() throws {
        let binding = HotkeyBinding(keyCode: 19, modifiers: HotkeyBinding.Modifier.command.rawValue | HotkeyBinding.Modifier.shift.rawValue)
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(binding, decoded)
    }

    func testDisplayString() {
        let binding = HotkeyBinding(keyCode: 19, modifiers: HotkeyBinding.Modifier.command.rawValue | HotkeyBinding.Modifier.shift.rawValue)
        XCTAssertEqual(binding.displayString, "⌘⇧2")
    }

    func testDisplayStringNamesLetterAndSpecialKeys() {
        let command = HotkeyBinding.Modifier.command.rawValue
        // 12 is the Q key on ANSI/ISO QWERTY; the test assumes a QWERTY-family layout.
        XCTAssertEqual(HotkeyBinding(keyCode: 12, modifiers: command).displayString, "⌘Q")
        XCTAssertEqual(HotkeyBinding(keyCode: 96, modifiers: command).displayString, "⌘F5")
        XCTAssertEqual(HotkeyBinding(keyCode: 49, modifiers: command).displayString, "⌘Space")
    }

    func testDefaultsDiffer() {
        XCTAssertNotEqual(HotkeyBinding.defaultCapture, HotkeyBinding.defaultAdvancedMode)
    }
}
