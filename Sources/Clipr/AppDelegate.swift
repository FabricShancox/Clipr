import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
