import SwiftUI
import Cocoa

struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false

    var body: some View {
        Button(isRecording ? "Press a key…" : binding.displayString) {
            isRecording = true
        }
        .background(KeyCatcherView(isRecording: $isRecording, binding: $binding))
    }
}

private struct KeyCatcherView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var binding: HotkeyBinding

    func makeNSView(context: Context) -> KeyCatcherNSView {
        let view = KeyCatcherNSView()
        view.onKeyDown = { keyCode, modifiers in
            binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcherNSView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class KeyCatcherNSView: NSView {
    var isRecording = false
    var onKeyDown: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= HotkeyBinding.Modifier.command.rawValue }
        if event.modifierFlags.contains(.shift) { modifiers |= HotkeyBinding.Modifier.shift.rawValue }
        if event.modifierFlags.contains(.option) { modifiers |= HotkeyBinding.Modifier.option.rawValue }
        if event.modifierFlags.contains(.control) { modifiers |= HotkeyBinding.Modifier.control.rawValue }
        onKeyDown?(UInt32(event.keyCode), modifiers)
        window?.makeFirstResponder(nil)
    }
}
