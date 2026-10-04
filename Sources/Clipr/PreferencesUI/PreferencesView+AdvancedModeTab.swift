import SwiftUI

/// Preferences › Advanced Mode: what each recorded step includes, captions, and capture scope.
extension PreferencesView {
    var advancedModeTab: some View {
        Form {
            onEachStepSection
            captionsSection
            captureSection
        }
        .formStyle(.grouped)
    }

    private var onEachStepSection: some View {
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
    }

    private var captionsSection: some View {
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
    }

    private var captureSection: some View {
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
            stepHotkeyRow
        } header: {
            sectionHeader("Capture")
        } footer: {
            Text("Changes apply the next time you start Advanced Mode.")
                .foregroundStyle(.secondary)
        }
    }

    private var stepHotkeyRow: some View {
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
    }

    private var scopeDescription: String {
        switch advanced.scope {
        case .window: return "Just the window you clicked in."
        case .screen: return "The whole display you clicked on, including menus."
        case .fixedArea: return "An area you choose when recording starts."
        }
    }
}
