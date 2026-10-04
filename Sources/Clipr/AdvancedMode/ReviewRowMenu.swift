import AppKit

/// One item of a Review row menu, described as data so the menus can be tested and shown as a
/// native `NSMenu` popped up from a SwiftUI-drawn button.
///
/// Why not SwiftUI's `Menu`: on macOS it's an `NSPopUpButton`, and a native control inside a List
/// row sets accessibility attributes while SwiftUI updates the row — re-entering that update and
/// leaving SwiftUI in an attribute cycle it never exits (see the segmented-picker freeze). A menu
/// popped up on demand puts no native control in the row at all.
indirect enum RowMenuEntry {
    case action(String, enabled: Bool = true, checked: Bool = false, perform: () -> Void)
    case submenu(String, enabled: Bool, [RowMenuEntry])
    case separator
}

@MainActor
enum RowMenu {
    /// Edit first; Retake and Replace not while read-only, nor while an image editor is open on
    /// the step (it would write the old image back).
    static func imageActions(isReadOnly: Bool, isInEditor: Bool, onEdit: @escaping () -> Void,
                             onRetake: @escaping () -> Void, onReplace: @escaping () -> Void) -> [RowMenuEntry] {
        let canChangeImage = !isReadOnly && !isInEditor
        return [
            .action("Edit Image…", perform: onEdit),
            .separator,
            .action("Retake Screenshot…", enabled: canChangeImage, perform: onRetake),
            .action("Replace with File…", enabled: canChangeImage, perform: onReplace),
        ]
    }

    static func sizes(current: ImageSize, isReadOnly: Bool, set: @escaping (ImageSize) -> Void) -> [RowMenuEntry] {
        ImageSize.allCases.map { size in
            .action(size.title, enabled: !isReadOnly, checked: size == current) { set(size) }
        }
    }

    static func makeMenu(_ entries: [RowMenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .action(title, enabled, checked, perform):
                let item = ClosureMenuItem(title: title, perform: perform)
                item.isEnabled = enabled
                item.state = checked ? .on : .off
                menu.addItem(item)
            case let .submenu(title, enabled, children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = makeMenu(children)
                item.isEnabled = enabled
                menu.addItem(item)
            }
        }
        return menu
    }

    /// Shows the menu at the pointer, on the next run-loop pass so its tracking loop never runs
    /// inside the SwiftUI button action (and so inside a view update).
    static func popUp(_ entries: [RowMenuEntry]) {
        let location = NSEvent.mouseLocation
        let menu = makeMenu(entries)
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }
}

/// A menu item that runs a closure. It is its own target; the menu keeps it alive.
private final class ClosureMenuItem: NSMenuItem {
    private let perform: () -> Void

    init(title: String, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { perform() }
}
