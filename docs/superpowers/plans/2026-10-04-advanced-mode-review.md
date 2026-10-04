# Advanced Mode Review Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Advanced Mode's Review window into a guide editor: a vertical list where steps can be reordered, recaptioned and deleted (to the Trash), with every change autosaved to `session.json` and undoable.

**Architecture:** Pure `ManifestEditor` operations on `SessionManifest`, a `StepFiles` helper that moves a step's files to/from the Trash, and a `@MainActor ReviewModel` that applies edits, saves through a new `SessionManifestStore.saveSafely`, and owns an `UndoManager`. A rewritten SwiftUI `ReviewView` (`List` with selection and `.onMove`) renders the model; `ReviewWindowController` hosts it and refreshes rows when the image editor closes.

**Tech Stack:** Swift 5.10, SwiftPM, SwiftUI + AppKit, XCTest. macOS 14.

**Spec:** `docs/superpowers/specs/2026-10-04-advanced-mode-review-design.md`

## Global Constraints

- Platform floor macOS 14 (`Package.swift`). No new dependencies.
- Build `swift build`; tests `swift test` from repo root; app bundle `./Scripts/build-app.sh` (never commit `Clipr.app`). macOS has no `timeout` binary — don't rely on it.
- Order lives only in `session.json` `steps`; step files are never renamed. Displayed step numbers are 1-based positions.
- Every edit autosaves; caption typing saves after a 0.5 s pause; Return / focus loss commits immediately; Esc cancels.
- Undo/redo for reorder, caption and delete; action names exactly "Move Steps", "Edit Caption", "Delete Steps".
- Delete moves the step's files (raw PNG, `_annotations.json`, `_zoom.png`, `_edited.png`) to the Trash; no confirmation dialog.
- `saveSafely` refuses to write when the session folder can't be listed. Newer-version manifests (`version > 1`) are read-only and never written.
- Banner copy exactly: "Couldn't save changes — will retry"; "Made by a newer version of Clipr — read only"; trash failure "Couldn't move <file> to the Trash"; restore failure "Couldn't restore <file> — it's no longer in the Trash".
- Empty state copy: "No steps — press ⌘Z to undo". Caption placeholder: "Add a caption".
- Window 760 × 640 default, 560 × 400 minimum; title "Review — <session folder name>".
- Rename is disabled for editors opened from Review.
- Code comments explain *why*, in full sentences, matching repo style.

## Ruling vs. spec (recorded here so executors don't "fix" it)

The spec says the model registers undo with "the window's UndoManager". Clipr's main menu deliberately has no Undo/Redo items (`MenuBar/MainMenu.swift:49-51` — the image editor binds ⌘Z itself), so the window's undo manager is never reached by ⌘Z. The model therefore owns its own `UndoManager`, and `ReviewView` binds ⌘Z / ⇧⌘Z to it with keyboard-shortcut buttons that are disabled while a caption is being edited (so text-field undo still works there).

## Review Focus

