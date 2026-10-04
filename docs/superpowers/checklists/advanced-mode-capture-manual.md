# Advanced Mode Capture — Manual Checklist

Build with `./Scripts/build-app.sh`, quit any running Clipr, `open Clipr.app`. Re-grant
Accessibility / Screen Recording / Input Monitoring if prompted (ad-hoc rebuilds can drop them).

## Scopes (defaults otherwise)
- [ ] Window: click 3 buttons in Safari → 3 steps; each has a red ring on the clicked control.
- [ ] Screen: same clicks → full-display steps; rings on the right spots, including on a second display.
- [ ] Fixed area: start → overlay appears; drag an area → steps are that area only.
- [ ] Fixed area: start → press Esc in the overlay → no session, no alert.

## Features
- [ ] Captions: Review shows "Click Save in Safari"-style captions; a menu item shows "Choose File ▸ …".
- [ ] Marker style Ring (default): red ring centred on the clicked control.
- [ ] Marker style Dot: small solid filled dot (~14 pt) instead of ring.
- [ ] Marker off: no annotations on new steps.
- [ ] Trail on: faint path leading to each click; editable in editor.
- [ ] Zoom on: `Step_NN_zoom.png` next to each click step, centred on the click.
- [ ] Typing on (Input Monitoring granted): type a name in a text field, click elsewhere → a "Type "…" in Name" step showing the filled field, before the click step.
- [ ] Typing on: type in a password field → no typing step; `session.json` has no trace of it.
- [ ] Typing on: typing in an app with no usable Accessibility data (or where focus moves to another field mid-typing) → no typing step; clicks still record.
- [ ] Typing on: type in a field, press Tab to the next field → typing step recorded.
- [ ] Typing on: type in a field, click the next field → typing step recorded, before the click step.
- [ ] Typing on: pressing Clipr's own hotkeys (step / Advanced Mode) never creates a "Press …" step.
- [ ] Typing on: typing in Terminal/iTerm → no typing step; clicks still record.
- [ ] Typing on: type a few characters, Pause, Resume, Stop → no typing step for those characters.
- [ ] Typing on without Input Monitoring: panel shows the warning; clicks still record.
- [ ] Click captions: only quote visible text for labels, cells, buttons, links, headings; clicking a filled text field shows the field name, never its contents.
- [ ] Shortcut: ⌘S in an app → "Press ⌘S" step.
- [ ] Step hotkey: set one, start session, press it → manual step without caption/marker; after Stop the hotkey no longer fires.
- [ ] Delay 1.5 s, Screen scope: open a menu by clicking → step shows the menu open (Window scope captures only the app window, not menus).
- [ ] Double-click → one step.

## Session
- [ ] Pause → clicks ignored; Resume → numbering continues.
- [ ] Stop right after a click (within the delay) → that click's step is in Review.
- [ ] Clicking Pause/Resume/Stop, anything on Clipr's floating bar, the menu-bar icon, or Preferences never creates a step.
- [ ] Stop never hangs: even if a capture stalls, Review opens within ~10 s.
- [ ] Open a step in the editor → marker and trail are selectable, movable, deletable.
- [ ] Review Last Session after relaunching Clipr → same steps and captions.
- [ ] Old session folder (no session.json) → Review lists its steps without captions.

## Preferences
- [ ] After granting Input Monitoring, 'Grant…' may remain until Preferences is reopened; reopening hides it.
- [ ] Preferences window fits on the smallest display used.

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
- [ ] Click a caption, type one character, press Return → the character is saved (first keystroke not lost).
- [ ] Type into a caption, delete back to the original text, close the window without pressing Return → reopen Review: the original caption is unchanged.
- [ ] A caption whose text came from an app label containing a Markdown link (e.g. hand-edit session.json caption to `[Open](https://example.com)`) shows "Open" as plain text and is not clickable.
- [ ] Start recording, open Review Last Session → the session being recorded is not offered.
- [ ] Stop recording while that session's Review is already open → the existing window comes forward (no second window).
- [ ] Type a caption and press ⌘Q within half a second → reopen Review: caption saved.
- [ ] View toggle (List / Large / Guide) and ⌘1 / ⌘2 / ⌘3 switch layouts; images in Large and Guide are sharp.
- [ ] Drag-reorder, ⌫, ⌘Z and caption editing work the same in all three layouts.
- [ ] Close and reopen Review → it opens in the last chosen layout.
- [ ] Edit's arrow (or right-click a row) → Retake Screenshot… → Review hides, capture overlay appears; drag an area → Review returns with the new image in that step; caption kept.
- [ ] Retake, then press Esc in the overlay → nothing changes.
- [ ] Replace with File… → pick a PNG/JPEG/HEIC → the step shows the new image; the old PNG, annotations and zoom are in the Trash.
- [ ] After a replace, ⌘Z → original image (with its marker) back; ⇧⌘Z → new image again.
- [ ] Read-only session → Retake / Replace items are disabled.
- [ ] Large / Guide: hovering an image (or selecting its row) shows S · M · L · Full and Edit ▾ on a slim bar just above the image's top-right edge (never over the picture); it hides when the pointer leaves an unselected row, and rows don't jump. Captions use the full width.
- [ ] List: the ⋯ button beside the caption opens Edit Image / Retake / Replace / Image Size.

