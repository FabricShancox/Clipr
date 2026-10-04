// Sources/Clipr/AdvancedMode/ReviewModel.swift
import AppKit

/// Everything Review can change about a session, applied as manifest edits that save at once and
/// undo by swapping the previous manifest back (plus moving files out of / back from the Trash for
/// deletes). It owns its own `UndoManager`: Clipr's main menu has no Undo item (the image editor
/// binds ⌘Z itself), so the window's undo manager would never be reached.
@MainActor
final class ReviewModel: ObservableObject {
    @Published private(set) var manifest: SessionManifest
    @Published var selection: Set<UUID> = []
    @Published private(set) var banner: String?
    /// Bumped when step images may have changed on disk, so rows rebuild their thumbnails.
    @Published private(set) var refreshToken = 0

    let folder: URL
    let readOnlyReason: SessionManifestStore.ReadOnlyReason?
    var isReadOnly: Bool { readOnlyReason != nil }
    let undoManager = UndoManager()

    private let files: StepFiles
    private let save: (SessionManifest, URL) throws -> Void
    private let writeImage: (NSImage, URL) throws -> Void
    private let captionDelay: TimeInterval
    private var pendingCaption: (id: UUID, text: String?)?
    private var captionWork: DispatchWorkItem?
    /// True after a failed save until a later save succeeds, so edits held only in memory are
    /// retried (flush) and never overwritten by a reload.
    private var isDirty = false
    /// A reload skipped because unsaved edits were in memory; runs after the next successful save.
    private var reloadPending = false
    /// While a caption field is focused, its debounced saves are not individual undo steps: the
    /// whole session becomes one "Edit Caption" undo when committed, and Esc restores `original`.
    private var captionSession: (id: UUID, original: String?)?

    /// True while edits exist only in memory because saving keeps failing; closing the window
    /// then would lose them.
    var hasUnsavedChanges: Bool { isDirty }

    var readOnlyNotice: String? {
        switch readOnlyReason {
        case .newerVersion: "Made by a newer version of Clipr — read only"
        case .unreadable: "Couldn't read session.json — read only"
        case nil: nil
        }
    }

    init(
        folder: URL,
        files: StepFiles = StepFiles(),
        save: @escaping (SessionManifest, URL) throws -> Void = SessionManifestStore.saveSafely,
        writeImage: @escaping (NSImage, URL) throws -> Void = StepFiles.writePNG,
        captionDelay: TimeInterval = 0.5
    ) {
        self.folder = folder
        self.files = files
        self.save = save
        self.writeImage = writeImage
        self.captionDelay = captionDelay
        let loaded = SessionManifestStore.loadForReview(from: folder)
        manifest = loaded.manifest
        readOnlyReason = loaded.readOnly
        // Explicit groups: with grouping by run-loop event, several edits in one pass (and tests)
        // merge into a single undo step, and undo() inside an open event group raises.
        undoManager.groupsByEvent = false
    }

    func url(for step: StepRecord) -> URL { folder.appendingPathComponent(step.file) }
    func thumbnailURL(for step: StepRecord) -> URL { StepFiles.thumbnailURL(of: step.file, in: folder) }

    // MARK: Reorder

    func move(fromOffsets: IndexSet, toOffset: Int) {
        guard !isReadOnly else { return }
        replace(with: ManifestEditor.moving(manifest, fromOffsets: fromOffsets, toOffset: toOffset), actionName: "Move Steps")
    }

    /// ⌥↑ / ⌥↓. Does nothing at either end rather than wrapping.
    func moveSelection(by delta: Int) {
        let indices = IndexSet(manifest.steps.indices.filter { selection.contains(manifest.steps[$0].id) })
        guard let first = indices.first, let last = indices.last, delta != 0 else { return }
        if delta < 0 {
            guard first > 0 else { return }
            move(fromOffsets: indices, toOffset: first - 1)
        } else {
            guard last < manifest.steps.count - 1 else { return }
            move(fromOffsets: indices, toOffset: last + 2)
        }
    }

    // MARK: Captions

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

    // MARK: Delete

    func deleteSelection() { delete(ids: selection) }