1. **Deleting the last remaining step, then ⌘Z** — the user expects the step and its files back, and the empty state to disappear. Pinned in Task 4 (`testDeleteAllThenUndoRestoresEverything`).
2. **Undo of a delete after the Trash was emptied** — must not recreate a manifest entry pointing at a missing PNG. Pinned in Task 4 (`testUndoDeleteSkipsStepWhoseFilesLeftTheTrash`).
3. **Typing a caption then closing the window within 0.5 s** — the edit must not be lost. Pinned in Task 4 (`testFlushPendingCaptionSavesImmediately`).
4. **Moving a multi-row, non-contiguous selection to the end** — order must match what the user dragged, selection kept. Pinned in Task 1 (`testMoveNonContiguousToEnd`) and Task 4 (`testMoveKeepsSelectionByID`).
5. **Folder becomes unreadable mid-session (external drive unplugged)** — no write that empties the manifest. Pinned in Task 2 (`testSaveSafelyRefusesWhenFolderUnlistable`).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/Clipr/AdvancedMode/ManifestEditor.swift` | Create | Pure manifest operations + `RemovedStep` |
| `Sources/Clipr/AdvancedMode/SessionManifest.swift` | Modify | `currentVersion`, `isReadOnly`, `saveSafely`, de-dup on load |
| `Sources/Clipr/AdvancedMode/StepFiles.swift` | Create | Companion files; trash/restore with injectable file ops |
| `Sources/Clipr/Editor/ThumbnailCache.swift` | Modify | `remove(_:)` |
| `Sources/Clipr/AdvancedMode/ReviewModel.swift` | Create | Editing state, autosave, undo, selection, banner |
| `Sources/Clipr/Editor/EditorView.swift`, `EditorView+Header.swift`, `EditorWindowController.swift` | Modify | Optional rename (`allowsRename`) |
| `Sources/Clipr/AdvancedMode/ReviewView.swift` | Rewrite | List UI |
| `Sources/Clipr/AdvancedMode/ReviewRow.swift` | Create | One row (thumbnail, caption view/editor, meta, Edit) |
| `Sources/Clipr/AdvancedMode/ReviewWindowController.swift` | Modify | Host model, editor round trip, flush on close |
| `Sources/Clipr/AdvancedMode/AdvancedModeCoordinator.swift` | Modify | New `ReviewWindowController` initializer |
| `docs/superpowers/checklists/advanced-mode-capture-manual.md` | Modify | Review section |
| `Tests/ClipprTests/ManifestEditorTests.swift`, `StepFilesTests.swift`, `ReviewModelTests.swift` | Create | Unit tests |
| `Tests/ClipprTests/SessionManifestTests.swift` | Modify | New store tests |

---

### Task 1: ManifestEditor

**Files:**
- Create: `Sources/Clipr/AdvancedMode/ManifestEditor.swift`
- Test: `Tests/ClipprTests/ManifestEditorTests.swift`

**Interfaces:**
- Consumes: `SessionManifest`, `StepRecord` (existing, `AdvancedMode/SessionManifest.swift`).
- Produces:
  - `struct RemovedStep: Equatable { let record: StepRecord; let index: Int }` (`index` = position in the manifest before removal)
  - `enum ManifestEditor`
    - `static func moving(_ m: SessionManifest, fromOffsets: IndexSet, toOffset: Int) -> SessionManifest` — SwiftUI `onMove` semantics (`toOffset` is an index in the original array before which to insert).
    - `static func settingCaption(_ caption: String?, forStep id: UUID, in m: SessionManifest) -> SessionManifest` — trims; empty → nil.
    - `static func removing(ids: Set<UUID>, from m: SessionManifest) -> (SessionManifest, [RemovedStep])` — removed sorted by ascending `index`.
    - `static func restoring(_ removed: [RemovedStep], into m: SessionManifest) -> SessionManifest` — inserts in ascending original index, clamped to the end.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/ManifestEditorTests.swift
import XCTest
@testable import Clipr

final class ManifestEditorTests: XCTestCase {
    private func manifest(_ names: [String]) -> SessionManifest {
        SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: names.map {
            StepRecord(id: UUID(), file: "\($0).png", kind: .click, caption: $0, clickPoint: nil,
                       zoomFile: nil, appName: nil, capturedAt: Date(timeIntervalSince1970: 0))
        })
    }
    private func files(_ m: SessionManifest) -> [String] { m.steps.map { String($0.file.dropLast(4)) } }

    func testMoveSingleUpAndDown() {
        let m = manifest(["a", "b", "c", "d"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [2], toOffset: 0)), ["c", "a", "b", "d"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0], toOffset: 4)), ["b", "c", "d", "a"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [1], toOffset: 3)), ["a", "c", "b", "d"])
    }

    func testMoveNonContiguousToEnd() {
        let m = manifest(["a", "b", "c", "d", "e"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0, 2], toOffset: 5)), ["b", "d", "e", "a", "c"])
    }

    func testMoveNonContiguousToMiddle() {
        let m = manifest(["a", "b", "c", "d", "e"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0, 4], toOffset: 2)), ["b", "a", "e", "c", "d"])
    }

    func testMoveOutOfRangeIsNoOp() {
        let m = manifest(["a", "b"])
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [5], toOffset: 0), m)
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [0], toOffset: 9), m)
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [], toOffset: 0), m)
    }

    func testSettingCaptionTrimsAndClears() {
        let m = manifest(["a", "b"])
        let id = m.steps[1].id
        XCTAssertEqual(ManifestEditor.settingCaption("  Click **Save**  ", forStep: id, in: m).steps[1].caption, "Click **Save**")
        XCTAssertNil(ManifestEditor.settingCaption("   ", forStep: id, in: m).steps[1].caption)
        XCTAssertNil(ManifestEditor.settingCaption(nil, forStep: id, in: m).steps[1].caption)
        XCTAssertEqual(ManifestEditor.settingCaption("x", forStep: UUID(), in: m), m)  // unknown id
    }

    func testRemoveThenRestoreInterleaved() {
        let m = manifest(["a", "b", "c", "d", "e"])
        let ids: Set<UUID> = [m.steps[1].id, m.steps[3].id, m.steps[4].id]
        let (removedManifest, removed) = ManifestEditor.removing(ids: ids, from: m)
        XCTAssertEqual(files(removedManifest), ["a", "c"])
        XCTAssertEqual(removed.map(\.index), [1, 3, 4])
        XCTAssertEqual(ManifestEditor.restoring(removed, into: removedManifest), m)
    }

    func testRestoreClampsToEnd() {
        let m = manifest(["a", "b", "c"])
        let (shrunk, removed) = ManifestEditor.removing(ids: [m.steps[2].id], from: m)
        let shorter = ManifestEditor.removing(ids: [shrunk.steps[0].id], from: shrunk).0  // now just ["b"]
        XCTAssertEqual(files(ManifestEditor.restoring(removed, into: shorter)), ["b", "c"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ManifestEditorTests`
Expected: compile failure, "cannot find 'ManifestEditor' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/ManifestEditor.swift
import Foundation

/// A step taken out of a manifest, with where it was, so undo can put it back in place.
struct RemovedStep: Equatable {
    let record: StepRecord
    let index: Int
}

/// Edits to a session's step list as pure value transforms. Keeping file access out of here is
/// what lets Review's undo be "swap the old manifest back" and keeps every rule unit-testable.
enum ManifestEditor {
    /// SwiftUI `onMove` semantics: `toOffset` is an index into the original array before which the
    /// moved steps land. Implemented here rather than via SwiftUI's `Array.move` so this file has
    /// no UI dependency.
    static func moving(_ m: SessionManifest, fromOffsets: IndexSet, toOffset: Int) -> SessionManifest {
        let offsets = fromOffsets.filter { $0 < m.steps.count }
        guard !offsets.isEmpty, (0...m.steps.count).contains(toOffset) else { return m }
        var steps = m.steps
        let moving = offsets.map { steps[$0] }
        let before = offsets.filter { $0 < toOffset }.count
        for index in offsets.reversed() { steps.remove(at: index) }
        steps.insert(contentsOf: moving, at: toOffset - before)
        var result = m
        result.steps = steps
        return result
    }

    static func settingCaption(_ caption: String?, forStep id: UUID, in m: SessionManifest) -> SessionManifest {
        guard let index = m.steps.firstIndex(where: { $0.id == id }) else { return m }
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = m
        result.steps[index].caption = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return result
    }

    static func removing(ids: Set<UUID>, from m: SessionManifest) -> (SessionManifest, [RemovedStep]) {
        var removed: [RemovedStep] = []
        var kept: [StepRecord] = []
        for (index, step) in m.steps.enumerated() {
            if ids.contains(step.id) { removed.append(RemovedStep(record: step, index: index)) } else { kept.append(step) }
        }
        var result = m
        result.steps = kept
        return (result, removed)
    }

