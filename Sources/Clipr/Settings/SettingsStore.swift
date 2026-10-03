import Cocoa
import Foundation
import ServiceManagement

final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let captureHotkey = "captureHotkey"
        static let advancedModeHotkey = "advancedModeHotkey"
        static let saveFolder = "saveFolder"
        static let launchAtLogin = "launchAtLogin"
        static let captureCursor = "captureCursor"
        static let copyBorder = "copyBorder"
        static let copyShadow = "copyShadow"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var captureHotkey: HotkeyBinding {
        get { decoded(Key.captureHotkey) ?? .defaultCapture }
        set { encode(newValue, forKey: Key.captureHotkey) }
    }

    var advancedModeHotkey: HotkeyBinding {
        get { decoded(Key.advancedModeHotkey) ?? .defaultAdvancedMode }
        set { encode(newValue, forKey: Key.advancedModeHotkey) }
    }

    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: Key.saveFolder) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Clipr: failed to update login item registration: \(error)")
            }
        }
    }

    /// Whether the mouse cursor should be included in captures. Off by default — most users
    /// taking a screenshot want a clean shot of the content, not their pointer frozen mid-frame.
    var captureCursor: Bool {
        get { defaults.bool(forKey: Key.captureCursor) }
        set { defaults.set(newValue, forKey: Key.captureCursor) }
    }

    /// What Copy adds around the image — see `CopyStyle`. Both off by default.
    var copyStyle: CopyStyle {
        get { CopyStyle(border: defaults.bool(forKey: Key.copyBorder), shadow: defaults.bool(forKey: Key.copyShadow)) }
        set {
            defaults.set(newValue.border, forKey: Key.copyBorder)
            defaults.set(newValue.shadow, forKey: Key.copyShadow)
        }
    }

    private func decoded<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
