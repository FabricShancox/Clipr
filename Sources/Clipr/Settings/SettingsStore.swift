import Cocoa
import Foundation
import ServiceManagement

final class SettingsStore {
    /// Internal (not private) so views can bind `@AppStorage` to the same store — see
    /// `copyBorderKey`.
    let defaults: UserDefaults

    private enum Key {
        static let captureHotkey = "captureHotkey"
        static let advancedModeHotkey = "advancedModeHotkey"
        static let saveFolder = "saveFolder"
        static let captureCursor = "captureCursor"
        static let advancedMode = "advancedMode"
        static let exportFormat = "exportFormat"
        static let exportIncludeZoom = "exportIncludeZoom"
        static let exportGIFFrameSeconds = "exportGIFFrameSeconds"
        /// Set once the ⌘⇧3 -> ⌃⇧⌘S Advanced Mode default migration has run, so a user who later
        /// picks ⌘⇧3 on purpose keeps it.
        static let advancedModeHotkeyMigrated = "advancedModeHotkeyMigratedFromCmdShift3"
    }

    /// The copy-style keys, each its own `Bool`. Preferences and every open editor bind
    /// `@AppStorage` straight to these, so a change in one shows in the others at once, and each
    /// toggle writes only its own key. Each used to keep a stale `CopyStyle` copy and write the
    /// whole struct back, so toggling Border in the editor silently undid a Shadow change made in
    /// Preferences (and vice versa).
    static let copyBorderKey = "copyBorder"
    static let copyShadowKey = "copyShadow"

    /// Read directly by `UpdateChecker`, which has no `SettingsStore` of its own.
    static let checkForUpdatesAutomaticallyKey = "checkForUpdatesAutomatically"

    /// Shared with `ReviewView`'s `@AppStorage`, which reads and writes the same key directly.
    static let reviewLayoutKey = "reviewLayout"

    private let loginItem: LoginItem

    init(defaults: UserDefaults = .standard, loginItem: LoginItem = MainAppLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        migrateAdvancedModeHotkey()
    }

    /// The old Advanced Mode default, ⌘⇧3, is macOS's "save picture of screen" shortcut, which
    /// usually wins — so the hotkey silently didn't work, or dropped a screenshot on every toggle.
    /// Anyone still on it moves to the new default, once.
    private func migrateAdvancedModeHotkey() {
        guard !defaults.bool(forKey: Key.advancedModeHotkeyMigrated) else { return }
        if let stored: HotkeyBinding = decoded(Key.advancedModeHotkey), stored == .legacyDefaultAdvancedMode {
            encode(HotkeyBinding.defaultAdvancedMode, forKey: Key.advancedModeHotkey)
        }
        defaults.set(true, forKey: Key.advancedModeHotkeyMigrated)
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

    /// Read from the system, not from a stored preference: registration can fail (an unsigned or
    /// moved app) or be switched off in System Settings, and a stored flag then showed On for a
    /// login item that didn't exist.
    var launchAtLogin: Bool { loginItem.isEnabled }

    /// Registers or unregisters the login item. Throws when the system refuses, so the caller can
    /// say so; `launchAtLogin` always reports what actually took effect.
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try loginItem.register() } else { try loginItem.unregister() }
    }

    /// Whether Clipr asks GitHub for a newer release at launch (at most once a day). On by default.
    var checkForUpdatesAutomatically: Bool {
        get { defaults.object(forKey: Self.checkForUpdatesAutomaticallyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.checkForUpdatesAutomaticallyKey) }
    }

    /// Whether the mouse cursor should be included in captures. Off by default — most users
    /// taking a screenshot want a clean shot of the content, not their pointer frozen mid-frame.
    var captureCursor: Bool {
        get { defaults.bool(forKey: Key.captureCursor) }
        set { defaults.set(newValue, forKey: Key.captureCursor) }
    }

    /// What Copy adds around the image — see `CopyStyle`. Both off by default. Read-only: each
    /// part is set on its own (`copyBorder`, `copyShadow`), never as a whole struct.
    var copyStyle: CopyStyle {
        CopyStyle(border: copyBorder, shadow: copyShadow)
    }

    var copyBorder: Bool {
        get { defaults.bool(forKey: Self.copyBorderKey) }
        set { defaults.set(newValue, forKey: Self.copyBorderKey) }
    }

    var copyShadow: Bool {
        get { defaults.bool(forKey: Self.copyShadowKey) }
        set { defaults.set(newValue, forKey: Self.copyShadowKey) }
    }

    /// All Advanced Mode options — see `AdvancedModeSettings`.
    var advancedMode: AdvancedModeSettings {
        get { decoded(Key.advancedMode) ?? .default }
        set { encode(newValue, forKey: Key.advancedMode) }
    }

    /// How the Review window lays out steps. Unknown stored values (a newer build's layout) fall
    /// back to the list rather than failing.
    var reviewLayout: ReviewLayout {
        get { defaults.string(forKey: Self.reviewLayoutKey).flatMap(ReviewLayout.init(rawValue:)) ?? .list }
        set { defaults.set(newValue.rawValue, forKey: Self.reviewLayoutKey) }
    }

    /// The export sheet's starting options: the last format, close-up choice and GIF frame time,
    /// with `title` (per session, so never remembered). An unknown format (a newer build's) reads
    /// as PDF; a frame time outside 1–5 s is clamped.
    func exportOptions(title: String) -> ExportOptions {
        let format = defaults.string(forKey: Key.exportFormat).flatMap(GuideFormat.init(rawValue:)) ?? .pdf
        let seconds = defaults.object(forKey: Key.exportGIFFrameSeconds) as? Double ?? 2
        return ExportOptions(format: format, title: title, includeZoom: defaults.bool(forKey: Key.exportIncludeZoom),
                             gifFrameSeconds: GIFGuideExporter.clampedFrameSeconds(seconds))
    }

    func rememberExportOptions(_ options: ExportOptions) {
        defaults.set(options.format.rawValue, forKey: Key.exportFormat)
        defaults.set(options.includeZoom, forKey: Key.exportIncludeZoom)
        defaults.set(options.gifFrameSeconds, forKey: Key.exportGIFFrameSeconds)
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

/// The app's login item — a seam so tests never register the test runner to open at login.
protocol LoginItem {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct MainAppLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