    func delete(ids: Set<UUID>) {
        guard !isReadOnly, !ids.isEmpty else { return }
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

    // MARK: Replace image

    /// Swaps a step's image for a retake or a chosen file. The old image and everything derived
    /// from it (annotations, zoom crop, edited preview) go to the Trash, and the click point and
    /// zoom are cleared because they describe the old image. The step keeps its filename, place
    /// and caption.
    func replaceImage(for id: UUID, with image: NSImage) {
        guard !isReadOnly, let step = manifest.steps.first(where: { $0.id == id }) else { return }
        flushPendingCaption()
        let failure = "Couldn't replace the image for \(step.file)"
        let old: TrashedStep
        do { old = try files.trash(step.file, in: folder) } catch { banner = failure; return }
        do {
            try writeImage(image, url(for: step))
        } catch {
            // Put the original back so a failed write never leaves the step without an image.
            try? files.restore(old)
            banner = failure
            return
        }
        applyImageFields(clickPoint: nil, zoomFile: nil, for: id)
        registerUndo("Replace Image") { $0.swapImage(for: id, restoring: old, record: step) }
    }

    /// Undo and redo of a replacement: the current image set goes to the Trash and `trashed` comes
    /// back, with the click data that belongs to it. Each swap registers the opposite swap.
    private func swapImage(for id: UUID, restoring trashed: TrashedStep, record: StepRecord) {
        guard let current = manifest.steps.first(where: { $0.id == id }) else { return }
        let currentFiles: TrashedStep
        do { currentFiles = try files.trash(current.file, in: folder) } catch {
            banner = "Couldn't replace the image for \(current.file)"
            return
        }
        do {
            try files.restore(trashed)
        } catch {
            try? files.restore(currentFiles)
            banner = "Couldn't restore \(current.file) — it's no longer in the Trash"
            return
        }
        applyImageFields(clickPoint: record.clickPoint, zoomFile: record.zoomFile, for: id)
        registerUndo("Replace Image") { $0.swapImage(for: id, restoring: currentFiles, record: current) }
    }

    private func applyImageFields(clickPoint: CGPoint?, zoomFile: String?, for id: UUID) {
        guard let index = manifest.steps.firstIndex(where: { $0.id == id }) else { return }
        manifest.steps[index].clickPoint = clickPoint
        manifest.steps[index].zoomFile = zoomFile
        _ = persist()
        for url in StepFiles.companions(of: manifest.steps[index].file, in: folder) + [url(for: manifest.steps[index])] {
            ThumbnailCache.shared.remove(url)
        }
        ThumbnailCache.shared.remove(folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: manifest.steps[index].file)))
        refreshToken += 1
    }

    // MARK: Reload

    /// After the image editor closes (it may have changed or deleted the step's image), re-read the
    /// session from disk and make rows decode their thumbnails again.
    func reload() {
        flush()
        // Unsaved edits live only in memory; reloading now would silently discard them.
        guard !isDirty else { reloadPending = true; return }
        reloadPending = false
        manifest = SessionManifestStore.load(from: folder)
        let ids = Set(manifest.steps.map(\.id))
        selection = selection.filter { ids.contains($0) }
        refreshToken += 1
    }

    // MARK: Plumbing

    /// Registering the inverse from inside the undo handler is what makes redo work for free.
    private func replace(with new: SessionManifest, actionName: String) {
        guard new != manifest else { return }
        let old = manifest
        manifest = reconciled(new)
        persist()
        registerUndo(actionName) { $0.replace(with: old, actionName: actionName) }
    }

    /// An undo snapshot may predate changes it must not undo: a step deleted since (whose files may
    /// be gone from the Trash) must stay deleted, and a step added by reload must survive. So the
    /// snapshot's order and records are kept only for steps that still exist, and steps it has never
    /// heard of are appended.
    private func reconciled(_ target: SessionManifest) -> SessionManifest {
        let currentIDs = Set(manifest.steps.map(\.id))
        let targetIDs = Set(target.steps.map(\.id))
        var result = manifest
        result.steps = target.steps.filter { currentIDs.contains($0.id) }
            + manifest.steps.filter { !targetIDs.contains($0.id) }
        return result
    }

    /// Opens a group only for a fresh user action; registrations made while undoing or redoing
    /// belong to the group the undo manager is already replaying.
    private func registerUndo(_ name: String, _ handler: @escaping (ReviewModel) -> Void) {
        let ownGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if ownGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(name)
        if ownGroup { undoManager.endUndoGrouping() }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !isReadOnly else { return true }
        do {
            try save(manifest, folder)
            banner = nil
            isDirty = false
            if reloadPending { reload() }
            return true
        } catch {
            banner = "Couldn't save changes — will retry"
            isDirty = true
            return false
        }
    }
}
