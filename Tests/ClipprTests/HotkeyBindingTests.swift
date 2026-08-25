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

    func testDefaultsDiffer() {
        XCTAssertNotEqual(HotkeyBinding.defaultCapture, HotkeyBinding.defaultAdvancedMode)
    }
}
