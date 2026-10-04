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
