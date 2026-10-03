# Advanced Mode Capture Enhancements — Design

Date: 2026-10-03
Status: Approved (design), pending spec review

## Context and intent

Advanced Mode records a click-through session as numbered step screenshots. Its purpose is
producing **how-to guides and documentation**: steps must read cleanly, carry meaningful
captions, and be correctable after the fact. Exact forensic replay (QA/bug reports) is a
non-goal.

The full enhancement is split into three sub-projects, each with its own spec → plan → build:

1. **Capture** (this spec): session manifest, click marker, cursor trail, zoom on click, auto
   captions, typing steps, capture options, Preferences section.
2. **Review**: reorder, edit captions, multi-select delete/export. Edits the manifest from (1).
3. **Export**: PDF / Markdown / HTML / GIF guide. Consumes manifest captions and zoom crops.

Every feature in this spec is individually configurable in Preferences.

## Decisions

- **Markers are editable annotations (approach A).** Ring and trail are written into the
  step's existing `_annotations.json` sidecar as ordinary `AnnotationObject`s. Raw PNGs stay
  clean; the editor shows, moves, restyles, and deletes them; export renders them through the
  existing `AnnotationRenderer`.
- **Typing produces its own step**, captured when the typing burst ends, so the screenshot
  shows the filled field.
- **Settings are snapshotted at session start**; mid-session Preference changes apply to the
  next session.

## Defaults (tuned for guides)

| Setting | Default |
|---|---|
| Click marker | On, style: ring |
| Auto captions | On |
| Cursor trail | Off |
| Zoom on click | Off |
| Typing steps | Off |
| Capture scope | Window |
| Capture delay | 0.3 s (range 0–2 s) |
| Step hotkey | Unset |

## Architecture

### Units

| Unit | Kind | Responsibility |
|---|---|---|
| `AdvancedModeSettings` | Codable struct in `SettingsStore` | Holds all toggles, marker style, scope, delay, step hotkey. One UserDefaults key. |
| `SessionEventTap` | Event source | Single listen-only CGEventTap. Mask is built from the session's settings: `leftMouseDown` always; `mouseMoved`/`leftMouseDragged` only if trail on; `keyDown`/`flagsChanged` only if typing on. Callback does no work beyond copying event data and forwarding to the coordinator on the main queue. Re-enables itself on `tapDisabledBy*`. |
| `CursorTrailRecorder` | Pure | Accumulates global cursor points since the last step. Drops a point if < 8 pt from the previous kept point; keeps at most 300 points (drops oldest). `drain()` returns and resets. |
| `ClickDescriber` | AX adapter | Given a global point, on a private serial queue: `AXUIElementCopyElementAtPosition` on the system-wide element with `AXUIElementSetMessagingTimeout` 0.25 s; reads role, subrole, title, description, value (text fields: placeholder/title only, never value), and for menu items walks `AXParent` to build the menu path. Returns `ClickTarget` (plain struct) or `nil`. App name from `NSWorkspace.frontmostApplication.localizedName`. Also exposes `isSecureField(focused:)`. |
| `CaptionFormatter` | Pure | `ClickTarget` / typing / shortcut → caption string. |
| `KeystrokeAggregator` | Pure | Turns key events into bursts; emits `.text(String)` or `.shortcut(String)` events. |
| `StepGeometry` | Pure | Maps global (top-left) points into the step image's coordinate space. |
| `StepAnnotationFactory` | Pure | Builds ring/dot and trail `AnnotationObject`s. |
| `SessionManifest` + `SessionManifestStore` | Model + IO | `session.json` model; atomic writes; reconstruction fallback. |
| `ClickCaptureManager` | Coordinator | Owns a session: receives forwarded events, applies delay/coalescing, captures per scope, writes PNG → annotations → zoom → manifest, reports step count. |

### Manifest model (`session.json`, in the session folder)

```swift
struct SessionManifest: Codable {
    var version: Int            // 1
    var createdAt: Date
    var steps: [StepRecord]     // display order
}

struct StepRecord: Codable, Identifiable {
    enum Kind: String, Codable { case click, typing, manual }
    let id: UUID
    var file: String            // "Step_03.png", relative to session folder
    var kind: Kind
    var caption: String?
    var clickPoint: CGPoint?    // image point space, top-left origin; nil if off-image / n/a
    var zoomFile: String?       // "Step_03_zoom.png"
    var appName: String?
    var capturedAt: Date
}
```

