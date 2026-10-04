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
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
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

    /// Undo/Redo here act only on text being typed — a text annotation, the rename field, any
    /// Preferences field — and are disabled otherwise (see `TextUndoMenuTarget`). The editor keeps
    /// its own annotation undo stack bound to ⌘Z / ⇧⌘Z in `EditorView+Toolbar.swift`; a disabled
    /// menu item doesn't claim the key, so those still fire whenever no text is being edited. With
    /// no Undo item at all, ⌘Z did nothing inside text fields (the editor's own button is off then).
    /// The rest route down the responder chain and are what make text fields editable.
    private func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: #selector(TextUndoMenuTarget.undoText(_:)), keyEquivalent: "z")
        undo.target = TextUndoMenuTarget.shared
        menu.addItem(undo)
        let redo = NSMenuItem(title: "Redo", action: #selector(TextUndoMenuTarget.redoText(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = TextUndoMenuTarget.shared
        menu.addItem(redo)
        menu.addItem(.separator())
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

/// Target for the Edit menu's Undo/Redo: forwards to the undo manager of the text view being
/// typed in, and validates as disabled when no text view has focus, so the editor's own ⌘Z
/// shortcut (annotation undo) receives the key instead.
final class TextUndoMenuTarget: NSObject, NSMenuItemValidation {
    static let shared = TextUndoMenuTarget()

    private var focusedTextUndoManager: UndoManager? {
        guard let text = NSApp.keyWindow?.firstResponder as? NSText else { return nil }
        return text.undoManager
    }

    @objc func undoText(_ sender: Any?) { focusedTextUndoManager?.undo() }
    @objc func redoText(_ sender: Any?) { focusedTextUndoManager?.redo() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let manager = focusedTextUndoManager else { return false }
        switch menuItem.action {
        case #selector(undoText(_:)): return manager.canUndo
        case #selector(redoText(_:)): return manager.canRedo
        default: return false
        }
    }
}
