import Cocoa

final class StatusItemController {
    let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let advancedModeItem = NSMenuItem()

    var onCaptureNow: (() -> Void)?
    var onOpenImage: (() -> Void)?
    var onToggleAdvancedMode: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    init() {
        // `variableLength`, not `squareLength`: Advanced Mode shows its running step count as the
        // button's title (see `setAdvancedModeStepCount`), and a square item clips that away —
        // which hid the only feedback that mode has.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Clipr")
        }

        let captureItem = NSMenuItem(title: "Capture Now", action: #selector(captureNow), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        let openImageItem = NSMenuItem(title: "Open Image…", action: #selector(openImage), keyEquivalent: "")
        openImageItem.target = self
        menu.addItem(openImageItem)

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
        // Advanced Mode has no visible overlay of its own (it's silent background click
        // monitoring), so without this the user has no way to tell it's doing anything until
        // they stop it. The count updates live via `setAdvancedModeStepCount` as captures land.
        statusItem.button?.title = active ? "  0 captured" : ""
    }

    func setAdvancedModeStepCount(_ count: Int) {
        statusItem.button?.title = "  \(count) captured"
    }

    @objc private func captureNow() { onCaptureNow?() }
    @objc private func openImage() { onOpenImage?() }
    @objc private func toggleAdvancedMode() { onToggleAdvancedMode?() }
    @objc private func openPreferences() { onOpenPreferences?() }
}
