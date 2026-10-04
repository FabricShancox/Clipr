import AppKit
import SwiftUI

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

    /// Shows the menu under `anchor`'s button (so keyboard and VoiceOver activation land in the
    /// right place), or at the pointer when there is no anchor yet. Deferred a run-loop pass so its
    /// tracking loop never runs inside the SwiftUI button action (and so inside a view update).
    static func popUp(_ entries: [RowMenuEntry], anchor: RowMenuAnchor? = nil) {
        let fallback = NSEvent.mouseLocation
        let menu = makeMenu(entries)
        DispatchQueue.main.async {
            if let view = anchor?.view, view.window != nil {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY : view.bounds.minY), in: view)
            } else {
                menu.popUp(positioning: nil, at: fallback, in: nil)
            }
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
