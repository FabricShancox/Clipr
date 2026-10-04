import AppKit

/// Deleting steps to the Trash, and putting them back on undo.
extension ReviewModel {
    func deleteSelection() { delete(ids: selection) }

    /// Refused, with nothing moved, if any of the steps has an image editor open: the editor's
    /// next save would write the step's sidecar and edited preview back into the session as
    /// orphans, and the delete's undo would then fail on them.
    func delete(ids: Set<UUID>) {
        guard !isReadOnly, !ids.isEmpty else { return }
        guard ids.isDisjoint(with: stepsInEditor) else { banner = Self.editorOpenBanner; return }
        flushPendingCaption()
        let targets = manifest.steps.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        var trashed: [UUID: TrashedStep] = [:]
        var failed: [String] = []
        for step in targets {
            do { trashed[step.id] = try files.trash(step.file, in: folder) } catch { failed.append(step.file) }
        }
        guard !trashed.isEmpty else {
            // A pending "will retry" matters more: it says edits are not on disk.
            if !isDirty { banner = failed.first.map { "Couldn't move \($0) to the Trash" } }
            return
        }
        let firstIndex = manifest.steps.firstIndex { trashed[$0.id] != nil } ?? 0
        let (updated, removed) = ManifestEditor.removing(ids: Set(trashed.keys), from: manifest)
        manifest = updated
        let saved = persist()
        if saved, let failure = failed.first { banner = "Couldn't move \(failure) to the Trash" }
        selection = manifest.steps.isEmpty ? [] : [manifest.steps[min(firstIndex, manifest.steps.count - 1)].id]
        let trashedSteps = removed.compactMap { item in trashed[item.record.id].map { (item, $0) } }
        registerUndo("Delete Steps") { $0.restore(trashedSteps) }
    }

    /// Undo of a delete. Steps whose files are no longer in the Trash stay deleted, so the manifest
    /// never gains an entry for a missing image; redo re-deletes only what was actually restored.
    private func restore(_ items: [(RemovedStep, TrashedStep)]) {
        var restored: [RemovedStep] = []
        var missing: [String] = []
        for (removed, trashedStep) in items {
            do {
                try files.restore(trashedStep)
                restored.append(removed)
            } catch {
                missing.append(trashedStep.file)
            }
        }
        guard !restored.isEmpty else {
            if !isDirty, let first = missing.first { banner = "Couldn't restore \(first) — it's no longer in the Trash" }
            return
        }
        manifest = ManifestEditor.restoring(restored, into: manifest)
        let saved = persist()
        if saved, let first = missing.first { banner = "Couldn't restore \(first) — it's no longer in the Trash" }
        selection = Set(restored.map(\.record.id))
        let ids = Set(restored.map(\.record.id))
        registerUndo("Delete Steps") { $0.delete(ids: ids) }
    }
}
