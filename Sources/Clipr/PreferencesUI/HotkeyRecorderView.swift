import SwiftUI
import Cocoa

struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    /// Shown after a key that can't be a global hotkey (see `HotkeyBinding.recordingOutcome`);
    /// recording stays on so the user can simply try again.
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(isRecording ? "Press a key…" : binding.displayString) {
                hint = nil
                isRecording = true
            }
            .background(KeyCatcherView(isRecording: $isRecording, binding: $binding, hint: $hint))
        }
    }
}

private struct KeyCatcherView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var binding: HotkeyBinding
    @Binding var hint: String?

    func makeNSView(context: Context) -> KeyCatcherNSView {
        let view = KeyCatcherNSView()
        view.onKeyDown = { keyCode, modifiers in
            switch HotkeyBinding.recordingOutcome(keyCode: keyCode, modifiers: modifiers) {
            case .accepted(let newBinding):
                hint = HotkeyBinding.conflictNotice(keyCode: newBinding.keyCode, modifiers: newBinding.modifiers)
                binding = newBinding
                isRecording = false
                return true
            case .cancelled:
                hint = nil
                isRecording = false
                return true
            case .rejected(let message):
                NSSound.beep()
                hint = message
                return false
            }
        }
        return view
    }

    /// Focus moves on the next main-loop turn, never inside this view update: changing the first
    /// responder here posts accessibility and focus notifications that re-enter SwiftUI's update
    /// of the surrounding (List-backed) grouped Form — the same freeze family as Review. It also
    /// only happens when recording starts, not on every update while it's on.
    func updateNSView(_ nsView: KeyCatcherNSView, context: Context) {
        let startedRecording = isRecording && !nsView.isRecording
        nsView.isRecording = isRecording
        guard startedRecording else { return }
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, nsView.isRecording, let window = nsView.window,
                  window.firstResponder !== nsView else { return }
            window.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCatcherNSView: NSView {
    var isRecording = false
    /// Returns whether recording finished (accepted or cancelled); `false` keeps listening.
    var onKeyDown: ((UInt32, UInt32) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= HotkeyBinding.Modifier.command.rawValue }
        if event.modifierFlags.contains(.shift) { modifiers |= HotkeyBinding.Modifier.shift.rawValue }
        if event.modifierFlags.contains(.option) { modifiers |= HotkeyBinding.Modifier.option.rawValue }
        if event.modifierFlags.contains(.control) { modifiers |= HotkeyBinding.Modifier.control.rawValue }
        if onKeyDown?(UInt32(event.keyCode), modifiers) ?? true {
            window?.makeFirstResponder(nil)
        }
    }
}
