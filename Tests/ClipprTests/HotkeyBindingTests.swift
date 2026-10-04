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

    func testMatchesMapsCarbonModifiersToKeyModifiers() {
        let key = { (code: UInt16, mods: KeyModifiers) in
            KeyInput(characters: "", baseCharacters: "", keyCode: code, modifiers: mods, isSecure: false)
        }
        XCTAssertTrue(HotkeyBinding.defaultCapture.matches(key(19, [.command, .shift])))
        XCTAssertFalse(HotkeyBinding.defaultCapture.matches(key(19, [.command])))
        XCTAssertFalse(HotkeyBinding.defaultCapture.matches(key(19, [.command, .shift, .option])))
        XCTAssertFalse(HotkeyBinding.defaultCapture.matches(key(20, [.command, .shift])))
        let all = HotkeyBinding.Modifier.self
        let ctrlOpt = HotkeyBinding(keyCode: 1, modifiers: all.control.rawValue | all.option.rawValue)
        XCTAssertTrue(ctrlOpt.matches(key(1, [.control, .option])))
        XCTAssertFalse(ctrlOpt.matches(key(1, [.control, .shift])))
    }

    func testDefaultsDiffer() {
        XCTAssertNotEqual(HotkeyBinding.defaultCapture, HotkeyBinding.defaultAdvancedMode)
    }
}
