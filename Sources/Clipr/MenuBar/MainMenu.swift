import Cocoa

/// The app's menu bar. Clipr runs as a regular app (`.regular` activation policy) rather than a
/// menu-bar-only accessory, so it owns the menu bar whenever it's frontmost — and an app with no
/// `NSApp.mainMenu` shows an empty one, with no Quit and no working ⌘X/⌘C/⌘V/⌘A in any text
/// field. This builds the standard set. The status-item menu (`StatusItemController`) stays as
/// the quick-access route and is unaffected.
extension AppDelegate {
    func installMainMenu() {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(editMenuItem())
        let windowItem = windowMenuItem()
        main.addItem(windowItem)
        NSApp.mainMenu = main
        // Lets AppKit add "Bring All to Front" and the live window list itself.
        NSApp.windowsMenu = windowItem.submenu
    }

    private func appMenuItem() -> NSMenuItem {
        let name = "Clipr"
        let menu = NSMenu()
        menu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Mirrors the status-item menu's Preferences item. That one's ⌘, only works while that
        // menu is open; here it becomes a real app-wide shortcut.
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(showPreferencesFromMenu), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    /// Deliberately no Undo/Redo: the editor keeps its own annotation undo stack and already binds
    /// ⌘Z / ⇧⌘Z in `EditorView+Toolbar.swift`. A menu item on the same keys would shadow those and
    /// dispatch to `NSUndoManager`, which nothing here populates, so Undo would appear to break.
    /// The rest route down the responder chain and are what make text fields editable.
    private func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let item = NSMenuItem()
        item.title = "Edit"
        item.submenu = menu
        return item
    }

    private func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let item = NSMenuItem()
        item.title = "Window"
        item.submenu = menu
        return item
    }
}