Array order is display order, so sub-project 2 can reorder without renaming files.

**Reconstruction:** loading a session folder whose `session.json` is missing or undecodable
yields a manifest built from `Step_*.png` (excluding `_edited.png` and `_zoom.png`), sorted by
natural filename order, kind `.manual`, no captions. Steps present on disk but missing from a
valid manifest are appended the same way; manifest entries whose file is missing are dropped.
`AdvancedModeCoordinator.reviewLastSession()` and the Review window use this loader.

## Feature behavior

### Event flow (per click)

1. Tap sees `leftMouseDown` at global point `p`. Clicks on Clipr's own windows are ignored
   (existing behavior). Paused sessions ignore everything.
2. Coordinator immediately: drains the trail recorder, ends any typing burst (which may enqueue
   a typing step first), and if captions are on, starts `ClickDescriber.describe(p)` (async).
3. Schedules capture after `delay` (minimum 0.2 s). A new click before it fires replaces the
   pending one (last wins); the replaced click's trail points are kept and prepended to the
   new click's trail.
4. On fire: resolve capture target per scope, capture image, compute geometry, then write in
   order: PNG → annotations sidecar → zoom PNG → manifest entry (with caption once the describe
   result is available; awaited with a 0.5 s cap, fallback caption otherwise).

### Click marker

Ring: `.ellipse` annotation, frame 36×36 pt centered on the image-space click point, stroke 3,
color = the editor's current default color. Dot: `.ellipse` 14×14 pt with stroke width 7 (= radius),
which renders as a filled dot without a new annotation kind. Skipped
when `clickPoint` is nil.

### Cursor trail

One `.freehand` annotation from the drained trail points plus the click point, mapped to image
space, clipped to the image bounds (points outside are dropped; if fewer than 2 remain, no
trail). Stroke 2, color at 60% alpha.

### Zoom on click

Crop of the step image, 400×300 pt centered on `clickPoint`, shifted (not shrunk) to stay
inside the image; if the image is smaller than the crop in a dimension, that dimension is the
whole image. Native pixel resolution (reuse `CaptureGeometry`/crop helpers and pixel-scale
handling). Saved as `Step_NN_zoom.png`; filename recorded in `zoomFile`. Skipped when
`clickPoint` is nil.

### Auto captions (`CaptionFormatter`)

| Target | Caption |
|---|---|
| `AXMenuItem` with path | `Choose **File ▸ Export…**` |
| `AXButton`, `AXPopUpButton`, `AXCheckBox`, `AXRadioButton`, `AXTab` with label | `Click **Save** in Safari` |
| `AXTextField`, `AXTextArea`, `AXComboBox`, `AXSearchField` | `Click the **Name** field` (label from title/placeholder/description) |
| `AXLink` | `Click the **Pricing** link` |
| anything else with a label | `Click **Label** in AppName` |
| no target / no label | `Click in **AppName**` (or `Click` if app unknown) |
| typing burst | `Type "John" in **Name**` / `Type "John"` if no focused label |
| shortcut | `Press **⌘S**` |
| manual step | no caption |

Labels are trimmed, whitespace-collapsed, truncated to 60 characters with `…`. `**`/`"` inside
labels are escaped so Markdown export (sub-project 3) stays valid.

### Typing steps (`KeystrokeAggregator`)

- Printable characters append to the current burst; Backspace removes the last character
  (no-op on empty); arrow keys/Escape are ignored.
- A key with ⌘ or ⌃ (and not just ⇧) ends any burst and emits `.shortcut("⌘S")` using
  standard modifier glyph order ⌃⌥⇧⌘.
- Burst ends on: 1.0 s idle, Return, Tab, or a click. On end, if non-empty → `.text`.
- Text is truncated to 60 characters with `…` in the caption.
- **Secure input:** if `IsSecureEventInputEnabled()` is true at any key event, or the focused
  element's subrole is `AXSecureTextField`, the burst is marked secure and discarded entirely
  on end — never stored or emitted, even partially.
- Each emitted event becomes a step of kind `.typing` (shortcut steps are also `.typing`),
  captured immediately (no delay; the screen already shows the result), with no marker.
- Typing scope target: Window scope → frontmost window of the frontmost app; Screen scope →
  display containing the focused element (fallback: display containing the cursor); Fixed area
  → the area.
