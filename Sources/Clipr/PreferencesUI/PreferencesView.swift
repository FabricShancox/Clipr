import SwiftUI

struct PreferencesView: View {
    let settings: SettingsStore
    let onHotkeysChanged: () -> Void

    @State private var captureHotkey: HotkeyBinding
    @State private var advancedModeHotkey: HotkeyBinding
    @State private var saveFolder: URL
    @State private var launchAtLogin: Bool

    init(settings: SettingsStore, onHotkeysChanged: @escaping () -> Void) {
        self.settings = settings
        self.onHotkeysChanged = onHotkeysChanged
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
