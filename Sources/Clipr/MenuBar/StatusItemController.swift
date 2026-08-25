import Cocoa

final class StatusItemController {
    let statusItem: NSStatusItem
    let menu = NSMenu()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Clipr")
        }
        let quitItem = NSMenuItem(title: "Quit Clipr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
}
