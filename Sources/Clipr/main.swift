import Cocoa

let app = NSApplication.shared
// Top-level code runs on the main thread; AppDelegate is main-actor isolated.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Set again in `applicationDidFinishLaunching` alongside the menu bar; done here too so the app
// never briefly registers as an accessory before launching finishes.
app.setActivationPolicy(.regular)
app.run()