- **Permission:** keyboard events in a listen-only tap require Input Monitoring. Check with
  `CGPreflightListenEventAccess()`. If denied at session start, the keyboard mask is omitted,
  typing is off for the session, and the floating bar shows
  "Typing not recorded — grant Input Monitoring". Preferences shows a "Grant…" button next
  to the toggle when not granted (`CGRequestListenEventAccess()`).

### Capture scope

- **Window** — current behavior: frontmost window of the frontmost app (`WindowPicker`),
  `CaptureManager.captureWindow`. Geometry origin = window bounds origin.
- **Screen** — display containing the click point, full-screen capture (reuse
  `CaptureManager` full-screen capture). Geometry origin = display bounds origin.
- **Fixed area** — at session start, show the existing area-selection overlay once; cancel →
  session does not start (no alert). Each step captures the display containing the area and
  crops to it. Geometry origin = area origin. Clicks outside the area still produce a step
  (the area may show the result) but with `clickPoint = nil`.

### `StepGeometry`

`imagePoint = globalPoint - captureOrigin`, in points, top-left origin — the same space the
editor uses for `AnnotationObject.frame` (image point size, not pixels). Returns `nil` if the
point lies outside `CGRect(origin: .zero, size: imagePointSize)`. The implementation plan must
verify this matches how a saved Retina step PNG reloads (`NSImage+PixelScale`), with a test.

### Manual step hotkey

`AdvancedModeSettings.stepHotkey` (optional `HotkeyBinding`). Registered via `HotkeyManager`
when a session starts, unregistered when it stops. Registration conflict → logged; floating bar
shows nothing extra. Fires an immediate capture per scope (Window scope: frontmost window),
kind `.manual`, no caption, no marker, trail drained and discarded.

### Floating control bar

Unchanged except: optional one-line warning row (Input Monitoring); step count includes all
step kinds.

### Preferences

New "Advanced Mode" `Section` in `PreferencesView`:

- Toggle **Click marker** + segmented picker (Ring / Dot), disabled when off
- Toggle **Auto captions**
- Toggle **Cursor trail**
- Toggle **Zoom on click**
- Toggle **Typing steps** + "Grant…" button when Input Monitoring not granted
- Picker **Capture** (Window / Screen / Fixed area)
- Slider **Capture delay** 0–2 s, step 0.1, value label
- Hotkey recorder **Step hotkey** (with clear)

The existing global "Capture Mouse Cursor" toggle continues to apply to Advanced Mode captures.

## Error handling

| Failure | Behavior |
|---|---|
| Tap disabled by system | Re-enable (existing), applies to all masks |
| AX timeout / error | Fallback caption; step still captured |
| Image capture fails | Log, skip step; no manifest entry |
| Annotations sidecar write fails | Log; step kept without markers |
| Zoom write fails | Log; `zoomFile = nil` |
| Manifest write fails | Log; PNG kept; reconstruction covers it on load |
| Fixed-area selection cancelled | Session does not start, no alert |
| Input Monitoring denied | Typing disabled for session; bar warning |
| Step hotkey conflict | Log; session continues without it |
| Secure field typing | Burst discarded, nothing stored |

Writes order (PNG → annotations → zoom → manifest) guarantees the manifest never references a
missing PNG.

## Testing

Unit tests (XCTest, `Tests/ClipprTests`):

- `CursorTrailRecorderTests` — distance filter, 300-point cap drops oldest, drain resets.
- `KeystrokeAggregatorTests` — idle/Return/Tab/click boundaries, Backspace, shortcut glyph
  order, secure burst discarded, empty burst emits nothing.
- `CaptionFormatterTests` — each role row in the table, fallback rows, truncation, escaping.
- `StepGeometryTests` — offset window, Retina scale, negative-origin secondary display,
  off-image → nil.
- `StepAnnotationFactoryTests` — ring/dot frames, trail clipping and < 2 point rejection.
- `SessionManifestTests` — round trip, missing file reconstruction, orphan PNG append,
  missing-file entry drop, `_edited`/`_zoom` exclusion.
- `AdvancedModeSettingsTests` — defaults, persistence round trip, decoding with missing keys.

Manual checklist (event taps, AX, ScreenCaptureKit are not unit-testable): one session per
scope; each toggle on/off; typing into a normal field and a password field; menu item caption;
step hotkey; pause/resume; Review Last Session after relaunch; markers editable in editor.

## Out of scope (this sub-project)

- Editing/reordering captions or steps (sub-project 2).
- Any export format (sub-project 3).
- Showing captions anywhere other than the Review window thumbnails (read-only label).
- Right-click / double-click as distinct step types.
