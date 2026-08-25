import Foundation

struct HotkeyBinding: Codable, Equatable {
    enum Modifier: UInt32 {
        case command = 1
        case shift = 2
        case option = 4
        case control = 8
    }

    let keyCode: UInt32
    let modifiers: UInt32

    // macOS virtual keycodes for digits 0-9, used for defaults and display.
    private static let keyCodeToDigit: [UInt32: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9"
    ]

    var displayString: String {
        var s = ""
        if modifiers & Modifier.command.rawValue != 0 { s += "⌘" }
        if modifiers & Modifier.shift.rawValue != 0 { s += "⇧" }
        if modifiers & Modifier.option.rawValue != 0 { s += "⌥" }
        if modifiers & Modifier.control.rawValue != 0 { s += "⌃" }
        s += HotkeyBinding.keyCodeToDigit[keyCode] ?? "?"
        return s
    }

    static let defaultCapture = HotkeyBinding(keyCode: 19, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧2
    static let defaultAdvancedMode = HotkeyBinding(keyCode: 20, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧3
}
