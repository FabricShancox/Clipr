import SwiftUI

struct PreferencesView: View {
    let settings: SettingsStore
    let onHotkeysChanged: () -> Void
    /// Mirrors `onHotkeysChanged`: persisting a new save folder into `SettingsStore` isn't enough on
    /// its own, because the long-lived `StorageManager` every capture path uses was built from the
    /// old folder at launch. This callback lets the owner re-point it, so the change applies to the
    /// very next capture instead of only after a relaunch.
    let onSaveFolderChanged: () -> Void

    @State private var captureHotkey: HotkeyBinding
    @State private var advancedModeHotkey: HotkeyBinding
    @State private var saveFolder: URL
    @State private var launchAtLogin: Bool

    init(
        settings: SettingsStore,
        onHotkeysChanged: @escaping () -> Void,
        onSaveFolderChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.onHotkeysChanged = onHotkeysChanged
        self.onSaveFolderChanged = onSaveFolderChanged
        _captureHotkey = State(initialValue: settings.captureHotkey)
        _advancedModeHotkey = State(initialValue: settings.advancedModeHotkey)
        _saveFolder = State(initialValue: settings.saveFolder)
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
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
        }
        .padding(20)
        .frame(width: 420)
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
