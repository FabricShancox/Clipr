import Foundation

/// The image editors open on one session's steps. Owned by `AdvancedModeCoordinator` per session
/// folder rather than by the Review window, so closing Review doesn't orphan them: a reopened
/// Review for the same session picks them up again (still refusing to delete or replace a step
/// whose editor is open, and bringing that editor forward instead of opening a second), and quit
/// and export still flush their pending saves.
final class SessionEditorRegistry {
    struct Entry {
        /// Kept alive here until it finishes; without this the editor's controller would be
        /// released as soon as the code that opened it returned.
        let editor: AnyObject
        let stepID: UUID
        let flush: () -> Void
        let bringForward: () -> Void
    }

    private(set) var entries: [Entry] = []
    /// The Review showing this session, if one is open: told whenever the set of steps being
    /// edited changes, and when an editor on `stepID` finishes so its row can reload.
    var onStepsInEditorChanged: ((Set<UUID>) -> Void)?
    var onEditorFinished: ((_ stepID: UUID) -> Void)?

    var stepIDs: Set<UUID> { Set(entries.map(\.stepID)) }
    var isEmpty: Bool { entries.isEmpty }

    func entry(for stepID: UUID) -> Entry? {
        entries.first { $0.stepID == stepID }
    }

    func add(_ entry: Entry) {
        entries.append(entry)
        onStepsInEditorChanged?(stepIDs)
    }

    /// The editor closed (Done, Discard or its close button).
    func finished(_ editor: AnyObject) {
        guard let index = entries.firstIndex(where: { $0.editor === editor }) else { return }
        let stepID = entries.remove(at: index).stepID
        onStepsInEditorChanged?(stepIDs)
        onEditorFinished?(stepID)
    }

    func flushAll() {
        for entry in entries { entry.flush() }
    }
}
