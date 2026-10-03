import SwiftUI

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

    @State private var captureHotkey: HotkeyBinding
    @State private var advancedModeHotkey: HotkeyBinding
    @State private var saveFolder: URL
    @State private var launchAtLogin: Bool
    @State private var captureCursor: Bool
    @State private var copyStyle: CopyStyle

    init(
        settings: SettingsStore,
        onHotkeysChanged: @escaping () -> Void,
        onSaveFolderChanged: @escaping () -> Void,
        onCaptureCursorChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.onHotkeysChanged = onHotkeysChanged
        self.onSaveFolderChanged = onSaveFolderChanged
        self.onCaptureCursorChanged = onCaptureCursorChanged
        _captureHotkey = State(initialValue: settings.captureHotkey)
        _advancedModeHotkey = State(initialValue: settings.advancedModeHotkey)
        _saveFolder = State(initialValue: settings.saveFolder)
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
        _captureCursor = State(initialValue: settings.captureCursor)
        _copyStyle = State(initialValue: settings.copyStyle)
    }

    var body: some View {
        Form {
            HotkeyRecorderView(binding: Binding(
                get: { captureHotkey },
                set: { captureHotkey = $0; settings.captureHotkey = $0; onHotkeysChanged() }
            ))
            .labeled("Capture Hotkey")

            HotkeyRecorderView(binding: Binding(
                get: { advancedModeHotkey },
                set: { advancedModeHotkey = $0; settings.advancedModeHotkey = $0; onHotkeysChanged() }
            ))
            .labeled("Advanced Mode Hotkey")

            HStack {
                Text("Save Folder:")
                Text(saveFolder.path).lineLimit(1).truncationMode(.head)
                Button("Choose…") { chooseFolder() }
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; settings.launchAtLogin = $0 }
            ))

            Toggle("Capture Mouse Cursor", isOn: Binding(
                get: { captureCursor },
                set: { captureCursor = $0; settings.captureCursor = $0; onCaptureCursorChanged() }
            ))

            Toggle("Add Border When Copying", isOn: Binding(
                get: { copyStyle.border },
                set: { copyStyle.border = $0; settings.copyStyle = copyStyle }
            ))

            Toggle("Add Drop Shadow When Copying", isOn: Binding(
                get: { copyStyle.shadow },
                set: { copyStyle.shadow = $0; settings.copyStyle = copyStyle }
            ))

            Section {
                LabeledContent("Version", value: Self.appVersion)
            } header: {
                Text("About")
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url
            settings.saveFolder = url
            // Persisting alone doesn't move where captures land - notify the owner so the live
            // StorageManager is re-pointed too (see `onSaveFolderChanged`).
            onSaveFolderChanged()
        }
    }
}

private extension View {
    func labeled(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            self
        }
    }
}
