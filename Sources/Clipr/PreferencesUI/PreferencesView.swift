import SwiftUI

/// The Preferences window's content. Each tab lives in its own `PreferencesView+…Tab.swift`
/// extension, so the state below is internal rather than private purely so those files can see it.
struct PreferencesView: View {
    let settings: SettingsStore
    let onHotkeysChanged: () -> Void
    /// Mirrors `onHotkeysChanged`: persisting a new save folder into `SettingsStore` isn't enough on
    /// its own, because the long-lived `StorageManager` every capture path uses was built from the
    /// old folder at launch. This callback lets the owner re-point it, so the change applies to the
    /// very next capture instead of only after a relaunch.
    let onSaveFolderChanged: () -> Void
    /// Mirrors `onSaveFolderChanged`: `CaptureManager`/`ClickCaptureManager` each hold their own
    /// `captureCursor` copy (set once at launch) rather than reading `SettingsStore` live, so
    /// this callback re-syncs both the moment the toggle changes.
    let onCaptureCursorChanged: () -> Void
    /// A shortcut recorder (identified by its id) started (true) or ended (false) recording — see
    /// `HotkeyRecorderView.onRecordingChanged`.
    let onHotkeyRecording: (_ recorder: UUID, _ recording: Bool) -> Void

    @State var captureHotkey: HotkeyBinding
    @State var advancedModeHotkey: HotkeyBinding
    @State var saveFolder: URL
    @State var launchAtLogin: Bool
    @State var captureCursor: Bool
    /// Bound straight to the settings keys (see `SettingsStore.copyBorderKey`), so an open editor's
    /// copy-style menu and these toggles always agree.
    @AppStorage var copyBorder: Bool
    @AppStorage var copyShadow: Bool
    @AppStorage var checkForUpdates: Bool
    @State var advanced: AdvancedModeSettings
    @State var inputMonitoringGranted = CGPreflightListenEventAccess()

    init(
        settings: SettingsStore,
        onHotkeysChanged: @escaping () -> Void,
        onSaveFolderChanged: @escaping () -> Void,
        onCaptureCursorChanged: @escaping () -> Void,
        onHotkeyRecording: @escaping (_ recorder: UUID, _ recording: Bool) -> Void = { _, _ in }
    ) {
        self.settings = settings
        self.onHotkeyRecording = onHotkeyRecording
        self.onHotkeysChanged = onHotkeysChanged
        self.onSaveFolderChanged = onSaveFolderChanged
        self.onCaptureCursorChanged = onCaptureCursorChanged
        _captureHotkey = State(initialValue: settings.captureHotkey)
        _advancedModeHotkey = State(initialValue: settings.advancedModeHotkey)
        _saveFolder = State(initialValue: settings.saveFolder)
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
        _captureCursor = State(initialValue: settings.captureCursor)
        _copyBorder = AppStorage(wrappedValue: false, SettingsStore.copyBorderKey, store: settings.defaults)
        _copyShadow = AppStorage(wrappedValue: false, SettingsStore.copyShadowKey, store: settings.defaults)
        _checkForUpdates = AppStorage(wrappedValue: true, SettingsStore.checkForUpdatesAutomaticallyKey, store: settings.defaults)
        _advanced = State(initialValue: settings.advancedMode)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            advancedModeTab
                .tabItem { Label("Advanced Mode", systemImage: "cursorarrow.click.2") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 600)
        // Input Monitoring is granted in System Settings, outside this window, so re-check whenever
        // the user comes back — otherwise "Grant…" lingers after it's no longer needed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputMonitoringGranted = CGPreflightListenEventAccess()
        }
    }

    /// Grouped forms leave a tall gap above every section title; pulling the title up tightens
    /// the page without changing the spacing inside each group.
    func sectionHeader(_ title: String) -> some View {
        Text(title).padding(.top, -14)
    }

    // MARK: About

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("Version", value: Self.appVersion)
            }
        }
        .formStyle(.grouped)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    /// A refused registration is reported and the toggle reverts to what the system actually has,
    /// rather than showing On for a login item that doesn't exist.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try settings.setLaunchAtLogin(enabled)
        } catch {
            NSLog("Clipr: failed to update login item registration: \(error)")
            Alerts.run(enabled ? "Couldn't add Clipr to your login items" : "Couldn't remove Clipr from your login items",
                       "\(error.localizedDescription)\n\nYou can change this in System Settings › General › Login Items.")
        }
        launchAtLogin = settings.launchAtLogin
    }

    enum HotkeySlot { case capture, advancedMode, step }

    /// Clipr's shortcuts other than `slot`, with the names the recorder shows on a clash.
    func otherHotkeys(except slot: HotkeySlot) -> [(binding: HotkeyBinding, name: String)] {
        var others: [(binding: HotkeyBinding, name: String)] = []
        if slot != .capture { others.append((captureHotkey, "Capture")) }
        if slot != .advancedMode { others.append((advancedModeHotkey, "Advanced Mode")) }
        if slot != .step, let step = advanced.stepHotkey { others.append((step, "taking a step")) }
        return others
    }

    func chooseFolder() {
        let panel = Panels.chooseFolder(startingAt: saveFolder)
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url
            settings.saveFolder = url
            // Persisting alone doesn't move where captures land - notify the owner so the live
            // StorageManager is re-pointed too (see `onSaveFolderChanged`).
            onSaveFolderChanged()
        }
    }

    func advancedBinding<T>(_ keyPath: WritableKeyPath<AdvancedModeSettings, T>) -> Binding<T> {
        Binding(
            get: { advanced[keyPath: keyPath] },
            set: { advanced[keyPath: keyPath] = $0; settings.advancedMode = advanced }
        )
    }
}
