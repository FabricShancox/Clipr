import Foundation

extension HotkeyBinding {
    /// Same key and exactly the same ⌃⌥⇧⌘ modifiers. Carbon modifier bits mapped to `KeyModifiers`.
    func matches(_ key: KeyInput) -> Bool {
        guard UInt32(key.keyCode) == keyCode else { return false }
        var expected: KeyModifiers = []
        if modifiers & Modifier.command.rawValue != 0 { expected.insert(.command) }
        if modifiers & Modifier.shift.rawValue != 0 { expected.insert(.shift) }
        if modifiers & Modifier.option.rawValue != 0 { expected.insert(.option) }
        if modifiers & Modifier.control.rawValue != 0 { expected.insert(.control) }
        return key.modifiers == expected
    }
}
