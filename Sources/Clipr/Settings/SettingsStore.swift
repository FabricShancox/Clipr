import Foundation

final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let captureHotkey = "captureHotkey"
        static let advancedModeHotkey = "advancedModeHotkey"
        static let saveFolder = "saveFolder"
        static let launchAtLogin = "launchAtLogin"
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
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
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
