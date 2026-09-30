import Carbon
import Foundation

struct HotkeyBinding: Codable, Equatable {
    enum Modifier: UInt32 {
        case command = 256  // Carbon cmdKey (bit 8)
        case shift = 512    // Carbon shiftKey (bit 9)
        case option = 2048  // Carbon optionKey (bit 11)
        case control = 4096 // Carbon controlKey (bit 12)
    }

    let keyCode: UInt32
    let modifiers: UInt32

    // Keys that don't type a printable character, so the keyboard layout can't name them.
    private static let specialKeyNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    /// The key's label, e.g. "Q" or "F5". Printable keys are named through the current keyboard
    /// layout rather than a fixed table, so the label matches what's printed on the user's keycap
    /// (a German layout's Z/Y swap, AZERTY, and so on).
    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        return layoutCharacter(for: keyCode)?.uppercased() ?? "?"
    }

    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    var displayString: String {
        var s = ""
        if modifiers & Modifier.command.rawValue != 0 { s += "⌘" }
        if modifiers & Modifier.shift.rawValue != 0 { s += "⇧" }
        if modifiers & Modifier.option.rawValue != 0 { s += "⌥" }
        if modifiers & Modifier.control.rawValue != 0 { s += "⌃" }
        s += HotkeyBinding.keyName(for: keyCode)
        return s
    }

    static let defaultCapture = HotkeyBinding(keyCode: 19, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧2
    static let defaultAdvancedMode = HotkeyBinding(keyCode: 20, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧3
}
