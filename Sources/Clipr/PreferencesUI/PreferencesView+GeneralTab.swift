import SwiftUI

/// Preferences › General: shortcuts, save folder, capture, copy and startup options.
extension PreferencesView {
    var generalTab: some View {
        Form {
            shortcutsSection
            savingSection
            capturingSection
            copyingSection
            startupSection
        }
        .formStyle(.grouped)
    }

    private var shortcutsSection: some View {
        Section {
            LabeledContent("Capture") {
                HotkeyRecorderView(binding: Binding(
                    get: { captureHotkey },
                    set: { captureHotkey = $0; settings.captureHotkey = $0; onHotkeysChanged() }
                ), otherBindings: otherHotkeys(except: .capture), onRecordingChanged: onHotkeyRecording)
            }
            LabeledContent("Start / stop Advanced Mode") {
                HotkeyRecorderView(binding: Binding(
                    get: { advancedModeHotkey },
                    set: { advancedModeHotkey = $0; settings.advancedModeHotkey = $0; onHotkeysChanged() }
                ), otherBindings: otherHotkeys(except: .advancedMode), onRecordingChanged: onHotkeyRecording)
            }
        } header: {
            sectionHeader("Shortcuts")
        }
    }

    private var savingSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saveFolder]) }
                    Button("Choose…") { chooseFolder() }
                }
            } label: {
                Text("Save captures to")
                Text(saveFolder.path)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(saveFolder.path)
            }
        } header: {
            sectionHeader("Saving")
        }
    }

    private var capturingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { captureCursor },
                set: { captureCursor = $0; settings.captureCursor = $0; onCaptureCursorChanged() }
            )) {
                Text("Include the mouse pointer")
                Text("Shows the pointer in screenshots and Advanced Mode steps.")
            }
        } header: {
            sectionHeader("Capturing")
        }
    }

    private var copyingSection: some View {
        Section {
            Toggle(isOn: $copyBorder) {
                Text("Add a border")
                Text("A thin outline around copied images.")
            }
            Toggle(isOn: $copyShadow) {
                Text("Add a drop shadow")
                Text("Makes copied images stand out when pasted into documents.")
            }
        } header: {
            sectionHeader("Copying")
        }
    }

    private var startupSection: some View {
        Section {
            Toggle("Open Clipr at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            Toggle(isOn: $checkForUpdates) {
                Text("Check for updates automatically")
                Text("Asks GitHub for a newer release at most once a day.")
            }
        } header: {
            sectionHeader("Startup")
        }
    }
}
