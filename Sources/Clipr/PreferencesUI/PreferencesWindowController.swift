import Cocoa
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    init(
        settings: SettingsStore,
        onHotkeysChanged: @escaping () -> Void,
        onSaveFolderChanged: @escaping () -> Void,
        onCaptureCursorChanged: @escaping () -> Void,
        onHotkeyRecording: @escaping (_ recorder: UUID, _ recording: Bool) -> Void = { _, _ in }
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipr Preferences"
        super.init(window: window)
        window.contentView = NSHostingView(rootView: PreferencesView(
            settings: settings,
            onHotkeysChanged: onHotkeysChanged,
            onSaveFolderChanged: onSaveFolderChanged,
            onCaptureCursorChanged: onCaptureCursorChanged,
            onHotkeyRecording: onHotkeyRecording
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }
}
