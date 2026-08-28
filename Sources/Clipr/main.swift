import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Set again in `applicationDidFinishLaunching` alongside the menu bar; done here too so the app
// never briefly registers as an accessory before launching finishes.
app.setActivationPolicy(.regular)
app.run()
