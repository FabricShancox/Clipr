import AppKit

/// Everything Review can change about a session, applied as manifest edits that save at once and
/// undo by swapping the previous manifest back (plus moving files out of / back from the Trash for
/// deletes). It owns its own `UndoManager`: Clipr's main menu has no Undo item (the image editor
/// binds ⌘Z itself), so the window's undo manager would never be reached.
///
/// Captions, deletion and image replacement live in `ReviewModel+…` extensions. The state they
/// share is internal rather than private so those files can reach it; nothing outside the model
/// and its extensions writes it.
@MainActor
final class ReviewModel: ObservableObject {
    @Published var manifest: SessionManifest
    @Published var selection: Set<UUID> = []
    @Published var banner: String?
    /// Bumped when any step's image may have changed on disk (a reload), so rows rebuild their
    /// thumbnails.
    @Published private(set) var refreshToken = 0
    /// Per step: bumped when just that step's image changed (a replacement, its editor closing),
    /// so only its row decodes again.
    @Published var imageVersions: [UUID: Int] = [:]
    /// Which file each step's thumbnail comes from (raw or edited preview), so rows don't stat the
    /// disk every time they render. Cleared whenever a step's files may have changed.
    var thumbnailURLs: [String: URL] = [:]
    /// Steps with an image editor open on them, kept up to date by `ReviewWindowController`.
    /// Their images can't be replaced (or a replacement undone) meanwhile: the editor still holds
    /// the old image and would write it, or an edited preview of it, back over the new one.
    @Published var stepsInEditor: Set<UUID> = []

    let folder: URL
    let readOnlyReason: SessionManifestStore.ReadOnlyReason?
    var isReadOnly: Bool { readOnlyReason != nil }
    let undoManager = UndoManager()

