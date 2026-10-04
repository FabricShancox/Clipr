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
    /// Recording a shortcut started (true) or ended (false) — see
    /// `HotkeyRecorderView.onRecordingChanged`.
    let onHotkeyRecording: (Bool) -> Void

    @State private var captureHotkey: HotkeyBinding
    @State private var advancedModeHotkey: HotkeyBinding
    @State private var saveFolder: URL
    @State private var launchAtLogin: Bool
    @State private var captureCursor: Bool
    /// Bound straight to the settings keys (see `SettingsStore.copyBorderKey`), so an open editor's
    /// copy-style menu and these toggles always agree.
    @AppStorage private var copyBorder: Bool
    @AppStorage private var copyShadow: Bool
    @AppStorage private var checkForUpdates: Bool
    @State private var advanced: AdvancedModeSettings
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()

    init(
        settings: SettingsStore,
        onHotkeysChanged: @escaping () -> Void,
        onSaveFolderChanged: @escaping () -> Void,
        onCaptureCursorChanged: @escaping () -> Void,
        onHotkeyRecording: @escaping (Bool) -> Void = { _ in }
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

    // MARK: General

    private var generalTab: some View {
        Form {
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
        .formStyle(.grouped)
    }

    // MARK: Advanced Mode

    private var advancedModeTab: some View {
        Form {
            Section {
                Toggle(isOn: advancedBinding(\.clickMarker)) {
                    Text("Mark each click")
                    Text("Draws an editable marker where you clicked.")
                }
                // Drawn, not a native `.segmented` Picker — see `DrawnSegmentedPicker`.
                DrawnSegmentedPicker(
                    label: "Marker style",
                    selection: advancedBinding(\.markerStyle),
                    options: [(.ring, "Ring"), (.dot, "Dot")]
                )
                .disabled(!advanced.clickMarker)
                Toggle(isOn: advancedBinding(\.cursorTrail)) {
                    Text("Show pointer trail")
                    Text("A short curve showing where the pointer came from before each click.")
                }
                Toggle(isOn: advancedBinding(\.zoomOnClick)) {
                    Text("Save a close-up of each click")
                    Text("Adds a zoomed-in image next to each step, centred on the click.")
                }
            } header: {
                sectionHeader("On each step")
            }

            Section {
                Toggle(isOn: advancedBinding(\.autoCaptions)) {
                    Text("Write captions automatically")
                    Text("For example \u{201C}Click Save in Safari\u{201D}.")
                }
                Toggle(isOn: advancedBinding(\.typingSteps)) {
                    Text("Record typing as steps")
                    Text("Not recorded in password fields, terminals, or apps that don\u{2019}t report their fields to Accessibility.")
                }
                if advanced.typingSteps && !inputMonitoringGranted {
                    LabeledContent {
                        Button("Open System Settings…") {
                            inputMonitoringGranted = CGRequestListenEventAccess()
                        }
                    } label: {
                        Label("Needs Input Monitoring permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                sectionHeader("Captions")
            }

            Section {
                Picker(selection: advancedBinding(\.scope)) {
                    Text("Clicked window").tag(AdvancedModeSettings.Scope.window)
                    Text("Whole screen").tag(AdvancedModeSettings.Scope.screen)
                    Text("Fixed area").tag(AdvancedModeSettings.Scope.fixedArea)
                } label: {
                    Text("Capture")
                    Text(scopeDescription)
                }
                LabeledContent {
                    HStack {
                        Slider(value: advancedBinding(\.captureDelay), in: 0.2...2, step: 0.1)
                            .frame(width: 180)
                        // Locale-aware decimal separator (0,5 s in many locales).
                        Text("\(advanced.captureDelay.formatted(.number.precision(.fractionLength(1)))) s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                } label: {
                    Text("Wait after click")
                    Text("Lets menus and pop-ups finish opening before the screenshot.")
                }
                LabeledContent {
                    if let hotkey = advanced.stepHotkey {
                        HStack(spacing: 8) {
                            HotkeyRecorderView(binding: Binding(
                                get: { hotkey },
                                set: { advanced.stepHotkey = $0; settings.advancedMode = advanced }
                            ), otherBindings: otherHotkeys(except: .step), onRecordingChanged: onHotkeyRecording)
                            Button("Clear") { advanced.stepHotkey = nil; settings.advancedMode = advanced }
                        }
                    } else {
                        Button("Add Shortcut") {
                            advanced.stepHotkey = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.control.rawValue | HotkeyBinding.Modifier.option.rawValue)
                            settings.advancedMode = advanced
                        }
                    }
                } label: {
                    Text("Take a step without clicking")
                    Text("Shortcut that works only while recording.")
                }
            } header: {
                sectionHeader("Capture")
            } footer: {
                Text("Changes apply the next time you start Advanced Mode.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Grouped forms leave a tall gap above every section title; pulling the title up tightens
    /// the page without changing the spacing inside each group.
    private func sectionHeader(_ title: String) -> some View {
        Text(title).padding(.top, -14)
    }

    private var scopeDescription: String {
        switch advanced.scope {
        case .window: return "Just the window you clicked in."
        case .screen: return "The whole display you clicked on, including menus."
        case .fixedArea: return "An area you choose when recording starts."
        }
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
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try settings.setLaunchAtLogin(enabled)
        } catch {
            NSLog("Clipr: failed to update login item registration: \(error)")
            Alerts.run(enabled ? "Couldn't add Clipr to your login items" : "Couldn't remove Clipr from your login items",
                       "\(error.localizedDescription)\n\nYou can change this in System Settings › General › Login Items.")
        }
        launchAtLogin = settings.launchAtLogin
    }

    private enum HotkeySlot { case capture, advancedMode, step }

    /// Clipr's shortcuts other than `slot`, with the names the recorder shows on a clash.
    private func otherHotkeys(except slot: HotkeySlot) -> [(binding: HotkeyBinding, name: String)] {
        var others: [(binding: HotkeyBinding, name: String)] = []
        if slot != .capture { others.append((captureHotkey, "Capture")) }
        if slot != .advancedMode { others.append((advancedModeHotkey, "Advanced Mode")) }
        if slot != .step, let step = advanced.stepHotkey { others.append((step, "taking a step")) }
        return others
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

    private func advancedBinding<T>(_ keyPath: WritableKeyPath<AdvancedModeSettings, T>) -> Binding<T> {
        Binding(
            get: { advanced[keyPath: keyPath] },
            set: { advanced[keyPath: keyPath] = $0; settings.advancedMode = advanced }
        )
    }
}
