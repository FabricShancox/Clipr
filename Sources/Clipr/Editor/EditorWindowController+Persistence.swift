import Cocoa

/// Auto-save: the annotations sidecar on every settled edit, and the flattened `_edited.png`
/// when it's due.
extension EditorWindowController {
    /// Fired ~800ms after the last edit settles (see `EditorView.scheduleAutoSave`). That `Task`
    /// isn't cancelled by a content-view swap, so a debounce left over from a since-abandoned view
    /// must not overwrite what the window has moved on to. `forURL` catches a switch to a
    /// different capture; `generation` catches crop and canvas-resize, which keep the same URL but
    /// remap every annotation, so a stale save would write pre-crop geometry over the good one.
    func autoSave(for forURL: URL, annotations: [AnnotationObject], generation: Int) {
        guard generation == self.generation, forURL == rawURL else { return }
        persist(annotations, flattened: .throttled)
    }

    /// How eagerly `persist` rewrites the flattened `_edited.png`.
    enum FlattenedWrite {
        /// Write it now if anything has changed — for the moments where the file on disk has to be
        /// current: closing, quitting, switching capture, or changing the base image.
        case now
        /// Skip it if one was written in the last few seconds. Used by the debounced auto-save,
        /// which fires far too often to re-encode a large capture every time.
        case throttled
    }

    /// Writes the flattened preview and the annotations sidecar for the CURRENT capture. Callers
    /// inside this class use it directly — they only ever run for the live view, so they need no
    /// staleness check. Failures are logged here, since this can fire often; `flushPendingSave`
    /// tells the user (once) when a flush it depends on fails.
    @discardableResult
    func persist(_ annotations: [AnnotationObject], flattened: FlattenedWrite = .now) -> Bool {
        do {
            // The sidecar is what actually preserves the user's work — it restores editable
            // annotations on reopen and costs well under a millisecond — so it is written every
            // time. `_edited.png` is a derived export and may lag by a few seconds during active
            // editing; it is brought up to date whenever it matters (see `FlattenedWrite.now`),
            // and a stale one is regenerated from the sidecar anyway.
            try storage.saveAnnotations(annotations, rawURL: rawURL)

            let dueForWrite = flattened == .now
                || Date().timeIntervalSince(lastFlattenedWrite) >= Self.flattenedWriteInterval
            guard flattenedIsStale, dueForWrite else { return true }

            let rendered = AnnotationRenderer.flatten(base: image, annotations: annotations)
            _ = try storage.saveEditedCapture(rendered, rawURL: rawURL)
            flattenedIsStale = false
            lastFlattenedWrite = Date()
            // Deliberately does NOT touch the pasteboard. Auto-save used to copy here too, which
            // meant every settled edit silently replaced whatever the user had copied — annotate
            // for a minute and anything you'd put on the clipboard was gone. Copying is an
            // explicit action; it belongs in `copy(annotations:)` alone.
            //
            // Persists the actual editable annotation objects (not just the flattened preview)
            // so reopening this capture later — from Recents, or after relaunching Clipr —
            // restores them instead of showing a plain, no-longer-editable image. This is what
            // makes returning to a previously-edited capture not read as "losing" the edits.
            try storage.saveAnnotations(annotations, rawURL: rawURL)
            return true
        } catch {
            NSLog("Clipr: auto-save failed: \(error)")
            return false
        }
    }
}
