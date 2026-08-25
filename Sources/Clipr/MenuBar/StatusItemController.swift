import Cocoa

final class StatusItemController {
    let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let advancedModeItem = NSMenuItem()

    var onCaptureNow: (() -> Void)?
    var onToggleAdvancedMode: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Clipr")
        }

        let captureItem = NSMenuItem(title: "Capture Now", action: #selector(captureNow), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        advancedModeItem.title = "Start Advanced Mode"
        advancedModeItem.action = #selector(toggleAdvancedMode)
        advancedModeItem.target = self
        menu.addItem(advancedModeItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func setAdvancedModeActive(_ active: Bool) {
        advancedModeItem.title = active ? "Stop Advanced Mode" : "Start Advanced Mode"
    }

    @objc private func captureNow() { onCaptureNow?() }
    @objc private func toggleAdvancedMode() { onToggleAdvancedMode?() }
    @objc private func openPreferences() { onOpenPreferences?() }
}