## Export — clipboard spike

Run on (date, macOS version): pending — to be done by the user (needs signed-in browsers)
Script: copy it from Task 1 Step 1 of `docs/superpowers/plans/2026-10-04-advanced-mode-export.md` (heading, bold text, one data-URI PNG as HTML + RTF) into a scratch `.swift` file and run it with `swift`.

| Target | Heading + bold | Image |
|---|---|---|
| TextEdit (control) | pending — to be done by the user | pending — to be done by the user |
| Google Docs (Safari) | pending — to be done by the user | pending — to be done by the user |
| Notion (web) | pending — to be done by the user | pending — to be done by the user |
| Confluence (web) | pending — to be done by the user | pending — to be done by the user |

Decision: `GuideClipboard.imagesMayBeDropped` is `false` only if every web target's Image cell is `Kept`; otherwise `true` and the export sheet shows the Copy note.

Outcome: pending — until the spike is run, assume `imagesMayBeDropped = true` (the safe default: the Copy note is shown).

## Export
- [ ] Review's header shows **Export…**; ⇧⌘E opens the same sheet. Both are disabled when the session has no steps; ⇧⌘E does nothing while a caption is being edited.
- [ ] The sheet lists PDF, HTML, Markdown, GIF, Copy as Rich Text; Title defaults to the session folder name. Clearing the Title and exporting uses the folder name as the heading.
- [ ] With two steps selected the sheet offers "Selected steps (2)" (chosen) and "All steps (N)"; exporting gives just those two, numbered 1 and 2, in Review order.
- [ ] PDF: the save panel suggests "<title>.pdf"; after export Finder reveals the file. In Preview: title, grey "date · N steps" line, numbered steps with bold kept, app name in small grey text, images with their annotations (markers, trail, editor drawings), sized steps narrower, no step split across pages. Paper is A4 (Letter when the Mac's region is US).
- [ ] HTML: opens in Safari looking like the PDF; move the file to another folder and reopen → images still show (embedded).
- [ ] Markdown: choose a folder → it contains `guide.md` and `images/step-01.png`…; the guide renders on GitHub with images, Small/Medium/Large steps narrower than Full ones.
- [ ] Markdown again into the same folder (or into a folder that has only an `images` folder) → "This folder already has guide.md or an images folder." with Replace / Cancel → Cancel leaves the folder untouched; Replace overwrites guide.md and the whole images/ folder.
- [ ] GIF: one frame per step, same size throughout, caption band underneath ("Step N" when no caption), loops forever; the Frame time slider (1–5 s) changes the pace; posted in Slack it animates.
- [ ] Include close-ups on (session recorded with Zoom on click): the close-up sits beside the image in HTML/PDF and follows the image line in Markdown; off → no close-ups. The toggle is hidden for GIF.
- [ ] Copy as Rich Text: the action button reads "Copy"; the web-app note ("Images may not paste into some web apps — use PDF or Markdown") shows while the clipboard spike is pending or recorded dropped images. Paste into TextEdit, Google Docs, Notion and Confluence and compare with the spike table above.
- [ ] Progress sheet: the bar fills while step images render, then turns into an indeterminate bar with "Finishing…" (PDF printing, writing files, clipboard conversion); Cancel stays available throughout.
- [ ] Reopen the sheet → last format, close-ups choice and frame time are remembered; Title is the folder name again.
- [ ] With Review open, move one step's PNG out of the session folder in Finder, then export HTML → that step shows "Image unavailable" and an alert lists the step.
- [ ] Replace a step's `_annotations.json` contents with `x`, export → the step's image appears without annotations and an alert says its annotations couldn't be read.
- [ ] Start a PDF export of a long session and press Cancel in the progress sheet → no file at the chosen location.
- [ ] Export into a folder you can't write to (e.g. `chmod 555` a test folder) → "Export Failed" alert explaining the location couldn't be written; nothing appears there.
- [ ] Hand-edit `session.json` "version" to 2 (read-only session) → Export still works.