    let files: StepFiles
    private let save: (SessionManifest, URL) throws -> Void
    let writeImage: (Data, URL) throws -> Void
    /// Decoded step images shown in Review; entries are dropped when a step's image changes.
    let thumbnails: ThumbnailCache
    let captionDelay: TimeInterval
    var pendingCaption: (id: UUID, text: String?)?
    var captionWork: DispatchWorkItem?
    /// True after a failed save until a later save succeeds, so edits held only in memory are
    /// retried (flush) and never overwritten by a reload.
    var isDirty = false
    /// A reload skipped because unsaved edits were in memory; runs after the next successful save.
    private var reloadPending = false
    /// While a caption field is focused, its debounced saves are not individual undo steps: the
    /// whole session becomes one "Edit Caption" undo when committed, and Esc restores `original`.
    var captionSession: (id: UUID, original: String?)?
    /// The step each "Replace Image" group on the undo / redo stack swaps, in stack order. The
    /// undo manager can't be asked what its top group does, and refusing from inside the handler
    /// would already have popped the group, so `undo()`/`redo()` check these first.
    private var imageSwapUndoTargets: [UUID] = []
    private var imageSwapRedoTargets: [UUID] = []

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
        writeImage: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
        thumbnails: ThumbnailCache = .shared,
        captionDelay: TimeInterval = 0.5
    ) {
        self.folder = folder
        self.files = files
        self.save = save
        self.writeImage = writeImage
        self.thumbnails = thumbnails
        self.captionDelay = captionDelay
        let loaded = SessionManifestStore.loadForReview(from: folder)
        manifest = loaded.manifest
        readOnlyReason = loaded.readOnly
        // Explicit groups: with grouping by run-loop event, several edits in one pass (and tests)
        // merge into a single undo step, and undo() inside an open event group raises.
        undoManager.groupsByEvent = false
    }

    func url(for step: StepRecord) -> URL { folder.appendingPathComponent(step.file) }
    func thumbnailURL(for step: StepRecord) -> URL {
        if let cached = thumbnailURLs[step.file] { return cached }
        let url = StepFiles.thumbnailURL(of: step.file, in: folder)
        thumbnailURLs[step.file] = url
        return url
    }

    func imageVersion(of id: UUID) -> Int { imageVersions[id] ?? 0 }

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

    // MARK: Image size

    func setImageSize(_ size: ImageSize?, for ids: Set<UUID>) {
        guard !isReadOnly else { return }
        applyImageSizes(from: ManifestEditor.settingImageSize(size, forSteps: ids, in: manifest))
    }

    /// ⌘+ / ⌘−: each selected step one size larger or smaller.
    func stepImageSize(by delta: Int) {
        guard !isReadOnly else { return }
        applyImageSizes(from: ManifestEditor.steppingImageSize(by: delta, forSteps: selection, in: manifest))
    }

    /// Takes each step's size from `target` and registers an undo scoped to just those sizes.
    /// A whole-manifest snapshot (`replace`) would also roll back anything saved since, such as a
    /// caption a debounce wrote after this change; the inverse here re-applies only the sizes it
    /// replaced, to whatever the manifest is by then, and registers its own inverse for redo.
    private func applyImageSizes(from target: SessionManifest) {
        let wanted = Dictionary(target.steps.map { ($0.id, $0.imageSize) }, uniquingKeysWith: { first, _ in first })
        var previous: [(id: UUID, size: ImageSize?)] = []
        for index in manifest.steps.indices {
            let step = manifest.steps[index]
            guard let new = wanted[step.id], new != step.imageSize else { continue }
            previous.append((step.id, step.imageSize))
            manifest.steps[index].imageSize = new
        }
        // Nothing changed: nothing to save and nothing to undo.
        guard !previous.isEmpty else { return }
        persist()
        registerUndo(Self.imageSizeAction) { $0.restoreImageSizes(previous) }
    }

    private func restoreImageSizes(_ sizes: [(id: UUID, size: ImageSize?)]) {
        let wanted = Dictionary(sizes.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })
        var target = manifest
        for index in target.steps.indices {
            if let size = wanted[target.steps[index].id] { target.steps[index].imageSize = size }
        }
        applyImageSizes(from: target)
    }

    private static let imageSizeAction = "Change Image Size"

    // MARK: Reload

    /// Re-reads the session from disk and makes rows decode their thumbnails again. After an image
    /// editor closes, pass its step as `changedStep`: only that row's thumbnail is rebuilt.
    func reload(changedStep: UUID? = nil) {
        flush()
        // Unsaved edits live only in memory; reloading now would silently discard them.
        guard !isDirty else { reloadPending = true; return }
        reloadPending = false
        manifest = SessionManifestStore.load(from: folder)
        let ids = Set(manifest.steps.map(\.id))
        selection = selection.filter { ids.contains($0) }
        thumbnailURLs = [:]
        if let changedStep, ids.contains(changedStep) {
            imageVersions[changedStep, default: 0] += 1
        } else {
            refreshToken += 1
        }
    }

    // MARK: Undo

    /// ⌘Z. Refuses, leaving both stacks untouched, when the next undo would swap the image of a
    /// step that has an editor open: the editor still holds the old image and would write it back.
    func undo() {
        guard undoManager.canUndo else { return }
        if undoManager.undoActionName == Self.replaceImageAction, let id = imageSwapUndoTargets.last, stepsInEditor.contains(id) {
            banner = Self.editorOpenBanner
            return
        }
        undoManager.undo()
    }

    /// ⇧⌘Z. The mirror of `undo()`.
    func redo() {
        guard undoManager.canRedo else { return }
        if undoManager.redoActionName == Self.replaceImageAction, let id = imageSwapRedoTargets.last, stepsInEditor.contains(id) {
            banner = Self.editorOpenBanner
            return
        }
        undoManager.redo()
    }

    // MARK: Plumbing

    /// Registering the inverse from inside the undo handler is what makes redo work for free.
    func replace(with new: SessionManifest, actionName: String) {
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
    ///
    /// `imageSwapOf` records the step an image swap acts on, mirroring where the undo manager puts
    /// the group: a fresh action goes on the undo stack and clears redo (as the undo manager does),
    /// one registered while undoing goes on redo, and one registered while redoing back on undo.
    /// The handler pops its own entry as it runs, so the mirror stays right even when the undo
    /// manager is driven directly. A swap that fails registers nothing, and pushes nothing.
    func registerUndo(_ name: String, imageSwapOf target: UUID? = nil, _ handler: @escaping (ReviewModel) -> Void) {
        let ownGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if ownGroup { imageSwapRedoTargets.removeAll() }
        if let target {
            if undoManager.isUndoing { imageSwapRedoTargets.append(target) } else { imageSwapUndoTargets.append(target) }
        }
        if ownGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { model in
            if target != nil {
                if model.undoManager.isUndoing { _ = model.imageSwapUndoTargets.popLast() } else { _ = model.imageSwapRedoTargets.popLast() }
            }
            handler(model)
        }
        undoManager.setActionName(name)
        if ownGroup { undoManager.endUndoGrouping() }
    }

    @discardableResult
    func persist() -> Bool {
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
