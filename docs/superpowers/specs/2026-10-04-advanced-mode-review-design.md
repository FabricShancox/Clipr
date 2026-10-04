# Advanced Mode Review Upgrades — Design

Date: 2026-10-04
Status: Approved (design), pending spec review
Sub-project 2 of 3 (1: Capture — shipped; 3: Export — next).

## Context and intent

Advanced Mode sessions exist to become **how-to guides**. Review is where a raw recording turns
into a clean guide: put steps in the right order, write proper captions, drop junk steps (blank
or mid-animation captures). Today Review is a read-only grid with per-step Edit/Delete; Delete
removes only the PNG and leaves the manifest, sidecar and zoom behind.

Success: a user can reorder, recaption and prune a session entirely inside Review, every change
persists to `session.json` immediately, every change is undoable, and nothing is permanently
destroyed by a mis-click.

## Decisions

- **Layout:** a vertical list (one row per step, reads like the finished guide), replacing the
  grid.
- **Persistence:** autosave with undo. Every edit writes `session.json`; caption typing saves
  after a 0.5 s pause. ⌘Z / ⇧⌘Z undo/redo reorder, caption and delete.
- **Delete:** moves the step's files to the macOS Trash (recoverable), no confirmation dialog.
- **Order lives in the manifest only:** step files keep their names (`Step_03.png` may become
  the 1st step). Displayed step numbers are positions.
- **Out of scope here:** export of any kind (sub-project 3 reuses this sub-project's
  selection model).

## Architecture

| Unit | Kind | Responsibility |
|---|---|---|
| `ManifestEditor` | Pure | Value-type operations on `SessionManifest`: `moving(fromOffsets:toOffset:)`, `settingCaption(_:forStep:)`, `removing(ids:) -> (SessionManifest, [RemovedStep])`, `restoring(_ removed: [RemovedStep])`. `RemovedStep` = record + original index. Out-of-range input is a no-op. |
| `SessionManifestStore` (extended) | IO | `saveSafely(_:in:) throws` — refuses (throws `.folderUnreadable`) if the folder listing fails, so a transient read error can never persist an emptied manifest. `load` de-duplicates entries by `file` (first wins). `load` reports `isReadOnly` when `version > currentVersion` (current = 1). |
| `StepFiles` | IO, injectable trash | For a step file: companions = raw PNG, `_annotations.json`, `_zoom.png`, `_edited.png` (those that exist). `trash(step) throws -> TrashedStep` (records each original→trashed URL, via `FileManager.trashItem`). `restore(_ trashed:) throws` moves them back; throws `.trashedFileMissing` if any is gone. Trash function is injected for tests. |
| `ReviewModel` | `ObservableObject`, main actor | Owns `manifest`, `folder`, `selection: Set<UUID>`, `isReadOnly`, `banner: String?`. Every mutation: apply `ManifestEditor` → `saveSafely` → register undo with the window's `UndoManager`. Caption commits debounced 0.5 s (flushed on window close). |
| `ReviewView` (rewrite) | SwiftUI | `List(selection:)` with `.onMove` and `.onDeleteCommand`; row = number badge, 16:10 thumbnail (~200 pt), rendered caption / inline editor, app name + kind badge, Edit button. Toolbar: selection count, Delete Selected, Show in Finder. Banner area at the top. Empty state. |
| `ReviewWindowController` | AppKit | Hosts the view, supplies the window's `UndoManager` to the model, opens editors, refreshes a row when its editor closes, flushes pending caption save on close. |

### Editor interaction

- Thumbnails prefer `_edited.png` when present (so annotations added in the editor show in
  Review). On editor close, `ThumbnailCache` entries for that step's raw and edited URLs are
  invalidated (new `ThumbnailCache.remove(_:)`) and the row reloads.
- Rename is disabled for editors opened from Review (`EditorWindowController` gains an
  `allowsRename: Bool = true` parameter; Review passes false). Renaming would break the
  manifest's file reference; captions replace filenames as the human-facing label.