    /// Inserting in ascending original index restores each step to exactly where it was, because
    /// every earlier removed step has already been put back by the time a later one is inserted.
    static func restoring(_ removed: [RemovedStep], into m: SessionManifest) -> SessionManifest {
        var result = m
        for item in removed.sorted(by: { $0.index < $1.index }) {
            result.steps.insert(item.record, at: min(item.index, result.steps.count))
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ManifestEditorTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/ManifestEditor.swift Tests/ClipprTests/ManifestEditorTests.swift
git commit -m "feat: add pure manifest editing operations for Review"
```

---

### Task 2: Safe manifest store

**Files:**
- Modify: `Sources/Clipr/AdvancedMode/SessionManifest.swift`
- Test: `Tests/ClipprTests/SessionManifestTests.swift` (append)

**Interfaces:**
- Produces on `SessionManifestStore`: `static let currentVersion = 1`; `enum StoreError: Error, Equatable { case folderUnreadable }`; `static func saveSafely(_ m: SessionManifest, in folder: URL) throws`; `static func isReadOnly(_ m: SessionManifest) -> Bool`. `load(from:)` now drops duplicate `file` entries (first wins).

- [ ] **Step 1: Write the failing tests** (append inside `SessionManifestTests`; the class already has `folder`, `touch(_:)`, `record(_:caption:)` helpers)

```swift
    func testSaveSafelyWritesWhenFolderListable() throws {
        touch("Step_01.png")
        let m = SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: [record("Step_01.png", caption: "A")])
        try SessionManifestStore.saveSafely(m, in: folder)
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.first?.caption, "A")
    }

