import AppKit

/// Caption editing: debounced saves while typing, and one "Edit Caption" undo per focused edit
/// that Esc can cancel.
extension ReviewModel {
    /// Call when a caption field gains focus; remembers the caption Esc and undo return to.
    func beginCaptionEdit(for id: UUID) {
        guard !isReadOnly, let step = manifest.steps.first(where: { $0.id == id }) else { return }
        // Moving focus straight from one caption to another ends the first edit as a commit.
        if let open = captionSession, open.id != id {
            let typed = pendingCaption?.id == open.id ? pendingCaption!.text : manifest.steps.first { $0.id == open.id }?.caption
            commitCaption(typed, for: open.id)
        }
        captionSession = (id, step.caption)
    }

    /// Esc: drop typing and put the original back on disk without leaving anything to undo.
    func cancelCaptionEdit(for id: UUID) {
        guard !isReadOnly else { return }
        // Typing in another step must survive Esc in this one.
        if let pending = pendingCaption, pending.id != id { flushPendingCaption() }
        captionWork?.cancel()
        captionWork = nil
        pendingCaption = nil
        guard let session = captionSession, session.id == id else { return }
        captionSession = nil
        let restored = ManifestEditor.settingCaption(session.original, forStep: id, in: manifest)
        guard restored != manifest else { return }
        manifest = restored
        persist()
    }

    /// Called on every keystroke; saves once typing pauses.
    func editCaption(_ text: String?, for id: UUID) {
        guard !isReadOnly else { return }
        captionWork?.cancel()
        // Typing back to what's already saved must drop an earlier pending value, or the debounce
        // (or a window-close flush) would save text the user has since deleted.
        let current = manifest.steps.first { $0.id == id }?.caption
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (normalized?.isEmpty ?? true ? nil : normalized) == current {
            if pendingCaption?.id == id { pendingCaption = nil }
            captionWork = nil
            return
        }
        pendingCaption = (id, text)
        let work = DispatchWorkItem { [weak self] in self?.flushPendingCaption() }
        captionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + captionDelay, execute: work)
    }

    /// Return or focus loss: save now, superseding any pending typing save for this step.
    func commitCaption(_ text: String?, for id: UUID) {
        guard !isReadOnly else { return }
        // A pending edit for another step would otherwise be dropped by the cancel below.
        if let pending = pendingCaption, pending.id != id { flushPendingCaption() }
        captionWork?.cancel()
        pendingCaption = nil
        if let session = captionSession, session.id == id {
            captionSession = nil
            let updated = ManifestEditor.settingCaption(text, forStep: id, in: manifest)
            if updated != manifest { manifest = updated; persist() }
            // A step deleted or reloaded away mid-edit has nothing left to undo.
            guard let step = manifest.steps.first(where: { $0.id == id }), step.caption != session.original else { return }
            let original = session.original
            registerUndo("Edit Caption") {
                $0.replace(with: ManifestEditor.settingCaption(original, forStep: id, in: $0.manifest), actionName: "Edit Caption")
            }
            return
        }
        applyCaption(text, for: id)
    }

    /// Window close calls this so a caption typed in the last half-second isn't lost.
    func flushPendingCaption() {
        captionWork?.cancel()
        captionWork = nil
        guard let pending = pendingCaption else { return }
        pendingCaption = nil
        if captionSession?.id == pending.id {
            let updated = ManifestEditor.settingCaption(pending.text, forStep: pending.id, in: manifest)
            if updated != manifest { manifest = updated; persist() }
        } else {
            applyCaption(pending.text, for: pending.id)
        }
    }

    /// Saves any pending caption and retries a save that failed earlier. Window close calls this.
    func flush() {
        flushPendingCaption()
        if isDirty { persist() }
    }

    private func applyCaption(_ text: String?, for id: UUID) {
        let updated = ManifestEditor.settingCaption(text, forStep: id, in: manifest)
        guard updated != manifest else { return }
        replace(with: updated, actionName: "Edit Caption")
    }
}