## Behaviour

### Row

- Leading: step number (1-based position) in a small circle.
- Thumbnail: 16:10 box, image fitted, dark backing, rounded corners; double-click opens editor.
- Caption: displayed via `AttributedString(markdown:)` (so `**bold**` renders and part 1's `\*`
  / `\"` escapes display correctly). Placeholder "Add a caption" in secondary colour when nil.
  Click the caption, or press Return with exactly one row selected, to edit the raw text in a
  multi-line `TextField` (bold via `**…**`). Return commits, Esc cancels, focus loss commits.
  An empty commit stores nil.
- Secondary line: app name (if any) · kind badge (Click / Typing / Manual).
- Trailing: Edit button.

### Interactions

| Action | Input |
|---|---|
| Select | Click; Shift-click range; ⌘-click toggle; ⌘A all |
| Reorder | Drag rows (multi-row supported); ⌥↑ / ⌥↓ moves the selection up/down one place |
| Delete | ⌫ or Delete Selected — no confirmation (undoable; files go to Trash) |
| Undo / Redo | ⌘Z / ⇧⌘Z for reorder, caption and delete; action names "Move Steps", "Edit Caption", "Delete Steps" |
| Edit image | Edit button or thumbnail double-click |

Selection survives moves (it is by step ID). After a delete, selection moves to the step now at
the first deleted position (or the last step).

### Empty and read-only states

- All steps deleted: empty state "No steps — press ⌘Z to undo". Folder is kept.
- Newer-version manifest: banner "Made by a newer version of Clipr — read only"; reorder,
  caption editing and delete disabled; Edit (image editor) still allowed.

### Window

760 × 640 default, 560 × 400 minimum, resizable; title unchanged ("Review — Session_…").

## Error handling

| Failure | Behaviour |
|---|---|
| `saveSafely` throws (write error or unreadable folder) | Banner "Couldn't save changes — will retry"; in-memory state kept; next edit (and window close) retries; banner clears on success. File on disk untouched. |
| Trash fails for a step | That step stays (not removed from manifest); banner names it; other selected steps still delete; undo covers only the ones removed. |
| Undo of delete but a trashed file is gone (Trash emptied) | Restore skipped for that step with a banner; manifest unchanged for it, so no entry ever points at a missing file. |
| Step file removed outside Clipr while open | Next reload (editor close / save) reconciles via `load`; the missing step disappears. |
| Newer manifest version | Read-only as above; never written. |

## Testing

Unit (XCTest):

- `ManifestEditorTests` — move single/multiple to start/middle/end; caption set/clear;
  remove multiple then restore to original indices (including interleaved); out-of-range no-op.
- `SessionManifestStoreTests` (additions) — `saveSafely` refuses when the folder is unreadable
  (use a non-existent folder / permission-less temp dir) and leaves the existing file intact;
  duplicates de-duplicated on load; `isReadOnly` for version 2.
- `StepFilesTests` — companions found (all four, and subsets); trash + restore round trip with
  an injected trash function in a temp folder; restore fails cleanly when a trashed file is
  missing.
- `ReviewModelTests` — each edit persists; caption debounce (no write before 0.5 s, one write
  after); undo/redo for move, caption, delete; partial trash failure; read-only blocks edits;
  selection after move and delete; uses an injected `UndoManager` and temp folders.

Manual checklist additions (append to the existing checklist): multi-row drag; ⌥↑/⌥↓; ⌘A + ⌫;
⌘Z restores files from Trash; caption edit with bold; Return/Esc behaviour; edit image →
thumbnail refreshes; rename unavailable from Review; empty state; newer-version read-only
(hand-edit version to 2).

## Out of scope

- Export of any kind, including "export selected" (sub-project 3).
- Editing step kind, app name, click point or zoom from Review.
- Merging or splitting steps; adding new steps from Review.
- Cross-session operations.
