# Clipr — Screenshot & Annotation App — Design Spec

Date: 2026-08-25

## Overview

Clipr is a native macOS menu-bar screenshot utility (Snagit-style) with
region/window/full-screen capture, an annotation editor, and an
"Advanced Mode" that auto-captures a screenshot on every mouse click to
build step-by-step tutorials.

## Goals

- Global-hotkey-triggered screen capture: area (rectangle drag),
  full screen, or window.
- Immediate auto-save of raw capture to a configurable folder, and
  auto-copy to clipboard.
- Post-capture editor: draw boxes, arrows, freehand, text, highlighter,
  blur/pixelate, and a small built-in stamp library.
- Editor "Done" saves an edited copy as a new file (raw file
  untouched) and copies the edited image to the clipboard.
- Advanced Mode: toggled on/off, auto-captures the frontmost window on
  every global mouse click, building a numbered sequence for tutorial
  documentation, with a review screen afterward.
- Configurable global hotkeys (capture, advanced-mode toggle) and save
  folder, via a Preferences window.

## Non-Goals

- No screen recording / video capture.
- No freeform/arbitrary-polygon lasso — rectangle drag-select only.
- No cloud sync, sharing, or upload integrations.
- No reorder/rename of shots within an Advanced Mode session (v1).
- No editor interruption during Advanced Mode capture (raw batch save
  only; editing happens in the post-session review screen).

## Architecture

Native macOS app, Swift + SwiftUI (with AppKit where system APIs
require it). Menu-bar-only app (`LSUIElement = true`): no dock icon,
no main window at launch.

### Modules

- **HotkeyManager** — registers global hotkeys via Carbon
  `RegisterEventHotKey` (no Accessibility permission required). Two
  configurable bindings: capture hotkey, advanced-mode toggle hotkey.
- **CaptureManager** — drives the capture overlay and pixel grab via
  `ScreenCaptureKit` (macOS 12.3+). Handles area/full-screen/window
  modes.
- **ClickCaptureManager** — Advanced Mode only. Global mouse-click
  monitoring via `CGEventTap`. Requires Accessibility permission,
  requested the first time Advanced Mode is enabled (not at launch).
- **Editor** — SwiftUI/AppKit canvas for annotation: layered objects,
  undo/redo, flatten-and-save.
- **StorageManager** — filename generation, folder writes, session
  folder management for Advanced Mode.
- **SettingsStore** — UserDefaults-backed: hotkey bindings, save
  folder path, launch-at-login flag.

## Capture Flow (Area / Full Screen / Window)

1. Capture hotkey fires → transparent full-screen overlay window
   (spanning all displays) appears with a crosshair cursor and a small
   mode toolbar: Area / Full Screen / Window.
2. **Area**: user drags a rectangle; release triggers capture of that
   region.
   **Full Screen**: user clicks a display; captures that display.
   **Window**: hovering highlights the window under the cursor; click
   captures just that window.
3. Pixels are grabbed via `ScreenCaptureKit`. First use prompts for
   Screen Recording permission (TCC); if denied, show an alert with a
   link to System Settings → Privacy & Security → Screen Recording.
4. Raw capture is immediately:
   - Saved as PNG to the configured folder (default
     `~/Pictures/Screenshots`), filename
     `Screenshot_yyyy-MM-dd_HHmmss.png`.
   - Copied to the system clipboard (`NSPasteboard`).
5. The Editor window opens, loaded with the raw capture.

## Editor

- Canvas holds an ordered list of annotation objects: rectangle,
  arrow, freehand pen stroke, text box, highlighter, blur/pixelate
  region, stamp (built-in icon set: check, X, star, numbered circles
  1–9).
- Each object is selectable, movable, and resizable; color and stroke
  width apply where relevant. `UndoManager` backs undo/redo.
- Toolbar: tool picker, color swatch, stroke width control,
  undo/redo, **Done**, **Discard**.
- **Done**: flattens all annotation objects onto the base image,
  writes a new file (`Screenshot_..._edited.png`, alongside the
  untouched raw file), copies the edited image to the clipboard, and
  closes the editor.
- **Discard**: closes the editor with no new file written. (The raw
  capture was already saved and clipboarded in step 4 above.)

## Advanced Mode (Tutorial Builder)

Purpose: auto-capture a screenshot on every mouse click while working
through an app, to assemble a step-by-step tutorial without manually
triggering capture each time.

1. **Start**: toggled via menu bar item or its dedicated hotkey.
   First activation prompts for Accessibility permission (required by
   `CGEventTap`). A session folder is created:
   `~/Pictures/Screenshots/Session_yyyy-MM-dd_HHmmss/`.
2. **Per click**: on every global left mouse click, wait ~200ms
   (debounce, letting the clicked UI settle/redraw), then capture the
   frontmost application window at that moment and save it as
   `Step_01.png`, `Step_02.png`, … sequentially inside the session
   folder. No clipboard write; no editor popup — capture is silent.
3. **Self-exclusion**: clicks on Clipr's own UI (menu bar icon, the
   review screen described below) do not trigger a capture.
4. **Stop**: toggled off the same way it was started. Stopping opens a
   **Review screen**: a grid of thumbnails, one per captured step, in
   order. Per-shot actions: open in the full Editor (annotate, Done
   saves an edited copy alongside the raw step file as in the normal
   editor flow), or delete the shot from the session. No reorder or
   rename in v1.

## Settings (menu bar → Preferences)

- Hotkey recorder UI for both the capture hotkey and the Advanced
  Mode toggle hotkey.
- Save folder picker (default `~/Pictures/Screenshots`).
- Launch at login toggle.

## Permissions

- **Screen Recording** — required for all capture modes; requested on
  first capture attempt.
- **Accessibility** — required only for Advanced Mode's global click
  monitoring; requested on first Advanced Mode activation, not at
  app launch.

## Data Layout

```
~/Pictures/Screenshots/
  Screenshot_2026-08-25_143012.png              (raw, normal capture)
  Screenshot_2026-08-25_143012_edited.png       (edited copy, if Done clicked)
  Session_2026-08-25_150500/
    Step_01.png
    Step_02.png
    Step_02_edited.png                          (if annotated in review)
    ...
```

## Error Handling

- Screen Recording / Accessibility permission denied → alert with
  direct link to the relevant System Settings pane; feature stays
  disabled until granted.
- Save folder missing/unwritable (e.g. deleted after being configured)
  → alert on capture, offer to reset to default folder.
- Window capture on a window that closes mid-capture → abort that
  single capture, no crash, no partial file written.

## Testing

- Manual: hotkey trigger, all three capture modes, each editor tool
  (draw/undo/redo/Done/Discard), permission-denied paths (both TCC
  types), folder picker, Advanced Mode start/stop/review/delete,
  self-exclusion of own UI clicks.
- Unit tests: filename/session-folder generation, settings
  persistence (hotkey bindings, folder path), undo stack behavior in
  the editor, debounce timing logic in ClickCaptureManager.

## Open Items (explicitly deferred, not v1)

- Reorder/rename shots within an Advanced Mode session.
- Cloud sync / sharing / upload integrations.
- Freeform lasso selection shape.