    /// Write-and-search but no read permission: a plain save would succeed here, which is exactly
    /// the case where a manifest built from an empty listing could overwrite real captions.
    func testSaveSafelyRefusesWhenFolderUnlistable() throws {
        touch("Step_01.png")
        try SessionManifestStore.save(SessionManifest(createdAt: Date(), steps: [record("Step_01.png", caption: "keep")]), in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertThrowsError(try SessionManifestStore.saveSafely(SessionManifest(createdAt: Date()), in: folder)) {
            XCTAssertEqual($0 as? SessionManifestStore.StoreError, .folderUnreadable)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.first?.caption, "keep")
    }

    func testLoadDropsDuplicateEntries() throws {
        touch("Step_01.png")
        let m = SessionManifest(createdAt: Date(timeIntervalSince1970: 0),
                                steps: [record("Step_01.png", caption: "first"), record("Step_01.png", caption: "dup")])
        try SessionManifestStore.save(m, in: folder)
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.caption), ["first"])
    }

    func testNewerVersionIsReadOnly() {
        var m = SessionManifest(createdAt: Date())
        XCTAssertFalse(SessionManifestStore.isReadOnly(m))
        m.version = SessionManifestStore.currentVersion + 1
        XCTAssertTrue(SessionManifestStore.isReadOnly(m))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SessionManifestTests`
Expected: compile failure, "type 'SessionManifestStore' has no member 'saveSafely'".

- [ ] **Step 3: Implement** — in `SessionManifestStore`, add after `fileName`:

```swift
    static let currentVersion = 1

    enum StoreError: Error, Equatable { case folderUnreadable }

    /// Review saves after every edit. If the folder can't be listed (permissions changed, an
    /// external drive went away) the in-memory manifest may have been built from an empty listing,
    /// so writing it could erase every caption — refuse instead and let the caller retry.
    static func saveSafely(_ manifest: SessionManifest, in folder: URL) throws {
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else {
            throw StoreError.folderUnreadable
        }
        try save(manifest, in: folder)
    }

    /// A manifest written by a newer Clipr may carry meaning this build doesn't understand, so
    /// Review shows it but never writes it back.
    static func isReadOnly(_ manifest: SessionManifest) -> Bool {
        manifest.version > currentVersion
    }
```

In `load(from:)`, directly after `var manifest = decoded(from: folder) ?? …`, add:

```swift
        // A duplicate entry would show one file twice and make reorder/delete ambiguous.
        var seen = Set<String>()
        manifest.steps = manifest.steps.filter { seen.insert($0.file).inserted }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SessionManifestTests`
Expected: all pass (6 existing + 4 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/SessionManifest.swift Tests/ClipprTests/SessionManifestTests.swift
git commit -m "feat: safe manifest saves, duplicate removal and read-only versions"
```

---

### Task 3: StepFiles and thumbnail cache removal

**Files:**
- Create: `Sources/Clipr/AdvancedMode/StepFiles.swift`
- Modify: `Sources/Clipr/Editor/ThumbnailCache.swift`
- Test: `Tests/ClipprTests/StepFilesTests.swift`

**Interfaces:**
- Consumes: `FilenameGenerator.annotationsName(fromRaw:)`, `.editedName(fromRaw:)`, `.zoomName(fromStep:)`.
- Produces:
  - `struct TrashedStep: Equatable { let file: String; let moves: [Move]; struct Move: Equatable { let original: URL; let trashed: URL } }`
  - `struct StepFiles { var trashItem: (URL) throws -> URL; var moveItem: (URL, URL) throws -> Void; init(trashItem:moveItem:) with live defaults; static func companions(of file: String, in folder: URL) -> [URL]; static func thumbnailURL(of file: String, in folder: URL) -> URL; func trash(_ file: String, in folder: URL) throws -> TrashedStep; func restore(_ trashed: TrashedStep) throws }`
  - `enum StepFilesError: Error, Equatable { case trashedFileMissing(String) }`
  - `ThumbnailCache.remove(_ url: URL)`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/StepFilesTests.swift
import XCTest
@testable import Clipr

final class StepFilesTests: XCTestCase {
    var folder: URL!
    var trash: URL!

    override func setUp() {
        super.setUp()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Session")
        trash = root.appendingPathComponent("Trash")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
    }
    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }
    /// A stand-in Trash so tests never touch the user's real one.
    private var fakeFiles: StepFiles {
        StepFiles(
            trashItem: { [trash] url in
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
    }

    func testCompanionsFindsExistingFilesOnly() {
        touch("Step_03.png"); touch("Step_03_annotations.json"); touch("Step_03_edited.png")
        let names = StepFiles.companions(of: "Step_03.png", in: folder).map(\.lastPathComponent)
        XCTAssertEqual(Set(names), ["Step_03.png", "Step_03_annotations.json", "Step_03_edited.png"])
        touch("Step_03_zoom.png")
        XCTAssertEqual(StepFiles.companions(of: "Step_03.png", in: folder).count, 4)
    }

    func testThumbnailPrefersEdited() {
        touch("Step_01.png")
        XCTAssertEqual(StepFiles.thumbnailURL(of: "Step_01.png", in: folder).lastPathComponent, "Step_01.png")
        touch("Step_01_edited.png")
        XCTAssertEqual(StepFiles.thumbnailURL(of: "Step_01.png", in: folder).lastPathComponent, "Step_01_edited.png")
    }

    func testTrashAndRestoreRoundTrip() throws {
        touch("Step_02.png"); touch("Step_02_annotations.json"); touch("Step_02_zoom.png")
        let trashed = try fakeFiles.trash("Step_02.png", in: folder)
        XCTAssertEqual(trashed.moves.count, 3)
        XCTAssertFalse(exists("Step_02.png")); XCTAssertFalse(exists("Step_02_zoom.png"))
        try fakeFiles.restore(trashed)
        XCTAssertTrue(exists("Step_02.png")); XCTAssertTrue(exists("Step_02_annotations.json")); XCTAssertTrue(exists("Step_02_zoom.png"))
    }

    func testTrashFailsWhenRawCannotMove() {
        touch("Step_04.png")
        let failing = StepFiles(trashItem: { _ in throw CocoaError(.fileWriteNoPermission) }, moveItem: { _, _ in })
        XCTAssertThrowsError(try failing.trash("Step_04.png", in: folder))
        XCTAssertTrue(exists("Step_04.png"))
    }

    func testRestoreFailsCleanlyWhenTrashedFileIsGone() throws {
        touch("Step_05.png"); touch("Step_05_zoom.png")
        let trashed = try fakeFiles.trash("Step_05.png", in: folder)
        try FileManager.default.removeItem(at: trashed.moves[0].trashed)  // "Trash emptied"
        XCTAssertThrowsError(try fakeFiles.restore(trashed)) {
            XCTAssertEqual($0 as? StepFilesError, .trashedFileMissing("Step_05.png"))
        }
        XCTAssertFalse(exists("Step_05.png")); XCTAssertFalse(exists("Step_05_zoom.png"))  // nothing half-restored
    }

    func testThumbnailCacheRemove() {
        let url = folder.appendingPathComponent("x.png")
        ThumbnailCache.shared.store(NSImage(size: CGSize(width: 2, height: 2)), for: url)
        XCTAssertNotNil(ThumbnailCache.shared.image(for: url))
        ThumbnailCache.shared.remove(url)
        XCTAssertNil(ThumbnailCache.shared.image(for: url))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter StepFilesTests`
Expected: compile failure, "cannot find 'StepFiles' in scope".

- [ ] **Step 3: Implement**

In `ThumbnailCache.swift`, after `store(_:for:)`:

```swift
    /// Review drops a step's entry after the image editor closes, so the edited image is decoded
    /// again instead of the stale one being shown.
    func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
```

```swift
// Sources/Clipr/AdvancedMode/StepFiles.swift
import Foundation

enum StepFilesError: Error, Equatable {
    case trashedFileMissing(String)
}

/// Where a step's files went when it was deleted, so undo can move them back.
struct TrashedStep: Equatable {
    struct Move: Equatable {
        let original: URL
        let trashed: URL
    }
    let file: String
    let moves: [Move]
}

/// Every file that belongs to one step, and moving them to and from the Trash together. The file
/// operations are injected so tests never touch the user's real Trash.
struct StepFiles {
    var trashItem: (URL) throws -> URL
    var moveItem: (URL, URL) throws -> Void

    init(
        trashItem: @escaping (URL) throws -> URL = StepFiles.liveTrash,
        moveItem: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) {
        self.trashItem = trashItem
        self.moveItem = moveItem
    }

    static func liveTrash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }

    /// The raw PNG first, then whichever of its sidecar, zoom crop and edited preview exist.
    static func companions(of file: String, in folder: URL) -> [URL] {
        let names = [
            file,
            FilenameGenerator.annotationsName(fromRaw: file),
            FilenameGenerator.zoomName(fromStep: file),
            FilenameGenerator.editedName(fromRaw: file),
        ]
        return names
            .map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The edited preview when there is one, so annotations added in the editor show in Review.
    static func thumbnailURL(of file: String, in folder: URL) -> URL {
        let edited = folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: file))
        return FileManager.default.fileExists(atPath: edited.path) ? edited : folder.appendingPathComponent(file)
    }

    /// The raw PNG must move or the whole step stays put (a step without its image would be a
    /// manifest entry pointing at nothing). Companions are best-effort: one stuck sidecar must not
    /// block deleting the step.
    func trash(_ file: String, in folder: URL) throws -> TrashedStep {
        let urls = Self.companions(of: file, in: folder)
        guard let raw = urls.first, raw.lastPathComponent == file else {
            throw CocoaError(.fileNoSuchFile)
        }
        var moves = [TrashedStep.Move(original: raw, trashed: try trashItem(raw))]
        for url in urls.dropFirst() {
            if let trashed = try? trashItem(url) {
                moves.append(TrashedStep.Move(original: url, trashed: trashed))
            }
        }
        return TrashedStep(file: file, moves: moves)
    }

    /// All-or-nothing: if any trashed file is gone (the Trash was emptied) nothing is moved back,
    /// so a restored manifest entry never points at a missing image.
    func restore(_ trashed: TrashedStep) throws {
        for move in trashed.moves where !FileManager.default.fileExists(atPath: move.trashed.path) {
            throw StepFilesError.trashedFileMissing(trashed.file)
        }
        for move in trashed.moves {
            try moveItem(move.trashed, move.original)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StepFilesTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/StepFiles.swift Sources/Clipr/Editor/ThumbnailCache.swift Tests/ClipprTests/StepFilesTests.swift
git commit -m "feat: move a step's files to and from the Trash together"
```

---

### Task 4: ReviewModel

**Files:**
- Create: `Sources/Clipr/AdvancedMode/ReviewModel.swift`
- Test: `Tests/ClipprTests/ReviewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3; `SessionManifestStore.load(from:)`.
- Produces: `@MainActor final class ReviewModel: ObservableObject` with
  - `@Published private(set) var manifest: SessionManifest`, `@Published var selection: Set<UUID>`, `@Published private(set) var banner: String?`, `@Published private(set) var refreshToken: Int`
  - `let folder: URL`, `let isReadOnly: Bool`, `let undoManager: UndoManager`
  - `init(folder: URL, files: StepFiles = StepFiles(), save: @escaping (SessionManifest, URL) throws -> Void = SessionManifestStore.saveSafely, captionDelay: TimeInterval = 0.5)`
  - `func url(for step: StepRecord) -> URL`, `func thumbnailURL(for step: StepRecord) -> URL`
  - `func move(fromOffsets: IndexSet, toOffset: Int)`, `func moveSelection(by delta: Int)`
  - `func editCaption(_ text: String?, for id: UUID)` (debounced), `func commitCaption(_ text: String?, for id: UUID)` (immediate), `func flushPendingCaption()`
  - `func deleteSelection()`, `func delete(ids: Set<UUID>)`
  - `func reload()` (re-read from disk, prune selection, bump `refreshToken`)
  - `var readOnlyNotice: String?` ("Made by a newer version of Clipr — read only" when `isReadOnly`)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/ReviewModelTests.swift
import XCTest
@testable import Clipr

@MainActor
final class ReviewModelTests: XCTestCase {
    var root: URL!
    var folder: URL!
    var trash: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Session")
        trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var steps: [StepRecord] = []
        for (i, name) in ["a", "b", "c", "d"].enumerated() {
            let file = String(format: "Step_%02d.png", i + 1)
            FileManager.default.createFile(atPath: folder.appendingPathComponent(file).path, contents: Data([1]))
            steps.append(StepRecord(id: UUID(), file: file, kind: .click, caption: name, clickPoint: nil,
                                    zoomFile: nil, appName: "Safari", capturedAt: Date(timeIntervalSince1970: 0)))
        }
        try SessionManifestStore.save(SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: steps), in: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var fakeFiles: StepFiles {
        StepFiles(
            trashItem: { [trash] url in
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
    }

    private func makeModel(captionDelay: TimeInterval = 0.05, save: ((SessionManifest, URL) throws -> Void)? = nil) -> ReviewModel {
        ReviewModel(folder: folder, files: fakeFiles, save: save ?? SessionManifestStore.saveSafely, captionDelay: captionDelay)
    }
    private func captions(_ m: SessionManifest) -> [String?] { m.steps.map(\.caption) }
    private var onDisk: SessionManifest { SessionManifestStore.load(from: folder) }

    func testMovePersistsAndUndoRedo() {
        let model = makeModel()
        model.move(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(captions(onDisk), ["d", "a", "b", "c"])
        XCTAssertEqual(model.undoManager.undoActionName, "Move Steps")
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
        model.undoManager.redo()
        XCTAssertEqual(captions(onDisk), ["d", "a", "b", "c"])
    }

    func testMoveKeepsSelectionByID() {
        let model = makeModel()
        let ids = [model.manifest.steps[0].id, model.manifest.steps[2].id]
        model.selection = Set(ids)
        model.move(fromOffsets: [0, 2], toOffset: 4)
        XCTAssertEqual(model.selection, Set(ids))
        XCTAssertEqual(captions(model.manifest), ["b", "d", "a", "c"])
    }

    func testMoveSelectionByOne() {
        let model = makeModel()
        model.selection = [model.manifest.steps[1].id]
        model.moveSelection(by: -1)
        XCTAssertEqual(captions(onDisk), ["b", "a", "c", "d"])
        model.moveSelection(by: -1)  // already first: no-op
        XCTAssertEqual(captions(onDisk), ["b", "a", "c", "d"])
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(captions(onDisk), ["a", "c", "b", "d"])
    }

    func testCaptionDebounceWritesOnceAfterPause() async throws {
        var writes = 0
        let model = makeModel(captionDelay: 0.2, save: { m, f in writes += 1; try SessionManifestStore.saveSafely(m, in: f) })
        let id = model.manifest.steps[0].id
        model.editCaption("x", for: id)
        model.editCaption("xy", for: id)
        model.editCaption("xyz", for: id)
        XCTAssertEqual(writes, 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(onDisk.steps[0].caption, "xyz")
        XCTAssertEqual(model.undoManager.undoActionName, "Edit Caption")
        model.undoManager.undo()
        XCTAssertEqual(onDisk.steps[0].caption, "a")
    }

    func testCommitCaptionIsImmediateAndEmptyClears() {
        let model = makeModel(captionDelay: 10)
        let id = model.manifest.steps[1].id
        model.commitCaption("  ", for: id)
        XCTAssertNil(onDisk.steps[1].caption)
    }

    func testUnchangedCaptionRegistersNoUndo() {
        let model = makeModel()
        model.commitCaption("a", for: model.manifest.steps[0].id)
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testFlushPendingCaptionSavesImmediately() {
        let model = makeModel(captionDelay: 10)
        let id = model.manifest.steps[2].id
        model.editCaption("typed", for: id)
        model.flushPendingCaption()
        XCTAssertEqual(onDisk.steps[2].caption, "typed")
    }

    func testDeleteTrashesFilesAndUndoRestores() {
        let model = makeModel()
        FileManager.default.createFile(atPath: folder.appendingPathComponent("Step_02_zoom.png").path, contents: Data([1]))
        model.selection = [model.manifest.steps[1].id]
        model.deleteSelection()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02_zoom.png").path))
        XCTAssertEqual(model.selection, [model.manifest.steps[1].id])  // the step now at the deleted position
        XCTAssertEqual(model.undoManager.undoActionName, "Delete Steps")
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02_zoom.png").path))
        model.undoManager.redo()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
    }

    func testDeleteAllThenUndoRestoresEverything() {
        let model = makeModel()
        model.selection = Set(model.manifest.steps.map(\.id))
        model.deleteSelection()
        XCTAssertTrue(model.manifest.steps.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
    }

    func testPartialTrashFailureKeepsFailedStepAndShowsBanner() {
        var calls = 0
        let flaky = StepFiles(
            trashItem: { [trash] url in
                calls += 1
                if url.lastPathComponent == "Step_03.png" { throw CocoaError(.fileWriteNoPermission) }
                let dest = trash!.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
        let model = ReviewModel(folder: folder, files: flaky, captionDelay: 0.05)
        model.selection = [model.manifest.steps[1].id, model.manifest.steps[2].id]
        model.deleteSelection()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
        XCTAssertEqual(model.banner, "Couldn't move Step_03.png to the Trash")
    }

    func testUndoDeleteSkipsStepWhoseFilesLeftTheTrash() throws {
        let model = makeModel()
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        for item in try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)  // "Empty Trash"
        }
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["b", "c", "d"])
        XCTAssertEqual(model.banner, "Couldn't restore Step_01.png — it's no longer in the Trash")
    }

    func testSaveFailureShowsBannerAndRetries() {
        var fail = true
        let model = makeModel(save: { m, f in if fail { throw CocoaError(.fileWriteUnknown) }; try SessionManifestStore.saveSafely(m, in: f) })
        model.move(fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])  // disk untouched
        fail = false
        model.move(fromOffsets: [0], toOffset: 2)
        XCTAssertNil(model.banner)
        XCTAssertEqual(captions(onDisk), captions(model.manifest))
    }

    func testReadOnlyBlocksEdits() throws {
        var m = SessionManifestStore.load(from: folder)
        m.version = SessionManifestStore.currentVersion + 1
        try SessionManifestStore.save(m, in: folder)
        let model = makeModel()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(model.readOnlyNotice, "Made by a newer version of Clipr — read only")
        model.move(fromOffsets: [0], toOffset: 4)
        model.commitCaption("x", for: model.manifest.steps[0].id)
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        XCTAssertEqual(captions(model.manifest), ["a", "b", "c", "d"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_01.png").path))
    }

    func testReloadPicksUpExternalChangesAndBumpsToken() throws {
        let model = makeModel()
        let before = model.refreshToken
        model.selection = [model.manifest.steps[3].id]
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Step_04.png"))
        model.reload()
        XCTAssertEqual(captions(model.manifest), ["a", "b", "c"])
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.refreshToken, before + 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ReviewModelTests`
Expected: compile failure, "cannot find 'ReviewModel' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/ReviewModel.swift
import Foundation

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
    let isReadOnly: Bool
    let undoManager = UndoManager()

    private let files: StepFiles
    private let save: (SessionManifest, URL) throws -> Void
    private let captionDelay: TimeInterval
    private var pendingCaption: (id: UUID, text: String?)?
    private var captionWork: DispatchWorkItem?

    var readOnlyNotice: String? { isReadOnly ? "Made by a newer version of Clipr — read only" : nil }

    init(
        folder: URL,
        files: StepFiles = StepFiles(),
        save: @escaping (SessionManifest, URL) throws -> Void = SessionManifestStore.saveSafely,
        captionDelay: TimeInterval = 0.5
    ) {
        self.folder = folder
        self.files = files
        self.save = save
        self.captionDelay = captionDelay
        let loaded = SessionManifestStore.load(from: folder)
        manifest = loaded
        isReadOnly = SessionManifestStore.isReadOnly(loaded)
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

    /// Called on every keystroke; saves once typing pauses.
    func editCaption(_ text: String?, for id: UUID) {
        guard !isReadOnly else { return }
        pendingCaption = (id, text)
        captionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPendingCaption() }
        captionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + captionDelay, execute: work)
    }

    /// Return or focus loss: save now, superseding any pending typing save for this step.
    func commitCaption(_ text: String?, for id: UUID) {
        guard !isReadOnly else { return }
        captionWork?.cancel()
        pendingCaption = nil
        applyCaption(text, for: id)
    }

    /// Window close calls this so a caption typed in the last half-second isn't lost.
    func flushPendingCaption() {
        captionWork?.cancel()
        captionWork = nil
        guard let pending = pendingCaption else { return }
        pendingCaption = nil
        applyCaption(pending.text, for: pending.id)
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
        var trashed: [UUID: TrashedStep] = [:]
        var failed: [String] = []
        for step in manifest.steps where ids.contains(step.id) {
            do { trashed[step.id] = try files.trash(step.file, in: folder) } catch { failed.append(step.file) }
        }
        guard !trashed.isEmpty else {
            banner = failed.first.map { "Couldn't move \($0) to the Trash" }
            return
        }
        let firstIndex = manifest.steps.firstIndex { trashed[$0.id] != nil } ?? 0
        let (updated, removed) = ManifestEditor.removing(ids: Set(trashed.keys), from: manifest)
        manifest = updated
        persist()
        if let failure = failed.first { banner = "Couldn't move \(failure) to the Trash" }
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
        manifest = ManifestEditor.restoring(restored, into: manifest)
        persist()
        if let first = missing.first { banner = "Couldn't restore \(first) — it's no longer in the Trash" }
        selection = Set(restored.map(\.record.id))
        let ids = Set(restored.map(\.record.id))
        registerUndo("Delete Steps") { $0.delete(ids: ids) }
    }

    // MARK: Reload

    /// After the image editor closes (it may have changed or deleted the step's image), re-read the
    /// session from disk and make rows decode their thumbnails again.
    func reload() {
        flushPendingCaption()
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
        manifest = new
        persist()
        registerUndo(actionName) { $0.replace(with: old, actionName: actionName) }
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

    private func persist() {
        guard !isReadOnly else { return }
        do {
            try save(manifest, folder)
            banner = nil
        } catch {
            banner = "Couldn't save changes — will retry"
        }
    }
}
```

Notes for the implementer:
- `testDeleteTrashesFilesAndUndoRestores` expects selection to land on the step now at the deleted position.
- `persist()` clears the banner on success; in `delete`, the trash-failure banner is set *after* `persist()` so it isn't immediately cleared.
- Undo uses explicit groups (`groupsByEvent = false` + `registerUndo`). `testMovePersistsAndUndoRedo` proves one undo reverts exactly one move; if redo registration during undo raises "no open group", wrap the handler body in `beginUndoGrouping`/`endUndoGrouping` only when `isUndoing || isRedoing` is false — do not switch back to event grouping.

- [ ] **Step 4: Run tests**

Run: `swift test --filter ReviewModelTests`
Expected: 14 tests pass. Run it 3 times; it must pass every time (timing-based caption test).

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/ReviewModel.swift Tests/ClipprTests/ReviewModelTests.swift
git commit -m "feat: Review model with autosave, undo and Trash-backed delete"
```

---

### Task 5: Optional rename in the image editor

**Files:**
- Modify: `Sources/Clipr/Editor/EditorView.swift:112`, `Sources/Clipr/Editor/EditorView+Header.swift` (`filename`, `beginRename`, `commitRename`), `Sources/Clipr/Editor/EditorWindowController.swift` (init + `onRename:` wiring at ~line 162)

**Interfaces:**
- Produces: `EditorWindowController.init(image:rawURL:storage:settings:allowsRename: Bool = true)`; `EditorView.onRename` becomes `((URL, String, [AnnotationObject]) -> Void)?` (nil = rename unavailable).

- [ ] **Step 1: Implement**

In `EditorView.swift` change line 112 to:

```swift
    /// `nil` when renaming isn't allowed — Review opens steps whose filenames `session.json`
    /// refers to, so renaming one there would orphan its caption.
    let onRename: ((URL, String, [AnnotationObject]) -> Void)?
```

In `EditorView+Header.swift`, in the non-editing branch of `filename`, make the tap and help conditional:

```swift
            Text(currentURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(EditorColors.t1)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { if onRename != nil { beginRename() } }
                .help(onRename != nil ? "Click to rename this capture" : "")
```

In `beginRename()`, add a first line `guard onRename != nil else { return }`. In `commitRename()`, replace `onRename(currentURL, trimmed, annotations)` with `onRename?(currentURL, trimmed, annotations)`.

In `EditorWindowController.swift`: add `private let allowsRename: Bool` stored property; init signature `init(image: NSImage, rawURL: URL, storage: StorageManager, settings: SettingsStore = SettingsStore(), allowsRename: Bool = true)` setting `self.allowsRename = allowsRename` before `super.init`; change the wiring to:

```swift
            onRename: allowsRename ? { [weak self] url, newName, annotations in self?.rename(url, to: newName, annotations: annotations) } : nil,
```

Search for any other call of `onRename(` (`grep -rn "onRename(" Sources Tests`) and make it optional-call too. If any test constructs `EditorView` directly, it keeps compiling (the closure literal converts to the optional type).

- [ ] **Step 2: Build and test**

Run: `swift build && swift test`
Expected: build clean; full suite passes.

- [ ] **Step 3: Commit**

```bash
git add Sources/Clipr/Editor/EditorView.swift Sources/Clipr/Editor/EditorView+Header.swift Sources/Clipr/Editor/EditorWindowController.swift
git commit -m "feat: allow opening the image editor with rename disabled"
```

---

### Task 6: Review list UI and window wiring

**Files:**
- Rewrite: `Sources/Clipr/AdvancedMode/ReviewView.swift`
- Create: `Sources/Clipr/AdvancedMode/ReviewRow.swift`
- Modify: `Sources/Clipr/AdvancedMode/ReviewWindowController.swift`, `Sources/Clipr/AdvancedMode/AdvancedModeCoordinator.swift:95`

**Interfaces:**
- Consumes: `ReviewModel` (Task 4), `EditorWindowController(…, allowsRename: false)` (Task 5), `ThumbnailView(url:contentMode:)` (existing), `ThumbnailCache.shared.remove` (Task 3), `StepFiles.companions` (Task 3).
- Produces: `ReviewWindowController.init(sessionFolder: URL, storage: StorageManager)` (replaces the `manifest:` initializer); `present()` unchanged.

No unit tests (SwiftUI); verified by build, full suite, and a screenshot check (Step 4).

- [ ] **Step 1: ReviewRow**

```swift
// Sources/Clipr/AdvancedMode/ReviewRow.swift
import SwiftUI

/// One step in the Review list: number, thumbnail, caption (rendered, or an inline editor) and
/// the step's app and kind.
struct ReviewRow: View {
    let number: Int
    let step: StepRecord
    @ObservedObject var model: ReviewModel
    @Binding var editingID: UUID?
    let onOpenEditor: (StepRecord) -> Void

    @State private var draft = ""
    /// The caption when editing began — Esc puts this back even if a debounced save already landed.
    @State private var originalCaption: String?
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { editingID == step.id }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                .padding(.top, 4)

            Color.black.opacity(0.25)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .frame(width: 200)
                .overlay(
                    ThumbnailView(url: model.thumbnailURL(for: step), contentMode: .fit)
                        // New identity after the editor closes so the edited image is decoded.
                        .id("\(step.id)-\(model.refreshToken)")
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture(count: 2) { onOpenEditor(step) }
                .help("Double-click to edit the image")

            VStack(alignment: .leading, spacing: 6) {
                caption
                HStack(spacing: 6) {
                    if let app = step.appName {
                        Text(app)
                    }
                    Text(kindLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Edit") { onOpenEditor(step) }
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .onChange(of: editingID) { _, newValue in
            if newValue == step.id {
                originalCaption = step.caption
                draft = step.caption ?? ""
                fieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if isEditing {
            TextField("Add a caption", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onChange(of: draft) { _, text in model.editCaption(text, for: step.id) }
                .onSubmit { finishEditing(commit: true) }
                .onExitCommand { finishEditing(commit: false) }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { finishEditing(commit: true) }
                }
        } else {
            Group {
                if let text = step.caption,
                   let rendered = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(rendered)
                } else {
                    Text("Add a caption").foregroundStyle(.tertiary)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !model.isReadOnly { editingID = step.id } }
        }
    }

    /// Esc restores the caption as it was before editing began — including undoing any debounced
    /// save that already landed while typing.
    private func finishEditing(commit: Bool) {
        editingID = nil
        model.commitCaption(commit ? draft : originalCaption, for: step.id)
    }

    private var kindLabel: String {
        switch step.kind {
        case .click: return "Click"
        case .typing: return "Typing"
        case .manual: return "Manual"
        }
    }
}
```

- [ ] **Step 2: ReviewView**

```swift
// Sources/Clipr/AdvancedMode/ReviewView.swift
import SwiftUI

struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    let onOpenEditor: (StepRecord) -> Void
    let onShowInFinder: () -> Void

    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.banner ?? model.readOnlyNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
            }
            header
            Divider()
            if model.manifest.steps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No steps — press ⌘Z to undo").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(shortcuts)
    }

    private var header: some View {
        HStack {
            Text(model.manifest.steps.count == 1 ? "1 step" : "\(model.manifest.steps.count) steps")
                .font(.headline)
            if model.selection.count > 1 {
                Text("· \(model.selection.count) selected").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete Selected", role: .destructive) { model.deleteSelection() }
                .disabled(model.selection.isEmpty || model.isReadOnly)
            Button("Show in Finder", action: onShowInFinder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(Array(model.manifest.steps.enumerated()), id: \.element.id) { index, step in
                ReviewRow(number: index + 1, step: step, model: model, editingID: $editingID, onOpenEditor: onOpenEditor)
                    .tag(step.id)
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            .moveDisabled(model.isReadOnly)
        }
        .listStyle(.inset)
        .onDeleteCommand { if editingID == nil { model.deleteSelection() } }
        .onKeyPress(.return) {
            guard editingID == nil, !model.isReadOnly, model.selection.count == 1, let id = model.selection.first else { return .ignored }
            editingID = id
            return .handled
        }
    }

    /// Keyboard commands Clipr's main menu doesn't provide. Disabled while a caption is being
    /// edited so ⌘Z there undoes typing and ⌥↑ moves the text cursor, not the step.
    private var shortcuts: some View {
        Group {
            Button("") { model.undoManager.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editingID != nil)
            Button("") { model.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editingID != nil)
            Button("") { model.moveSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: .option)
                .disabled(editingID != nil || model.isReadOnly)
            Button("") { model.moveSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: .option)
                .disabled(editingID != nil || model.isReadOnly)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
```

(Undo/redo enablement isn't tied to `canUndo`: those aren't published, and calling `undo()` with nothing to undo is harmless.)

- [ ] **Step 3: ReviewWindowController + coordinator**

Replace the body of `ReviewWindowController.swift` with:

```swift
import Cocoa
import SwiftUI

final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private let storage: StorageManager
    private let model: ReviewModel
    // Keeps each opened EditorWindowController alive until it finishes; without this,
    // the local `editor` in openEditor(for:) would be deallocated as soon as that
    // function returns, silently breaking its Done/Discard closures (which capture
    // `[weak self]` on the editor controller).
    private var openEditors: [EditorWindowController] = []
    var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    @MainActor
    init(sessionFolder: URL, storage: StorageManager) {
        self.storage = storage
        model = ReviewModel(folder: sessionFolder)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review — \(sessionFolder.lastPathComponent)"
        window.minSize = NSSize(width: 560, height: 400)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReviewView(
            model: model,
            onOpenEditor: { [weak self] step in self?.openEditor(for: step) },
            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Clipr is a menu-bar (accessory) app, so a plain `showWindow` can open the Review window
    /// behind whatever app the user was just recording — activate so it actually comes forward.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// A caption typed in the last half-second must still be saved.
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { model.flushPendingCaption() }
    }

    private func openEditor(for step: StepRecord) {
        let url = model.url(for: step)
        guard let image = NSImage(contentsOf: url) else { return }
        // Rename disabled: session.json refers to steps by filename.
        let editor = EditorWindowController(image: image, rawURL: url, storage: storage, allowsRename: false)
        openEditors.append(editor)
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0 === editor }
            MainActor.assumeIsolated {
                let folder = self.model.folder
                // Drop every cached decode for this step so the row shows the edited image.
                for companion in StepFiles.companions(of: step.file, in: folder) {
                    ThumbnailCache.shared.remove(companion)
                }
                ThumbnailCache.shared.remove(folder.appendingPathComponent(step.file))
                self.model.reload()
            }
        }
        editor.showWindow(nil)
    }
}
```

In `AdvancedModeCoordinator.swift`, change the construction in `openReview` to `ReviewWindowController(sessionFolder: sessionFolder, storage: storage)` (the manifest parameter of `openReview` may stay for its callers' empty-check; just stop passing it on). The coordinator is always called on the main thread; if the compiler rejects calling the `@MainActor` initializer, wrap that one call in `MainActor.assumeIsolated { … }`.

- [ ] **Step 4: Build, test, and look at it**

Run: `swift build && swift test`
Expected: clean build; full suite passes.

Then rebuild and screenshot the Review window on the most recent session:

```bash
osascript -e 'quit app "Clipr"'; sleep 1; ./Scripts/build-app.sh && open Clipr.app && sleep 2
osascript -e 'tell application "System Events" to tell process "Clipr"
click menu bar item 1 of menu bar 2
delay 0.5
click menu item "Review Last Session…" of menu 1 of menu bar item 1 of menu bar 2
end tell'
```

Capture it with `screencapture -x -o -l <windowID>` (find the window ID with `CGWindowListCopyWindowInfo` filtered on owner "Clipr" and a name starting "Review") and check: rows aligned, numbers 1…N, thumbnails same size, captions rendered with bold, kind badges, Edit buttons right-aligned. Fix layout issues before committing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/ReviewView.swift Sources/Clipr/AdvancedMode/ReviewRow.swift Sources/Clipr/AdvancedMode/ReviewWindowController.swift Sources/Clipr/AdvancedMode/AdvancedModeCoordinator.swift
git commit -m "feat: Review as an editable list with reorder, captions and delete"
```

---

### Task 7: Checklist and final verification

**Files:**
- Modify: `docs/superpowers/checklists/advanced-mode-capture-manual.md`

- [ ] **Step 1: Append a Review section**

```markdown
## Review
- [ ] Steps are listed top to bottom, numbered 1…N, thumbnails the same size.
- [ ] Drag a step to a new position → numbers update; reopen Review → order kept.
- [ ] Select two non-adjacent steps (⌘-click) and drag them → both move, in order.
- [ ] ⌥↑ / ⌥↓ move the selected step one place.
- [ ] Click a caption → edit it; Return saves; reopen Review → new caption shown.
- [ ] Type `**Save**` in a caption → shows bold after Return.
- [ ] Esc while editing a caption → original caption back.
- [ ] Empty a caption and press Return → "Add a caption" placeholder.
- [ ] Select a step, press ⌫ → it disappears; its PNG, zoom and annotations files are in the Trash.
- [ ] ⌘Z → the step is back in the same place with its files; ⇧⌘Z deletes it again.
- [ ] ⌘A then ⌫ → "No steps — press ⌘Z to undo"; ⌘Z brings them all back.
- [ ] Edit a step's image (Edit button) and close the editor → its thumbnail shows the changes.
- [ ] In an editor opened from Review, clicking the filename does not start a rename.
- [ ] Hand-edit `session.json` "version" to 2, open Review → read-only notice; no drag/edit/delete.
```

- [ ] **Step 2: Full verification**

Run: `swift build && swift test && ./Scripts/build-app.sh`
Expected: clean build; full suite passes; "Built Clipr.app". Do not stage `Clipr.app`.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/checklists/advanced-mode-capture-manual.md
git commit -m "docs: manual checklist for Review upgrades"
```
