# Clipr — Full Code Review (2026-10-04, main @ b31470e)

Five parallel reviews: structure, security, core bugs, Advanced Mode bugs, product/monetisation. Build clean, 466 tests pass. Detailed reports are appended below.

## Fix first (data loss, privacy, freezes)

| # | Area | Issue | Where |
|---|---|---|---|
| 1 | Privacy | Close-ups are cropped from the raw frame and never regenerated, so an exported guide can show unredacted pixels next to a redacted step | ClickCaptureManager.swift:374, GuideDocument.swift:118 |
| 2 | Privacy | Typing steps can record passwords in fields that don't report secure (VS Code, JetBrains, Hyper, browser terminals, Screen Sharing/RDP/VMs) | ClickDescriber.swift:81 |
| 3 | Data loss | Cropping a file opened via "Open Image…" overwrites the user's original (and writes PNG bytes into .jpg/.heic) | StorageManager.swift:38/257 |
| 4 | Data loss | Overwrite deletes the file before writing; a failed write loses the capture while the alert says "left unchanged" | StorageManager.swift:257-261 |
| 5 | Usability | Hotkey recorder accepts keys without modifiers — a bare A/Esc becomes a global hotkey that swallows the key everywhere | HotkeyRecorderView.swift:41 |
| 6 | Freeze | Same hang pattern as the fixed segmented picker: native `Menu(.borderedButton/.borderlessButton)` in Review rows with hover-toggled `.accessibilityHidden` | ReviewRow.swift:108-182 |
| 7 | Freeze (unverified) | Capture hotkey while an alert/open panel is up may leave click-proof overlays | AppDelegate.performCapture |
| 8 | Security | Ad-hoc signing, no hardened runtime, not notarised: library injection can inherit Accessibility/Input Monitoring/Screen Recording grants; updates reset grants | Scripts/build-app.sh:35 |
| 9 | Conflict | Default Advanced Mode shortcut ⌘⇧3 is macOS's screenshot shortcut | Settings defaults |

## Next (correctness)
- Recording: second click within the delay drops the first step; Window scope uses frontmost window, not the clicked one; PNG encode/write on main thread (event-tap thread); typing steps use the mouse's display; same-second session folder reuse overwrites session.json.
- Review: deleting a step with its editor open leaves orphans and breaks ⌘Z; same step openable in two editors; PDF 30 s timeout may fail long guides.
- Editor: undo leaves stale selection (wipes redo), per-keystroke text undo, empty text boxes restored, long text clipped, placed text not re-editable, diagonal arrows/pen hit-test by bounding box, Save As can export old annotations, Recents delete permanent without confirm, light mode not handled, empty `_annotations.json` written.
- Hardening: validate `zoomFile` path / don't follow `Step_*.png` symlinks; image/sidecar size limits; files 0600 for sessions; validate update-checker URL.

## Structure / maintainability
- Extract shared helpers: `NSImage.encodedData` (3 PNG encoders), `BitmapContext.rgb` (6 CGContext setups), `ImageDecoder.thumbnail` (2), `Alerts.show` (15 NSAlert sites), `WindowPresenter.bringToFront` (7), `Panels` (6 open/save panels), cached `DateFormatter`s.
- Split AppDelegate (365) into HotkeyCoordinator / AdvancedModeController / EditorPresenter / PreferencesPresenter.
- Files >300 lines: ReviewModel 517, ClickCaptureManager 451, EditorWindowController 425, AppDelegate 365, ReviewRow 350, EditorView+Toolbar 341, GuideExporter 335 — splits proposed in Appendix A.
- One type per file: SessionManifest (8 types), GuideDocument (8), GuideExporter (6), ExportSheet, KeystrokeAggregator, ClickDescriber.
- Long view bodies/functions (no function >100 lines): PreferencesView.advancedModeTab 97, CaptureOverlayView.body 85, EditorView+Canvas.canvasArea 80, generalTab 78, GuideExporter.run 71.
- Testability: inject ThumbnailCache; protocols for StorageManager, CaptureManager, PermissionsManager, UpdateChecker.

## Monetisation (recommended)
- Position: "Scribe-style guides that stay on your Mac, for any app, pay once." Competitors are cloud, per-seat (Scribe Pro ~$25/seat/mo, Tango $15–22/user/mo).
- Free: screenshot tool + guide recording. Pro $39 one-time incl. 1 yr updates, $19/yr optional renewal (CleanShot $29+$19, Xnapper $29.99). Team 5-seat $149. Optional Share subscription ~$36/yr later. Paywall at export, not capture; 14-day trial from first export.
- Direct sale via Paddle (5% + $0.50), notarised DMG + Sparkle, Homebrew cask; Setapp after 3–6 months. Mac App Store not viable (sandbox blocks Accessibility).
- App changes: Developer ID + notarisation + hardened runtime, Sparkle, offline Ed25519 licence keys in Keychain, feature gates, trial, License tab, managed settings for IT.
- Launch: Product Hunt, r/macapps, r/sysadmin, r/msp, Show HN; intro $29.

---


# Appendix: structure

# Clipr structure review (paths relative to Sources/Clipr)

Totals: 121 source files. Only 6 non-test files >300 lines. No big-view or giant-function crisis; main wins are dedup and trimming AppDelegate / ReviewModel / EditorWindowController.

## HIGH

### H1. Duplicated NSBitmapImageRep -> PNG encode (3 copies)
- Storage/StorageManager.swift:241 `bitmapRep(of:)` + :249 inline `representation(using:.png)`; Storage/StorageManager.swift:219 uses `format.bitmapType`
- AdvancedMode/StepFiles.swift:129-134 `pngData(_:)` (identical rep + size=image.size)
- AdvancedMode/Export/GuideImages.swift:99 `encoded(image, as:, properties:)`
Extract: `extension NSImage { func encodedData(_ format: ExportFormat) -> Data? }` (new Editor/NSImage+Encoding.swift, next to NSImage+PixelScale.swift). StorageManager and StepFiles.pngData become one-liners (or are deleted; ReviewModel.swift:305 calls StepFiles.pngData).

### H2. Duplicated CGContext/RGB bitmap setup (6 sites)
GuideImages.swift:88,117; GIFGuideExporter.swift:70; Editor/Pixelation.swift:39,47; Editor/NSImage+PixelScale.swift:32. All `CGContext(data:nil,...,space:CGColorSpaceCreateDeviceRGB(), bitmapInfo:...)`.
Extract: `enum BitmapContext { static func rgb(width: Int, height: Int, opaque: Bool) -> CGContext? }` in Editor/BitmapContext.swift (nearer a shared Imaging/ folder).

### H3. Duplicated ImageIO thumbnail decode
- AdvancedMode/StepFiles.swift:143-152 (`CGImageSourceCreateThumbnailAtIndex` with FromImageAlways + WithTransform)
- AdvancedMode/Export/GuideImages.swift:66-78 (same options, plus width->long-side math)
- Editor/ThumbnailCache.swift / ThumbnailView.swift call StepFiles version.
Extract: `enum ImageDecoder { static func thumbnail(source: CGImageSource, maxPixelSize: Int) -> CGImage?; static func thumbnail(url: URL, maxPixelSize: Int) -> CGImage? }` (Editor/ImageDecoder.swift); StepFiles and GuideImages call it.

### H4. NSAlert boilerplate: 15 `NSAlert()` sites
AppDelegate.swift:125,153,226,274; UpdateChecker.swift:108,133; ReviewWindowController.swift:74; ExportFlowController.swift:129,188; EditorWindowController.swift:188,222,308,360; plus two helpers already exist (Permissions/PermissionAlert.swift:7, AdvancedMode/AdvancedModeAlert.swift:8) which are themselves parallel.
Extract: `enum Alerts { @discardableResult static func show(_ title: String, _ detail: String? = nil, style: NSAlert.Style = .warning, buttons: [String] = ["OK"], sheetFor window: NSWindow? = nil) -> NSApplication.ModalResponse }` in new UI/Alerts.swift; fold PermissionAlert/AdvancedModeAlert into it. Pairs with window activation (H5).

### H5. Window presentation/activation repeated
`NSApp.activate(ignoringOtherApps:true)` at AppDelegate.swift:191,273,352; StatusItemController.swift:84; UpdateChecker.swift:120,136; ReviewWindowController.swift:57-59; EditorWindowController.swift:408; AppDelegate.bringToFront :351 already exists as the intended helper but is private.
Extract: `extension NSWindowController { func presentFront() }` / `enum WindowPresenter { static func bringToFront(_ c: NSWindowController) }` in UI/WindowPresenter.swift. Also NSOpenPanel/NSSavePanel setup is repeated 6x (AppDelegate:100, PreferencesView:272, ReviewWindowController:107, ExportFlowController:91,105, EditorWindowController:291): `enum Panels { static func chooseImage(...), chooseFolder(...), saveFile(...) }`.

### H6. AppDelegate is a god object (365 lines, AppDelegate.swift)
Owns: status item, settings, hotkeys (registerHotkeys :109, three HotkeyIDs), updates, storage, capture, Advanced Mode lifecycle (:181-278), control panel show/hide, editors array, preferences window (:308-349), open-image panel (:99), main menu, alerts (:125,153,226). Split:
- `HotkeyCoordinator.swift` (registerHotkeys + step hotkey register/unregister + rejected-alert)  ~60 lines
- `AdvancedModeController.swift` (toggle/start/pause/panel/reviewLast, :181-278) ~100 lines
- `EditorPresenter.swift` (openEditors, openEditor, frontmostEditor, openImage) ~50 lines
- `MainMenu.swift` (installMainMenu; check if already extension) 
- `PreferencesPresenter` (:308-349)
AppDelegate shrinks to wiring (<120 lines).

## MEDIUM

### M1. Files >300 lines (non-test) and split plans
| file | lines | verdict |
|---|---|---|
| AdvancedMode/ReviewModel.swift | 517 | Split. It mixes selection (:82-115), image-size (:102-145), caption editing state machine (:146-240), delete/restore (:243-295), image replacement incl. file IO (:302-417), undo/manifest persistence (:419-517). Move into extensions: `ReviewModel+Captions.swift`, `ReviewModel+Deletion.swift`, `ReviewModel+ImageReplacement.swift`, `ReviewModel+Undo.swift`; core stays ~150 lines. Better: extract a `ReviewImageReplacer` (file ops, uses StepFiles) so the model has no IO beyond injected closures. |
| AdvancedMode/ClickCaptureManager.swift | 451 | Split. Contains lifecycle (:88-155), event handling (:158-198), step/typing burst (:199-280), write/queue (:281-390), and `FirstResult` (:418) + a key-matcher type (:442 `matches(_:)`). Extract `CaptureWriteQueue.swift` (reserveWriteSlot/enqueue/write, :293-390) and `TypingBurstTracker.swift` (:211-280); move `FirstResult` into its own file. |
| Editor/EditorWindowController.swift | 425 | Split. UI wiring + persistence/autosave (:211-290: rename/autoSave/persist) + saveAs/copy/share (:289-400) + crop/resize write (:326-383). Extract `EditorDocument` / `EditorPersistence` (autoSave generation, persist, writeBaseImage, loadAnnotationsPreservingCorrupt) and `EditorWindowController+Actions.swift` (saveAs/copy/share). Controller keeps window setup and delegate methods. |
| AppDelegate.swift | 365 | see H6 |
| AdvancedMode/ReviewRow.swift | 350 | Split into ReviewRow.swift (layout), `ReviewRowCaptionField.swift`, `ReviewRowThumbnail.swift` (image + marker overlay), `ReviewRowContextMenu`. |
| Editor/EditorView+Toolbar.swift | 341 | Extension already; split `toolbar` (72 lines) into `ToolPicker`, `ColorStyleControls`, `UndoRedoButtons` subviews and move to EditorToolbar/ files. |
| AdvancedMode/Export/GuideExporter.swift | 335 | Split: it holds 6 types (see M2) + `run` (71 lines). Move the support types out; leaves ~230. |
Near threshold: PreferencesView 291, StorageManager 285 (move rename, :117, to StorageManager+Rename; Annotations I/O to +Annotations).

### M2. Files defining multiple significant types
- AdvancedMode/Export/GuideExporter.swift: GuideWarning :5, GuideExportError :27, CancelFlag :46, ImagesRestoreError :65, WorkFolder :249 -> GuideExportTypes.swift (warning + errors), CancelFlag.swift (Common/), WorkFolder to GuideExporter+WorkFolder.swift.
- AdvancedMode/Export/GuideDocument.swift (8 types): GuideFormat :6, ExportOptions :41, GuideImageRef/GuideImage/RenderedImages :57-86, GuideStep, GuideDocument -> GuideFormat.swift, ExportOptions.swift, GuideImage.swift (Ref/Image/RenderedImages), GuideDocument.swift.
- AdvancedMode/SessionManifest.swift (8 types): ImageSize :6, StepRecord :29, SessionManifest :52, SessionManifestStore :64 (+ReadOnlyReason :94) -> ImageSize.swift, StepRecord.swift, SessionManifestStore.swift.
- AdvancedMode/Export/ExportSheet.swift: ExportProgress :62 (ObservableObject) and ExportProgressView :66 -> ExportProgress.swift, ExportProgressView.swift.
- AdvancedMode/Export/GuideClipboard.swift: GuideRichText :52 -> GuideRichText.swift.
- AdvancedMode/KeystrokeAggregator.swift: KeyModifiers :3, KeyInput :12, TypingEvent :23 -> KeyInput.swift.
- AdvancedMode/ClickDescriber.swift: ClickDescribing :5 protocol, FieldSecurity :16, FocusedField :20 -> ClickDescribing.swift (protocol + value types).
- AdvancedMode/StepImageSource.swift: CaptureTarget :4, CapturedFrame :10, protocol :17, LiveStepImageSource :22 -> split live impl out.
- AdvancedMode/SessionEventTap.swift: SessionEvent :5, SessionEventOptions :14, protocol :19, SessionEventTap :29 -> SessionEvent.swift.
- AdvancedMode/StepFiles.swift: StepFilesError :3, TrashedStep :8 -> own files.
- AdvancedMode/AdvancedModeControlPanel.swift: AdvancedModeControlState :6 -> own file.
- AdvancedMode/CaptionFormatter.swift: ClickTarget :4. Updates/UpdateChecker.swift: AppVersion :4 -> AppVersion.swift. Editor/AnnotationObject.swift: RedactionStyle :5. AdvancedMode/ManifestEditor.swift: RemovedStep :4. Settings/AdvancedModeSettings: nested enums fine. Export/GIFGuideExporter, PDFGuideExporter (error enums) are minor/Low.
- Nested enums (HotkeyBinding.Modifier, CaptureManager.CaptureMode, StorageManager.AnnotationsLoad) are fine.

### M3. Long functions / view bodies (>~45 lines; none >100)
- PreferencesUI/PreferencesView.swift:144 `advancedModeTab` 97 lines; :63 `generalTab` 78 -> extract subviews `AdvancedModeSettingsForm`, `MarkerStyleSection`, `ScopeSection`, `GeneralTab` as separate files (PreferencesUI/Tabs/).
- Capture/CaptureOverlayView.swift:15 `body` 85 -> extract `SelectionLayer`, `DimLayer`, `SizeBadge`.
- Editor/EditorView+Canvas.swift:44 `canvasArea` 80 -> `CanvasScrollContainer`, `CanvasOverlays`.
- Editor/EditorView+Toolbar.swift:6 `toolbar` 72 -> subviews (see M1).
- AdvancedMode/Export/GuideExporter.swift:126 `run` 71 lines -> `prepareWorkFolder`, `renderImages`, `writeOutput`, `finish` stages.
- Capture/CaptureOverlayWindow.swift:29 `showAll` 62 lines (window creation + hosting + key handling) -> `makeOverlayWindow(for:)` per screen.
- Editor/AnnotationOverlayShape.swift:51 `content` 55; AdvancedMode/Export/ExportSheet.swift:11 `body` 48; Editor/EditorView+Header.swift:6 `headerBar` 48.
- ClickCaptureManager.swift:342 `write` 49; :158 `handle` 40; EditorWindowController.swift:122 `makeContentView` 46 (22 closure params -> pass a `EditorActions` struct); AppDelegate.swift:308 `openPreferences` 39 (three callbacks closure-injected), :29 `applicationDidFinishLaunching` 34; MenuBar/StatusItemController.swift:15 `init` 45.
- Deep nesting: none flagged beyond above; Prefs tabs and canvasArea are the nesting hot spots.

### M4. Date formatting: 2 DateFormatters built per call
Storage/FilenameGenerator.swift:64-68 ("yyyy-MM-dd_HHmmss", gregorian, injected TZ) and AdvancedMode/Export/GuideDocument.swift:132-135 ("d MMM yyyy"). Not true duplication, but both allocate a DateFormatter per call (costly). Extract `enum DateFormats { static func string(_ d: Date, pattern: String, tz: TimeZone, locale: Locale = en_US_POSIX) -> String }` with a small cache, or use `Date.FormatStyle`.

### M5. File naming/sanitising scattered
`.png` suffix logic repeated in FilenameGenerator.swift:9,19,33,59 (hasSuffix(".png"), dropLast(4)) plus SessionManifest.swift:148-153 (`Step_`, `_edited.png`, `_zoom.png` string checks) and ReviewModel.swift:330 (temp name built inline). Centralise in `FilenameGenerator`: `static func baseName(_ file: String) -> String`, `static func sibling(of: String, suffix: String) -> String`, `static func isStepImage(_ name: String) -> Bool` and use from SessionManifest/ReviewModel/StepFiles. Sanitisation itself is single-sourced (FilenameGenerator.sanitizedBaseName :31, used by StorageManager:126, GuideDocument:35) - good. `CaptionMarkup.stripBidi` is invoked ahead of it; fold bidi stripping into sanitizedBaseName to avoid callers forgetting.

### M6. Escaping
Markdown/HTML escaping spread across CaptionFormatter.swift:50 (escapes `*` and `"`), CaptionMarkup, HTMLGuideWriter, MarkdownGuideWriter. Consolidate in `enum TextEscaping { static func html(_:), markdown(_:), quotedAttribute(_:) }` (Export/TextEscaping.swift); verify before extracting since escaping rules differ per format.

## LOW

### L1. Settings access
Single SettingsStore (Settings/SettingsStore.swift) wraps UserDefaults; UpdateChecker.swift:48-50 keeps its own UserDefaults (fine, injected). No scattered `UserDefaults.standard` (only 4 refs). OK. Consider a `SettingsProviding` protocol if Preferences/Coordinator tests need it.

### L2. Singletons
Only one: `ThumbnailCache.shared` (Editor/ThumbnailCache.swift:16), used from ReviewModel.swift:409,411 and ReviewWindowController.swift:143, ThumbnailView.swift:15,38. Model layer touching a UI cache is the smell: inject a `ThumbnailInvalidating` closure/protocol into ReviewModel (it already uses closure injection for save/writeImage, :60-61, so same pattern). Static enums (SessionManifestStore, StepFiles-as-struct, PermissionsManager, ManifestEditor) act as hidden singletons: PermissionsManager is static and called directly from AppDelegate:164 and ClickCaptureManager defaults (:76) -> hide behind `PermissionChecking` protocol.

### L3. UI doing IO / layering
- EditorWindowController owns file persistence: writeBaseImage :351, persist :253, autoSave :235, rename :211, annotations load :175 call StorageManager and FileManager directly from a window controller. Move to an `EditorDocument` service (see M1).
- ReviewModel.swift:302-417 does PNG replacement with temp-file moves (:330) and ThumbnailCache calls; UI-adjacent model owns IO (partially injected via `writeImage`/`save`).
- PreferencesView.swift:272 and ReviewWindowController.swift:107 present NSOpenPanel from views/controllers; Panels helper (H5) fixes.
- AppDelegate.swift:99-107 open panel and :280 CGWindowList queries.
- FileManager.default used in 11 files / 54 refs, including SessionManifest.swift, GuideDocument.swift, MarkdownGuideWriter.swift, RecentCapturesFinder.swift; only ReviewModel/StepFiles take injected IO. A `FileSystem` protocol (move/trash/write/exists) would make StepFiles, GuideExporter, StorageManager testable without disk; low priority since tests use temp dirs.

### L4. Protocols for testability: what exists
Good: StepImageSource, ClickDescribing, SessionEventSource, closure injection in ReviewModel/ClickCaptureManager. Missing: StorageManager (concrete, passed to CaptureManager, AdvancedModeCoordinator), CaptureManager (ScreenCaptureKit direct), UpdateChecker (URLSession.shared at :73 -> inject URLSession), HotkeyManager (Carbon), PermissionsManager, PDFGuideExporter (WKWebView). Add `ScreenshotStoring`, `HTTPFetching` first.

### L5. Misc
- AppDelegate.swift:164 `MainActor.assumeIsolated` indicates actor isolation not declared on AppDelegate: annotate AppDelegate/CaptureManager `@MainActor` and drop assumeIsolated.
- Test file ReviewModelTests.swift 960 lines: split by the ReviewModel extensions in M1 (ReviewModelCaptionTests, ReviewModelDeleteTests, ReviewModelImageTests, ReviewModelUndoTests); ClickCaptureManagerTests 418.


# Appendix: security

# Clipr security and privacy review

Repo: /Users/shancox/Documents/Apps/Clipr (main @ b31470e). Read-only review; nothing was modified.
Scope: Sources/Clipr, Scripts/, Info.plist, Package.swift, git history. There is no entitlements file and no sandbox.

## Summary table

| # | Severity | Area | Finding |
|---|----------|------|---------|
| 1 | High | Privacy / export | Close-up (zoom) images are never re-rendered after edits, so redactions and crops are bypassed when "Include close-ups" is on |
| 2 | High | Privacy / typing steps | Terminal denylist is incomplete: web terminals (xterm.js), IDE terminals, remote desktop and VMs record passwords as plaintext captions |
| 3 | Medium | Distribution | Ad-hoc signature with no hardened runtime on an app that holds Accessibility, Input Monitoring and Screen Recording (DYLD injection inherits the grants; every update resets TCC) |
| 4 | Low | File system | `zoomFile` from session.json is used as a path without validation (path traversal read into exports); step PNGs can be symlinks |
| 5 | Low | Privacy | Click captions take AXValue from AXStaticText/AXCell, so on-screen content (revealed secrets, message text) can end up in captions |
| 6 | Low | Privacy | Deleted steps go to the Trash; raw unredacted PNGs stay in the session folder; files use default 0644/0755 permissions |
| 7 | Low | Export | Markdown escaping doesn't stop GFM autolinks (`www.x.com`, `https://…`, emails) built from AX labels |
| 8 | Low | Updates | Release `html_url` from the GitHub API is opened with `NSWorkspace.open` without checking the scheme or host; the check runs at launch with no opt-out |
| 9 | Low | Robustness | Untrusted sidecars and PNGs are decoded with no size limits (decompression bomb or huge annotation geometry) |
| 10 | Info | Event tap | The tap re-enables on `tapDisabledByUserInput` as well as on timeout, and does window-list work on the main thread inside the callback |
| 11 | Info | Typing | Burst check compares only the first and last focused element; keys typed in between are not re-verified |

---

## 1. High: close-ups bypass redaction and crop

- `ClickCaptureManager.swift:374-377` writes `Step_NN_zoom.png` once, at capture time, cropped from the raw frame.
- The editor and Review never regenerate it. No code under `Editor/` or `ReviewModel` references the zoom file except `replaceImage` and its undo, which clear or restore `zoomFile` (`ReviewModel.swift:351,395`). Review doesn't show the close-up at all, so the user never sees it.
- `GuideDocument.swift:118` adds it to the export when `includeZoom` is on. `GuideImages.render` (`GuideImages.swift:40`) looks for `Step_NN_zoom_annotations.json`, which never exists, so the close-up is exported raw.

**Scenario:** the user records a login flow with zoom-on-click on. They click into an account-number or API-key field, then pixelate that area (or crop it out) in the editor. They export a PDF or HTML with "Include close-ups". The guide shows the redacted step image next to a 30%-width close-up of the original, unredacted pixels around the click. The same thing happens with clipboard RTFD and Markdown `images/step-NN-zoom.*`.

**Fix:** at export time, build the close-up from the flattened (annotated, cropped) step image using the stored `clickPoint`, instead of reading the stored `_zoom.png`. Otherwise, delete or regenerate `_zoom.png` whenever the step's sidecar or raw image changes, and drop the close-up if the step has any `.blur` annotation or a crop. Add a test: a pixelated region under the click must not appear unredacted in the exported close-up.

## 2. High: typing steps capture passwords in apps the denylist misses

`ClickDescriber.swift:55-64,81-90`. Fail-closed applies only to `AXSecureTextField`, AX read failures, and 7 terminal bundle IDs. Many password prompts are none of those, so they come back `.notSecure`:
- **Browser-based terminals** (xterm.js: GCP/AWS/Azure cloud shells, Jupyter, code-server, GitHub Codespaces). They take input through a hidden `<textarea>`, which is AXTextArea, not secure, inside Safari/Chrome. A `sudo` or `ssh` password is stored as `Type "hunter2" in **Terminal input**`.
- **IDE and other terminals**: VS Code (`com.microsoft.VSCode`), Cursor, JetBrains (`com.jetbrains.*`), Zed, Nova, Hyper (`co.zeit.hyper`), Tabby, Termius, Prompt, and `com.apple.dt.Xcode` console input.
- **Remote desktop and VMs**: Screen Sharing (`com.apple.ScreenSharing`), Microsoft Remote Desktop / Windows App, Parallels, VMware Fusion, UTM, Citrix, AnyDesk, TeamViewer. Guest password fields are invisible to AX. The host view reports a non-secure role, and the host-side `IsSecureEventInputEnabled()` is false.
- **Web PIN/OTP widgets and "show password" toggles** that use `type=text`.

The first 60 characters are kept (`CaptionFormatter.swift:15,35-38`). They land in session.json, which is pretty-printed plaintext, and in every export format. `IsSecureEventInputEnabled` (`SessionEventTap.swift:89`) doesn't help in any of these cases.

Typing steps are opt-in (`AdvancedModeSettings.swift:16`, default false), which keeps this from being Critical.

**Fix (defence in depth):**
- Allowlist instead of denylist. Record text only when the focused role is one of AXTextField, AXSearchField, AXComboBox or AXTextArea, and the app isn't a known terminal, IDE, remote or VM host.
- Expand the denylist (prefix-match `com.jetbrains.`, and add the IDs above).
- Treat an AXTextArea whose label or description contains "terminal" (xterm.js sets `aria-label="Terminal input"`) as `.unknown`.
- Treat AXWebArea or an empty role with a non-native host as `.unknown`.
- Consider storing typing captions as `Type "••••" in **Field**` until the user reveals them in Review, or showing a one-time warning when typing steps are turned on.
- Add `ClickDescriberTests` for xterm.js-style and VS Code focus.

## 3. Medium: ad-hoc signing, no hardened runtime, not notarized

`Scripts/build-app.sh:35`: `codesign --force --deep --sign - "$APP"`. The built app shows `flags=0x2(adhoc)`, no `runtime` flag, and `TeamIdentifier=not set`. `release.sh` zips that bundle for the Homebrew cask.

- Without hardened runtime, dyld honours `DYLD_INSERT_LIBRARIES`. Any process running as the user can start Clipr with an injected dylib (for example `open --env DYLD_INSERT_LIBRARIES=… -a Clipr`, or a LaunchAgent). That code then runs with Clipr's TCC grants: Accessibility (reading or driving other apps), Input Monitoring (a global keylogger) and Screen Recording. This is the standard way into a TCC grant through a non-hardened app.
- An ad-hoc signature's designated requirement is the cdhash. Every rebuild or update invalidates the TCC grants, so users learn to re-approve high-risk permissions on every release.
- Without notarization, users have to bypass Gatekeeper (`--no-quarantine` or `xattr -d`), which also trains bad habits. Release integrity rests only on the cask sha256 and the GitHub account.
- `--deep` is deprecated for signing.

**Fix:** sign with `--options runtime` now. This works even with an ad-hoc identity and strips DYLD_* variables. Better: use a Developer ID (or at least a stable self-signed identity, so the designated requirement survives updates), hardened runtime, notarization and stapling. Drop `--deep`. Keep entitlements empty (no `disable-library-validation` or `allow-dyld-environment-variables`).

## 4. Low: untrusted `zoomFile` path in session.json; symlinked step files

- `GuideDocument.swift:118`: `folder.appendingPathComponent(record.zoomFile)`. `zoomFile` comes straight from session.json. `SessionManifestStore.load` (`SessionManifest.swift:129-145`) only validates `file` against the directory listing. A crafted value like `"../../Pictures/private.png"` (or anything decodable by ImageIO) is read, rendered and embedded in the exported guide that the user then shares.
- `rawStepFiles` (`SessionManifest.swift:149`) accepts any directory entry named `Step_*.png`, including symlinks to images elsewhere.

**Preconditions:** someone else's session folder has to end up inside the user's save folder, for example a shared or synced save folder or an unzipped session someone sent. That keeps this Low.

**Fix:** accept `zoomFile` only if it equals `FilenameGenerator.zoomName(fromStep: record.file)`, or derive it and ignore the stored value. Reject components with `/` or `..`. Resolve symlinks and require that the resolved path stays inside the session folder. Skip non-regular files (`.isRegularFileKey`, and reject `.isSymbolicLinkKey`).

## 5. Low: click captions can quote on-screen content

`ClickDescriber.swift:110,135`. For AXStaticText, AXCell, AXButton and similar roles, the element's AXValue (up to 200 characters, then trimmed to 60) becomes the caption.

**Scenario:** clicking on a revealed password, recovery code or one-time code in a password manager or web page, on a message body in Mail or Messages, or on a spreadsheet cell, produces `Click **<that text>**`. Excluding focused fields and AXSecureTextField is good, but static text can be secret too.

**Fix:** prefer the title and description attributes. Use AXValue only for AXButton, AXLink, AXMenuButton and AXPopUpButton. Drop AXStaticText and AXCell, or cap them much shorter, and skip strings that look like secrets (long runs of high-entropy characters or digits).

## 6. Low: data that outlives a delete; raw pixels kept; default permissions

- Deleting a step (`StepFiles.swift:31-39,64-76`) moves the raw image, sidecar, zoom and edited preview to the user's Trash, where they stay until the Trash is emptied (and in Time Machine backups). This is needed for undo, but the UI should say so. Deleting a Recent uses permanent `removeItem` (`StorageManager.swift:109-115`), which is inconsistent.
- Redaction only affects `_edited.png` and exports. `Step_NN.png` and `Screenshot_*.png` keep the original pixels, and the sidecar can be removed to undo the redaction. Users who share the session folder or the raw file leak the original. Exports are flattened, which is correct.
- Files and folders are created with the default umask (0644/0755) (`StorageManager.swift:189,252,261`, `SessionManifest.swift:74`). This is fine under `~/Pictures` (0700), but if the user picks `/Users/Shared`, an external disk, or an iCloud or Dropbox folder, screenshots and typed-text captions are readable by others or synced off the machine.

**Fix:** create session folders with 0700 and files with 0600, using `FileManager.createDirectory(attributes: [.posixPermissions: 0o700])` and `setAttributes`. Note in the Delete UI that items go to the Trash. Optionally offer "Delete permanently" when a session ends.

## 7. Low: Markdown export allows GFM autolinks

`CaptionMarkup.escapeMarkdown` (`CaptionMarkup.swift:106-114`) escapes ``\ ` * _ [ ] < > ~ & #`` but leaves bare URLs, `www.` domains and email addresses alone. GitHub, GitLab and Notion autolink these, so an AX label like `www.evil-login.example` becomes a clickable link in the published guide. HTML, RTF and the Review UI handle this correctly: `CaptionText` strips links, and HTML escapes everything.

**Fix:** break autolinks, for example by inserting U+200B (or `\` before `.` and `:`) in `://`, `www.` and `@`, or wrap captions that contain a URL in a code span.

## 8. Low: update checker

`UpdateChecker.swift:126` opens `release.htmlURL` from the API response with `NSWorkspace.shared.open`, with no check that it is `https://github.com/FabricShancox/Clipr/...`. A compromised GitHub account, API or TLS interception could make it open a `file://` URL or a custom-scheme URL. The check also contacts api.github.com at every launch, at most once a day (`AppDelegate.swift:61`), with no preference to turn it off.

**Fix:** require `scheme == "https"` and `host == "github.com"` with the expected path prefix; otherwise open a hard-coded releases URL. Add an "Automatically check for updates" toggle.

## 9. Low: no size limits when decoding untrusted files

- `GuideImages.swift:50` and `ReviewWindowController.swift:130` call `NSImage(contentsOf:)` for a full decode. A 60k×60k PNG (a few KB compressed) allocates more than 14 GB.
- `StepFiles.replacementPNG` decodes the chosen file at full size (`kCGImageSourceThumbnailMaxPixelSize: max(w,h)`).
- Sidecar JSON (`StorageManager.swift:65-73`) is decoded without limits on annotation count, coordinate size, font size or stroke width.

The files come from the user's own save folder or a file the user picked, so impact is limited to a crash or hang.

**Fix:** check `kCGImagePropertyPixelWidth`/`Height` against a cap (for example 16k×16k, or 200 MP) before decoding. Cap sidecar size (for example 5 MB), annotation count, and numeric ranges.

## 10. Info: event tap details

- `SessionEventTap.swift:75-78` re-enables on `.tapDisabledByUserInput` as well as `.tapDisabledByTimeout`. Re-enabling after a timeout is standard. A user-input disable is the system's signal, so log it and reconsider rather than re-arming silently. The NSLog fires on every re-enable and can flood if the tap keeps timing out.
- `SessionEventTap.swift:82` runs `WindowPicker.ownerPIDOfWindow` (a CGWindowList query) on the main thread for every mouse-down. The callback is meant to be cheap; slow calls are what cause the timeout disables.
- Good: the tap is listen-only, keys are only in the mask when Input Monitoring is preflighted (`ClickCaptureManager.swift:99,110-113`), Accessibility is checked before start, `stop()` disables, removes and invalidates the tap and is idempotent, and `deinit` stops it.

## 11. Info: focus checked only at the start and end of a burst

`ClickCaptureManager.swift:261-263` compares the field read at the first key with the one read at the last key. Keys in between are read (`readFocusedField`) but only the last read is kept. If focus moves to a non-secure-input password field mid-burst and back, without a click or Tab, those characters are kept. This is unlikely, but the fix is cheap: keep a running "all reads were the same non-secure element" flag instead of just the last read.

---

## Done well

- Secure input: characters are blanked inside the tap when `IsSecureEventInputEnabled()`, the whole burst is discarded if any key was secure, and AX read failures or a missing focus fail closed (`.unknown`). Typing steps are off by default, and a dropped burst skips the screenshot too.
- The focused element's AXValue is never used in labels, title-UI-element values are skipped for fields and secure fields, and labels are capped.
- Captions are treated as untrusted everywhere: Review strips links (`CaptionText`); HTML escapes every character and allows only strong/em/code; HTML export has a strict CSP (`default-src 'none'; img-src data:; style-src 'unsafe-inline'`); bidi controls are stripped; Markdown escaping is careful apart from autolinks.
- PDF: offscreen WKWebView with JavaScript off, `baseURL: nil` and embedded-only images. It prints to a per-user temp file, validates the PDF, then replaces the destination. Export staging is atomic, with a backup and restore for Markdown `images/`.
- Rename sanitizes `/`, `:`, `\`, control characters and leading dots. `step.file` is validated against the directory listing. Undo and restore are all-or-nothing.
- The control panel uses `sharingType = .none`, and Clipr's own windows are excluded from captures.
- No secrets in the tree or in git history (157 commits scanned). `.gitignore` covers `.build/`, `Clipr.app/` and `dist/`. No curl-pipe-to-shell, no third-party dependencies, no URL schemes, NSServices or AppleScript surface.
- Logging records only error types and file names, never captions or typed text.


# Appendix: bugs-core

# Clipr core bug hunt (everything except Sources/Clipr/AdvancedMode)

Repo: /Users/shancox/Documents/Apps/Clipr @ main (b31470e). I only read the code and made no changes.
`swift build` is clean (only the unhandled-resource warning). `swift test`: 466 XCTest tests pass, 0 fail.
Toolchain: Swift 6.2.3 with the macOS 26.2 SDK, so `View` is `@MainActor`. That means the `Task {}` inside `EditorView.scheduleAutoSave` runs on main. It is not a threading bug.

Severity key: **H** = data loss, a stuck or broken app, or system-wide input hijack. **M** = wrong output or a broken common workflow. **L** = edge case, cosmetic, or performance.
Items tagged **UNVERIFIED** follow from reading the code but need a manual run to confirm.

---

## High

### H1. Hotkey recorder accepts bare keys, so any letter, Esc or Delete can become a system-wide hotkey
- `PreferencesUI/HotkeyRecorderView.swift:41-50`, `PreferencesUI/PreferencesView.swift:67-76, 216-219`, `Hotkey/HotkeyManager.swift:25`
- **Scenario:** Click the Capture recorder and press `A`, or press `Esc` to back out. `KeyCatcherNSView.keyDown` builds `HotkeyBinding(keyCode:, modifiers: 0)` and the binding setter saves it and re-registers it at once. `RegisterEventHotKey` with no modifiers succeeds, so every `a` (or Esc) typed in **any app** now opens the capture overlay instead of reaching that app. The setting persists across relaunches. Escape is the natural "cancel" key, so this is easy to trigger by accident. Tab, Return and Delete behave the same way.
- **Fix:** In `keyDown`, treat Esc with no modifiers as cancel (set `isRecording = false` and don't call `onKeyDown`). Reject bindings with no ⌘/⌃/⌥ modifier unless the key is F1–F20, and beep or show a hint. Also reject a binding equal to the other Clipr binding before saving.

### H2. Cropping an image opened with "Open Image…" overwrites the user's original file, and JPEG/HEIC/TIFF/GIF files get PNG bytes under the old extension
- `AppDelegate.swift:99-107` (rawURL = the picked file), `Editor/EditorWindowController.swift:336-337, 351-353, 376-377`, `Storage/StorageManager.swift:38-40, 248-262`, `Storage/FilenameGenerator.swift:8-22`
- **Scenario:** Open `~/Desktop/photo.jpg` and crop or resize the canvas. `writeBaseImage` calls `overwriteRawCapture(rawURL)` on the user's own file. `write(... overwrite: true)` **deletes** `photo.jpg` and writes PNG data under that name. The original JPEG, its EXIF data and its colour profile are gone, and nothing can undo it (crop also clears the undo history). The file now has a `.jpg` name with PNG contents.
- Companion files are also named badly for non-PNG files. `editedName(fromRaw: "photo.jpg")` gives `photo.jpg_edited`, a PNG with no extension, and the sidecar becomes `photo.jpg_annotations.json`.
- **Fix:** When the opened file isn't in the save folder, or isn't a `.png`, import it first: copy it into `baseFolder` as a fresh `Screenshot_…png` and edit that copy. At minimum, never overwrite a non-PNG and derive companion names from `deletingPathExtension()`.

### H3. Overwriting the raw capture is delete-then-write and not atomic, so a failed write loses the capture while the alert says it was "left unchanged"
- `Storage/StorageManager.swift:257-261`, `Editor/EditorWindowController.swift:351-366`
- **Scenario:** Crop or resize while the disk is full, the volume is ejected or permission is denied. `removeItem(at: finalURL)` succeeds, then `pngData.write(to:)` throws. The raw capture is gone from disk. `writeBaseImage` still shows "…could not be written, so it was left unchanged". On the next reopen the image is missing, while the sidecar and `_edited.png` are orphaned. The same path is used for `_edited.png` and the step-zoom files.
- **Fix:** `try pngData.write(to: finalURL, options: .atomic)` with no prior `removeItem`, since an atomic write replaces in place. Or use `FileManager.replaceItemAt`.

### H4 (UNVERIFIED). Pressing the capture hotkey while a modal alert or open panel is up can leave a screen-covering overlay nobody can use
- `AppDelegate.swift:163-179`, `Capture/CaptureOverlayWindow.swift:29-90`. Modal sessions are started at `AppDelegate.swift:105,134,157,230,277`, `PermissionAlert.swift:12`, `UpdateChecker.swift:121,137` and `PreferencesView.swift:276`.
- **Scenario:** The "Capture failed" alert, the launch-time "shortcut couldn't be registered" alert, the update alert, or the Open Image panel is on screen, and the user presses ⌘⇧2 again. If the Carbon hotkey fires during `runModal` (it usually does), `beginCapture` puts `.screenSaver`-level overlays over every display. The app is in a modal session, so the overlays get no mouse or key events: no drag and no Esc. Meanwhile the alert they would have to dismiss is underneath them. The only way out is ⌥⌘Esc.
- **Fix:** In `performCapture` (and `toggleAdvancedMode`), `guard NSApp.modalWindow == nil else { NSSound.beep(); return }`. Prefer sheets and `begin` over `runModal` for these alerts.

---

## Medium

### M1. Default Advanced Mode hotkey ⌘⇧3 is macOS's own "Save picture of screen as a file" shortcut
- `Settings/HotkeyBinding.swift:62` (keyCode 20 = kVK_ANSI_3)
- **Scenario:** On a fresh install the user presses ⌘⇧3 to start Advanced Mode. The system symbolic hotkey normally wins: a full-screen PNG lands on the Desktop and Advanced Mode may never toggle. If both fire, every start or stop also drops a screenshot. Registration may still return `noErr`, so the "couldn't be registered" alert never appears.
- **Fix:** Pick a default that doesn't collide with a system shortcut (e.g. ⌃⌥⌘A) and migrate stored values equal to the old default.

### M2. Undo/redo leave a stale selection, so a later color, stroke or nudge silently wipes the redo stack
- `Editor/EditorView+Persistence.swift:46-56` (selection never pruned), `EditorView+ColorStrokeBindings.swift:14-51`, `EditorView+AnnotationEditing.swift:22-30, 105-121`, `EditorView+KeyboardShortcuts.swift:39-45`
- **Scenario:** Draw a box (it auto-selects), press ⌘Z (the box disappears but `selectedIDs` still holds its id), then click a swatch or press an arrow key. `colorBinding` and `nudgeSelected` are active because `selectedIDs` isn't empty. Each one calls `mutateAnnotations`, which pushes a no-op undo entry and runs `redoStack.removeAll()`. ⇧⌘Z can no longer bring the box back. Esc first "clears" an invisible selection instead of closing, and the Delete button stays enabled.
- **Fix:** In `undo()` and `redo()`, run `selectedIDs.formIntersection(annotations.map(\.id))` and clear `editingTextID` if it no longer exists. In `mutateAnnotations`, skip the push when the transform left the array unchanged.

### M3. Each text keystroke is its own undo step, and undo brings back the empty text boxes that `finishTextEditing` removed
- `Editor/AnnotationCanvasView+TextEditing.swift:49-57, 73-77`, routed via `annotationsBinding` (`EditorView+Persistence.swift:39-44`)
- **Scenario A:** Type "hello world" into a text box. After finishing, ⌘Z removes one character at a time, so 11 undos are needed for one edit.
- **Scenario B:** Click with the Text tool, then press Esc without typing. `finishTextEditing` removes the empty annotation through the binding, which pushes `[…, emptyText]` onto the undo stack. One ⌘Z brings back the empty (bordered by default) text box that `finishTextEditing` exists to prevent. It is then hit-tested and saved to the sidecar.
- **Fix:** Edit the text in a local buffer and write it back once in `finishTextEditing`, as one undo step that replaces the "add empty text" step. Or coalesce undo entries while `editingTextID` is set and drop both entries when the text is discarded.

### M4. Text longer than the box is truncated on screen and clipped in the export, and the box never grows
- `Editor/AnnotationCanvasView+ShapeCommit.swift:29-33` (click-placed box is 160 × (fontSize+10)), `AnnotationOverlayShape.swift:70-80` (`Text` in a fixed frame), `TextDrawing.swift:44` (`min(measured.height, frame.height)`)
- **Scenario:** Click with the Text tool and type a sentence wider than 160pt. The `TextEditor` wraps it to several lines and scrolls inside a ~28pt-tall box. On finish, the overlay `Text` shows only line 1 with "…", and `_edited.png`, Copy and Save As draw only what fits. Words the user typed vanish from the output.
- **Fix:** On every text change, re-measure with `verticallyAlignedTextRect`/`boundingRect` and grow `frame.height` (downward on screen) to fit.

### M5. Text can't be edited after it's placed
- `editingTextID` is only assigned in `AnnotationCanvasView+ShapeCommit.swift:40`. No double-click or Return-to-edit exists anywhere.
- **Scenario:** Finish a text box, notice a typo, and there's no way back in. The user has to delete it and retype, losing style and position.
- **Fix:** Add a double-click on a `.text` annotation that sets `editingTextID`, and Return when exactly one text annotation is selected.

### M6. Long diagonal arrows and freehand strokes grab every click inside their whole bounding box, with any tool
- `Editor/AnnotationObject.swift:31-44, 49-67` (`outlineContains` only narrows rect and ellipse, so arrow and freehand fall through to `true`), `AnnotationCanvasView+Hover.swift:29-40`, `+Gestures.swift:57-80`
- **Scenario:** Draw an arrow from the top-left to the bottom-right of a capture, then try to draw a box anywhere in the middle. Each press hits the arrow's bounding rectangle, so the arrow gets selected and moved and no box is drawn. A pen squiggle does the same over its whole bounding box. Hover shows the hand cursor across that empty area.
- **Fix:** For `.arrow`, hit-test distance to the segment (≤ tolerance + head). For `.freehand`, test distance to the polyline. Keep the bounding box only as a cheap pre-filter.

### M7. Changing the capture while the Save As panel is open exports the new image with the old annotations
- `Editor/EditorWindowController.swift:289-315` (completion reads `self.image` at Save time), `:401-409` (`present` swaps `image`)
- **Scenario:** Open Save As… (⇧⌘S), then press the capture hotkey (it's global) and take a shot. `present()` replaces `image` and `rawURL` while the sheet stays up. When the user clicks Save, the file contains the new capture with the previous capture's annotations drawn on it. `hideOwnWindows` also orders out a window with a sheet attached. The Recents `loadCapture` path has the same problem.
- **Fix:** Snapshot `image` and `annotations` when the panel opens and flatten those. Or make `present()` defer, or route to a new window, while `window.attachedSheet != nil`.

### M8. Deleting from Recents is permanent with no confirmation, and failures are hidden
- `Editor/EditorView+Sidebar.swift:48-61`, `Storage/StorageManager.swift:109-115`
- **Scenario:** The small × sits at the corner of every thumbnail. One mis-click calls `removeItem` on the raw file, `_edited.png` and the sidecar. They don't go to the Trash and there's no undo. If the delete fails (`try?`), the tile is still hidden via `deletedRecentURLs`, so the user thinks it worked.
- **Fix:** Use `FileManager.trashItem` (or `NSWorkspace.recycle`) and surface errors. Optionally confirm, or offer an undo toast.

### M9. Editor is hard-coded to a dark palette but never forces dark appearance, so light mode has low-contrast system controls
- `Editor/EditorColors.swift` (fixed dark colors), `EditorView+Header.swift:16-47`. Nothing sets `window.appearance` or `.preferredColorScheme`. Grep confirms no appearance code outside AdvancedMode.
- **Scenario:** With macOS in Light mode, the header's default-style `Button`s (Reveal, Save As…), the `Menu`, the rename `TextField` and the popover's Stepper/TextField render with light bezels on the `#1C252E` bar. `.foregroundColor(EditorColors.t1)` (white) makes header button labels white on light-grey bezels.
- **Fix:** `window.appearance = NSAppearance(named: .darkAqua)` in `EditorWindowController.init`, or `.preferredColorScheme(.dark)` on `EditorView`.

### M10. Copy-style changes in Preferences and in the editor overwrite each other, and the editor menu shows stale checkmarks
- `Editor/EditorView.swift:89` (`@State copyStyle` seeded once), `EditorView+Header.swift:55-60` (writes the whole struct back), `PreferencesUI/PreferencesView.swift:21, 111-125` (same stale `@State`)
- **Scenario:** With an editor open, turn on "Drop shadow" in Preferences. The editor menu still shows it off, although Copy uses `settings.copyStyle` and does add the shadow. Toggling Border in the editor menu then writes `CopyStyle(border: true, shadow: false)` and silently turns the shadow back off. The reverse also happens.
- **Fix:** Use `@AppStorage("copyBorder")`/`@AppStorage("copyShadow")` in both places, or toggle a single key instead of writing the whole struct.

### M11. Annotation sidecars are written for captures and images that were never edited
- `Editor/EditorWindowController.swift:102-115, 253-260` (`persist` always calls `saveAnnotations`; `windowDidResignKey` and `windowWillClose` call it)
- **Scenario:** Open `~/Desktop/photo.png` via Open Image… and click another app. `photo_annotations.json` (`[]`) appears on the Desktop. Every capture viewed in the editor gets an empty sidecar. If the opened file's folder is read-only (a DMG, a shared drive), every flush fails, is only `NSLog`ged, and annotations are lost on close with no warning.
- **Fix:** Skip the sidecar write when annotations are empty and no sidecar exists, or track a dirty flag. Show an alert, once per window, when a persist from close or quit fails.

---

## Low

| # | File:line | Issue / scenario | Fix |
|---|---|---|---|
| L1 | `Editor/ThumbnailCache.swift` + `EditorWindowController.swift:326-382` | After a crop or canvas resize, `ThumbnailView.init` seeds from the cache keyed by URL, so the Recents tile keeps showing the **uncropped** image for the rest of the session. | `ThumbnailCache.shared.remove(rawURL)` in `writeBaseImage` on success. |
| L2 | `Editor/AnnotationCanvasView+ResizeHandles.swift:63-72, 113-122` | A plain click on a resize handle (minimumDistance 0) commits `annotations[index] = final` with an unchanged frame. That adds a no-op undo entry and clears redo. Same class of problem as M2. | Skip when `final == annotations[index]`. |
| L3 | `Editor/AnnotationRenderer.swift:143-155` | A redaction that extends past the canvas edge pixelates only the clipped region, then **stretches** it into the full `frame`. Blocks get distorted and misaligned with the preview, which draws differently. Still opaque. | Clip `frame` to the canvas before drawing, or draw into `region`'s rect. |
| L4 | `Editor/AnnotationOverlayShape.swift:136-142` | The pixelated preview is recomputed (cgImage fetch, crop, two CGContexts) on every body evaluation, e.g. every hover or drag frame, for every redaction. This causes noticeable lag on large Retina captures with several redactions. | Cache per `(annotation.frame, image)` or precompute in a `@State`. |
| L5 | `Editor/EditorView+CanvasResizeHandles.swift:44-54`, `CaptureGeometry.swift:66-77` | Canvas resize has no upper bound. Dragging a corner far outward when zoomed to 5% can request a many-GB `CGContext`. That returns nil at best and is a memory spike or jetsam at worst. | Clamp the new size (e.g. ≤ 4× the original, or ≤ 16k px). |
| L6 | `Editor/AnnotationCanvasView+TextEditing.swift:28-35` vs `AnnotationOverlayShape.swift:75-79` vs `TextDrawing.swift:16-20` | The editing `TextEditor` uses `max(width, 80)` plus NSTextView insets. The static `Text` uses the exact frame, and the export border is inset −4/−2. Text re-wraps and shifts when editing ends and again in the export. | Use one layout: same width and insets in all three. |
| L7 | `Editor/EditorWindowController.swift:384-389` | The share picker is shown `relativeTo: .zero` of the content view, so it pops from the window's corner, not the Share button. | Anchor to the button (pass its frame via a `GeometryReader`/anchor preference). |
| L8 | `Editor/EditorView+Toolbar.swift:199-235` (popover "Next" TextField) | **UNVERIFIED:** while typing in the stamp popover's number field, the main window's bare-key shortcuts (digits, Delete, Return = copy & close) may still fire through key-equivalent dispatch to the main window, since `isTextEntryActive` doesn't cover this field. | Add a `@FocusState` for that field to `isTextEntryActive`, or use the Stepper only. |
| L9 | `Editor/EditorView+KeyboardShortcuts.swift`, `+AnnotationEditing.swift:105-139`, `+Toolbar.swift:12-23` | About 25 zero-size `Button("")` shortcut carriers are visible to VoiceOver as unlabeled buttons (opacity 0 doesn't hide them). Icon-only toolbar buttons have only `.help` and no `.accessibilityLabel`. Canvas annotations are not accessible. | `.accessibilityHidden(true)` on the shortcut groups; `.accessibilityLabel` on tool buttons. |
| L10 | `MenuBar/MainMenu.swift:53-64` | No Undo/Redo menu items, so ⌘Z does nothing inside a text annotation or the rename field (NSTextView relies on the `undo:` menu action). The editor's own ⌘Z button is disabled while text is active. | Add Undo/Redo items that are enabled only when the first responder is an NSText. Or give the canvas undo its own keyboard path. |
| L11 | `AppDelegate.swift:99-107`, `142-158` | "Open Image…" from the status menu and the "Capture failed" alert don't activate the app first, so the panel or alert can appear behind the frontmost app. Preferences already fixed this. | `NSApp.activate(ignoringOtherApps: true)` before `runModal`. |
| L12 | `AppDelegate.swift` (no `applicationShouldHandleReopen`) | The app is `.regular` with a Dock icon, but clicking the Dock icon with no windows does nothing. | Implement it to open Preferences or a "Capture" affordance. |
| L13 | `Settings/SettingsStore.swift:49-63` | `launchAtLogin` reads UserDefaults, not `SMAppService.mainApp.status`. If `register()` fails (unsigned or moved app, or the user disabled it in System Settings), the toggle shows On, the error is only logged, and the setting is out of sync. | Read the status in the getter. Show an alert on error and revert the toggle. |
| L14 | `AppDelegate.swift:316-332` / `PreferencesView.swift:67-76` | When both Clipr hotkeys are set to the same combo, the second registration fails with an alert blaming "another app or macOS". The step hotkey colliding with capture or advanced only reaches `NSLog`. While recording, pressing the currently registered capture combo fires a capture instead of recording. | Check for duplicates before saving. Unregister Clipr's own hotkeys while recording. |
| L15 | `Capture/CaptureOverlayView.swift:92-98` | In Window mode with several displays, each overlay keeps its own `hoveredWindow`. Leaving a screen doesn't clear it (`.ended` is ignored), so a stale highlight stays on the other display. `CGWindowListCopyWindowInfo` also runs on every mouse move. | Clear on `.ended`. Fetch the window list once per capture. |
| L16 | `Capture/ScreenScaleFactor.swift:12-21`, `CaptureManager.swift:228` | The window-capture scale comes from the screen containing the window's **origin**. A window whose top-left is off-screen, or on a 1x display while mostly on a 2x one, falls back to `NSScreen.main` or the wrong scale, giving a blurry or oversized capture. | Use the screen with the largest intersection, or `SCWindow`'s own frame and display. |
| L17 | `Capture/CaptureManager.swift:149-155, 157-158` | `snapshotScreens` runs one `SCShareableContent` query per display in sequence before the overlay appears, which adds visible latency on 2–3 monitors. If one call hangs (seen around permission prompts), `isCapturing` stays true and every later capture is silently ignored until relaunch. **UNVERIFIED** hang. | Query content once. Add a timeout that resets `isCapturing`. |
| L18 | `Capture/CaptureOverlayView.swift:15-21, 59` | **UNVERIFIED:** only the frozen `Image` has `.ignoresSafeArea()`. On a notched MacBook display, if the hosting view reports a top safe-area inset, the drag coordinates (ZStack space) would be offset from the image and the crop (screen space) by the notch height. | Put `.ignoresSafeArea()` on the whole ZStack. |
| L19 | `Capture/CaptureManager.swift:99-138` | `handle` is nonisolated, so `captureCursor`, `storage.baseFolder` (mutated on main from Preferences), `NSScreen.backingScaleFactor`/`NSScreen.screens` and `NSPasteboard.general` are read or used off the main thread. This is a benign data race today and will be flagged under strict concurrency. | Make `CaptureManager` `@MainActor` and push only the encode/write off-main. |
| L20 | `PreferencesUI/PreferencesView.swift:151-156` + `HotkeyRecorderView.swift:16-33` | **Known-pattern check:** there is no `List` outside AdvancedMode, but the Advanced tab is a `.grouped` `Form` (List-backed on macOS) holding a native `.segmented` Picker, and its `.disabled` flips when the toggle above it changes. `KeyCatcherView` (NSViewRepresentable) also calls `makeFirstResponder` from `updateNSView`, which is a side effect during a view update. Same ingredients as the Review freeze. Not reproduced. | Toggle "Mark each click" with the pointer over the form. If it hitches, swap in the custom segmented control used in Review, and move `makeFirstResponder` into `DispatchQueue.main.async`. |
| L21 | `Editor/EditorView+Canvas.swift:10-13` | Zoom "−" clamps to 10%, but fit can be 5%, so pressing "−" at fit zooms **in** to 10%. | Use `max(fitMin, …)`, or allow 5. |
| L22 | `Editor/EditorWindowController.swift:66-70` | The editor opens on `NSScreen.main` (the key-window screen) at full `visibleFrame`, not on the screen that was captured. `minWidth: 900, minHeight: 620` overflows small displays. | Open on the captured screen; clamp to `visibleFrame`. |
| L23 | `Editor/EditorView+StampNumbering.swift` | Undoing a numbered stamp doesn't rewind `nextStampNumber`, so the next stamp skips a number. | Recompute from `annotations` after undo/redo, as `resumeStampNumbering` does. |
| L24 | Alerts and labels throughout; `PreferencesView.swift:205` | Strings are not localized, and `String(format: "%.1f s")` ignores the locale's decimal separator. Filenames correctly use `en_US_POSIX`. | `Text(value, format: .number.precision(.fractionLength(1)))`; wrap strings for localization if needed. |

---

## Checked and found OK
- Editor window lifecycle: the key monitor is removed in `windowWillClose`, and every closure captures `[weak self]`. `AppDelegate.openEditors` is pruned via `onFinished`. No retain cycle through `EditorCommands.perform`.
- The Preferences `willClose` observer removes itself, and the controller is nil'd.
- `HotkeyManager` uses `passUnretained(self)` safely because AppDelegate lives for the whole process. Unregister happens before re-register.
- Coordinate math: renderer and SwiftUI flips are consistent (their own inverses). Crop and resize deltas come from the clamped rect. Retina pixel scaling in capture crop and `pixelContext` is correct. `globalDisplayPoint` uses `NSScreen.screens.first` (the primary), which is correct for negative-origin layouts.
- The auto-save generation guard prevents a stale pre-crop debounce from overwriting. Flush happens on close, quit, switch and rename.
- The overlay crosshair push/pop is balanced. Hidden windows are restored on both the success and failure paths.
- Filename timestamps use `en_US_POSIX` with the Gregorian calendar. Rename sanitising blocks path traversal.
- `AdvancedModeSettings` decoding tolerates missing keys. A hotkey decode failure falls back to the default (silently, which is acceptable).


# Appendix: bugs-advanced

# Advanced Mode bug hunt — Sources/Clipr/AdvancedMode (incl. Export/)

Repo: /Users/shancox/Documents/Apps/Clipr @ main (b31470e). Read-only review. `swift build` clean (no
AdvancedMode warnings), `swift test` 466 tests, 0 failures.
Already-known items from the brief are not repeated. "UNVERIFIED" = reasoned from code/platform
behaviour, not reproduced.

Severity key: High = hang/data loss likely in normal use; Medium = wrong output or lost work in
plausible scenarios; Low = edge case / polish / perf.

---

## High

### H1. Native `Menu(.borderedButton)` / `.borderlessButton` still inside List rows — same attribute-cycle hang pattern (UNVERIFIED repro)
- **Where:** `ReviewRow.swift:149-159` (`imageEditMenu`, `.menuStyle(.borderedButton)`),
  `ReviewRow.swift:161-178` (`compactSizeMenu`, `.borderedButton`, dynamic `.accessibilityLabel`),
  `ReviewRow.swift:182-196` (`compactEditMenu`, `.borderlessButton`, List layout),
  toggled by hover at `ReviewRow.swift:108-122`.
- **Scenario:** c218a29 replaced only the segmented Picker. The same toolbar still holds two
  AppKit-backed pop-up buttons (SwiftUI `Menu` on macOS is an `NSPopUpButton` for both bordered and
  borderless styles). On every hover change the row flips `.opacity`, `.allowsHitTesting` and
  **`.accessibilityHidden(!showControls)`** on the container of those native controls, and
  `ViewThatFits` instantiates/measures *both* variants (so up to 3 native menus per row). Changing
  accessibility attributes of a native control during the row update is exactly the documented
  trigger of the freeze. `compactSizeMenu` also re-sets its `accessibilityLabel` whenever the size
  changes (⌘+/⌘− while hovering). List layout's `compactEditMenu` is in every row of the default layout.
- **Repro to try:** Large/Guide layout, narrow window (forces the `compactSizeMenu` branch), sweep
  the pointer over rows while pressing ⌘+/⌘−, or switch ⌘1/⌘2/⌘3 with the pointer over a row.
- **Fix:** draw "Edit" and the size menu as plain SwiftUI buttons (`.buttonStyle(.plain)`) that open
  the actions via `.contextMenu`/a popover, or move the per-row menus out of the List (one toolbar
  acting on the selection). At minimum stop toggling `.accessibilityHidden` on hover (keep the
  controls always in the AX tree, only change opacity), and replace `ViewThatFits` with a width
  check so only one variant is built.

---

## Medium

### M1. Second click inside the capture delay silently drops the first step, even on a different control
- **Where:** `ClickCaptureManager.swift:165-186`; delay up to 2 s (`AdvancedModeSettings.swift:24`).
- **Scenario:** Delay set to 1.5 s. In a dialog the user ticks a checkbox and clicks OK within 1.5 s.
  The checkbox click is cancelled (`previous.work.cancel()`), only the OK click becomes a step — the
  guide skips a step. Same when clicking quickly through a toolbar. The merge is meant for
  double-clicks but applies to any two clicks anywhere.
- **Fix:** only supersede when the new click is within `NSEvent.doubleClickInterval` *and* a few
  points of the previous one (or `event.getIntegerValueField(.mouseEventClickState) > 1`);
  otherwise fire the previous pending click immediately (`work.perform()`) and start a new pending.

### M2. Window scope captures the frontmost app's frontmost normal window, not the window that was clicked
- **Where:** `ClickCaptureManager.swift:281-290` (`.frontmostWindow`), `StepImageSource.swift:30-33, 51-58`,
  `WindowPicker.swift` `onScreenWindows()` (layer 0 only).
- **Scenarios:**
  1. Click in a floating inspector/palette or popover (non-zero layer) that overlaps the document
     window: the capture is the document window (`desktopIndependentWindow`, palette not in it), but
     the click point falls inside its bounds → the marker/zoom points at whatever lies *under* the palette.
  2. Click opens a new window (Preferences…, New Window): after the delay the new window is frontmost,
     the click's global point is mapped against the new window's origin → marker on an unrelated spot.
  3. Click on another app that doesn't activate (Dock, menu-bar extras, non-activating panels):
     screenshot of the previous app with caption "Click **Wi-Fi** in Safari" (appName is read from
     the frontmost app at capture time, not the clicked element's pid).
- **Fix:** resolve the target at click time: `WindowPicker.window(at: p, in: allLayers)` → windowID +
  owner pid; capture that window (fall back to frontmost only if it closed); take appName from the
  window owner / `AXUIElementGetPid` of the described element; drop the marker if the captured
  window is not the one under the click.

### M3. Control panel (and tooltips) in Screen / Fixed-area steps rely only on `sharingType = .none` (UNVERIFIED on macOS 15+/26)
- **Where:** `CaptureManager.swift:161-167` excludes only `windowLayer == 0` own windows;
  panel is `.floating` (`AdvancedModeControlPanel.swift:29,34`).
- **Scenario:** Screen scope on macOS 15+ (user is on Darwin 25/macOS 26), where ScreenCaptureKit is
  reported to no longer honour `NSWindow.sharingType = .none`: the Pause/Stop bar appears at the top
  of every step image; its `.help` tooltip windows (help level, default sharingType) can too when the
  pointer rests on it as a delayed capture fires. The step that `stop` flushes early
  (`ClickCaptureManager.swift:128`) fires while the pointer is on Stop, so it is the most likely to show it.
  Also, the comment in `AdvancedModeControlPanel.swift:13-16` ("steps capture only the clicked app's
  own window") is only true for Window scope.
- **Fix:** exclude every own window except the status item explicitly in the SCContentFilter (e.g.
  filter `owningApplication.processID == ownPID && windowLayer != statusLayer`, or pass the panel's
  windowNumber through `ownWindowIDs`). Note `currentOwnWindowIDs()` (AppDelegate.swift:280) is taken
  *before* `showAdvancedModePanel()` runs, so the panel is never in `ownWindowIDs` today.

### M4. Step PNG encode, zoom crop and manifest write run on the main thread — where the event tap lives
- **Where:** `ClickCaptureManager.swift:334-336` → `write` (`:342-390`) → `StorageManager.write`
  (`StorageManager.swift:248-263`, PNG encode) + `StepZoom` crop/encode + JSON save.
- **Scenario:** Screen scope on a 5K/6K display: each step encodes a ~5120×2880 PNG synchronously on
  main (hundreds of ms). The tap callback is on the main run loop, so clicks/keys during that time
  are delayed; the system can disable the tap for timeout (re-armed at `SessionEventTap.swift:75-78`,
  but events in between are lost — UNVERIFIED that listen-only taps drop rather than queue). The
  control panel and Review/editor windows also stutter per step. The header comment of
  `SessionEventTap` itself warns about main-thread work.
- **Fix:** encode PNG/zoom/sidecar data in the capture Task (off main), then hop to main only to
  assign the index, rename/write the already-encoded bytes and append to the manifest (or reserve the
  index on main first and do all file I/O on a serial background queue).

### M5. Deleting a step while its image editor is open orphans files and breaks Undo
- **Where:** `ReviewModel.swift:243-266` (no `stepsInEditor` check, unlike replace at `:324`),
  `StepFiles.swift:108-125` (`restore` fails if destination exists), `ReviewWindowController.swift:128-149`.
- **Scenario:** Double-click step 3 → editor opens. In Review press ⌫ on step 3: raw, sidecar,
  `_edited.png` go to Trash. The editor's debounced/close save then writes `Step_03.annotations.json`
  and `Step_03_edited.png` back into the session folder (orphans with no raw). ⌘Z: `restore` tries
  to move the sidecar back, `moveItem` fails because the editor's new file exists, everything is
  rolled back and the banner says "Couldn't restore Step_03.png — it's no longer in the Trash"
  (wrong reason); the step is unrecoverable from Review.
- **Fix:** refuse delete (and undo/redo of a delete) for ids in `stepsInEditor` with
  `editorOpenBanner`, or close/flush the editor first; in `restore`, treat an existing destination
  sidecar/edited file as "replace" (trash the newer one) rather than failure.

### M6. Same step can be opened in two editors; last writer wins
- **Where:** `ReviewWindowController.swift:128-149` (`openEditor` never checks `openEditors`),
  callers `ReviewRow.swift:139, 155, 226`.
- **Scenario:** Double-click the thumbnail, then later choose Edit Image… (or click "Edit" again)
  while the first editor is behind Review. Two `EditorWindowController`s load the same sidecar and
  both auto-save `Step_NN.annotations.json` / `_edited.png`; annotations added in one are wiped by
  the other's next save.
- **Fix:** if an editor for `step.id` is already in `openEditors`, bring it front instead of opening another.

### M7. PDF export of a long session can hit the fixed 30 s timeout (UNVERIFIED timing)
- **Where:** `PDFGuideExporter.swift:24, 78-82` (timeout armed at load start, never extended
  when printing starts), `GuideExporter.swift:161-172`.
- **Scenario:** 200–400 steps → the embedded-HTML string is hundreds of MB of base64
  (`HTMLGuideWriter.swift:78`); WebKit load + layout + paginated print of hundreds of pages can take
  longer than 30 s, so the export always fails with "Couldn't create the PDF. Try exporting as HTML instead."
- **Fix:** scale the timeout with step count, or re-arm/cancel the timer in `didFinish` once printing
  has started (the user can still Cancel); consider linked images from a temp folder via
  `loadFileURL(_:allowingReadAccessTo:)` instead of one giant data-URI string.

### M8. Typing/manual steps in Screen scope capture the display the *mouse* is on, not where the typing happened
- **Where:** `ClickCaptureManager.swift:247, 261, 153` → `scopeTarget(for: nil)` →
  `.screenContaining(NSEvent.mouseLocationQuartz)` (`:286`).
- **Scenario:** Two displays; user clicks a field on display 2, moves the pointer away to display 1
  and types; the "Type …" step is a screenshot of display 1.
- **Fix:** for typing steps use the frame of the focused element/window (AX `kAXPositionAttribute`
  read at burst start, already done in `focusedField`) or the screen of the last click.

---

## Low

### L1. Session folder collision reuses an existing folder
- **Where:** `StorageManager.swift:186-194` (`createDirectory(withIntermediateDirectories: true)`
  doesn't fail if it exists), name has 1-second resolution (`FilenameGenerator.sessionFolderName`).
- **Scenario:** Two sessions started in the same second (manual-step hotkey + stop + start fast), or
  the repeated local hour at DST fall-back / timezone change: the new session writes its own
  `session.json` over the old one (old captions lost; old PNGs reappear as caption-less "Manual"
  steps; new steps become `Step_01_1.png`). If a Review is open on the old session it now races the
  capture writes. DST/timezone also break the name-order assumption in
  `AdvancedModeCoordinator.latestSessionWithSteps` (`:90-96`).
- **Fix:** create the leaf with `withIntermediateDirectories: false` and add a suffix on
  `fileExists`; use UTC (or include offset) in the timestamp.

### L2. Failed tap start leaves an empty Session folder
- **Where:** `ClickCaptureManager.swift:96-116` — folder created at `:96`, `eventSource.start` may throw at `:110`.
- **Fix:** `removeItem(at: folder)` in a `catch` around the tap start.

### L3. Cursor trail carries pre-pause movement into the first click after Resume
- **Where:** `ClickCaptureManager.swift:41-43, 159` — `handle` ignores events while paused but `trail`
  is never drained on pause/resume.
- **Scenario:** Move around, pause, move elsewhere, resume, click: the trail annotation includes
  points from before the pause (usually cut by `StepAnnotationFactory.trail`'s last-run logic, but a
  pre-pause path inside the image is drawn as if it led to the click).
- **Fix:** `_ = trail.drain()` in the `isPaused` didSet (both directions).

### L4. A click made just before Pause is still captured after Pause, showing post-pause screen
- **Where:** `ClickCaptureManager.swift:41-43` (pause doesn't touch `pending`), `:180-186`.
- **Fix:** on pause, either fire the pending click immediately or cancel it (and release its slot).

### L5. Export doesn't flush open image editors
- **Where:** `ReviewWindowController.swift:89-94` calls `model.flush()` only; `flush()` (`:64-67`)
  which also calls `editor.flushPendingSave()` is not used.
- **Scenario:** Annotate in an editor and press ⇧⌘E in Review within the editor's 800 ms debounce:
  the export renders the raw image + the *previous* sidecar, missing the last annotation.
- **Fix:** call `flush()` in `showExport()`.

### L6. Raw HTML typed by the user disappears from exported captions
- **Where:** `CaptionFormatter.swift:45-51` escapes only `*` and `"`; `CaptionMarkup.swift:31`
  drops `inlineHTML` runs; Review's `CaptionText` likewise renders through Markdown.
- **Scenario:** Typing `<div>` in a code editor → caption `Type "<div>"` → exported as `Type ""`;
  backticks / underscores typed or from AX labels turn into code/emphasis. (Distinct from the
  known Markdown-emphasis edge garble: this is loss of literal text.)
- **Fix:** in `CaptionFormatter.clean` backslash-escape all CommonMark punctuation
  (`\ ` `` ` `` `_ [ ] < > & #` …) for UI- and user-sourced text.

### L7. Trap on duplicate step ids in a hand-edited / externally merged session.json
- **Where:** `ReviewModel.swift:118, 135` `Dictionary(uniqueKeysWithValues:)`; `SessionManifestStore.load`
  dedupes by `file` only (`SessionManifest.swift:133-134`), not by `id`.
- **Scenario:** Two records with the same UUID but different files (copy-paste in JSON, sync conflict
  merge) → ⌘+ crashes; SwiftUI `ForEach` also misbehaves with duplicate ids.
- **Fix:** in `load`, also dedupe/regenerate duplicate ids; use `Dictionary(_:uniquingKeysWith:)`.

### L8. Review-close observer token is never removed
- **Where:** `AdvancedModeCoordinator.swift:126-133` — block-based `addObserver` token discarded.
- **Impact:** one leaked observer per Review opened (tiny). **Fix:** keep the token and remove it in the block.

### L9. Fixed-area start can stack two area pickers
- **Where:** `AppDelegate.swift:197-205` — while `AreaPicker.pick` is up, `isActive` is false, so a
  second hotkey press starts another snapshot + overlay. **Fix:** an `isPickingArea` flag.

### L10. Main-thread work per click in the tap callback
- **Where:** `SessionEventTap.swift:82` → `WindowPicker.ownerPIDOfWindow` → `CGWindowListCopyWindowInfo`
  synchronously inside the tap callback (few–tens of ms with many windows). Combined with M4 this is
  the main contributor to tap stalls. **Fix:** resolve "own click" with
  `NSApp.windows.contains { $0.isVisible && $0.frame(contains: p) }` (cheap, own process only) or do
  the window-list lookup in the pending-click Task.

### L11. Memory with rapid capture on big displays
- **Where:** `ClickCaptureManager.swift:319-337` — each in-flight step Task holds a full-resolution
  `NSImage` (≈60 MB per 5K frame) until its turn in the serialized write chain; with M4's slow
  main-thread writes, fast clicking queues several. **Fix:** encode to PNG `Data` in the Task
  (see M4) and drop the bitmap before awaiting the predecessor.

### L12. GIF export of hundreds of steps may hold every frame until finalize (UNVERIFIED)
- **Where:** `GIFGuideExporter.swift:48-65` — `CGImageDestinationAddImage` per frame, finalize at end;
  if ImageIO retains frames until `Finalize`, 300 × 1000×1200×4 ≈ 1.4 GB. The `autoreleasepool` doesn't
  help retained CGImages. **Fix:** measure; if confirmed, cap step count for GIF or warn.

### L13. Review rows do disk stats on every render
- **Where:** `ReviewModel.thumbnailURL` → `StepFiles.thumbnailURL` `fileExists` (`StepFiles.swift:56-59`)
  in every visible row body; every `@Published` change (selection, banner, refreshToken) re-renders
  all visible rows because each row observes the whole model. Also `refreshToken` bumps change the
  `.id` of *every* row's ThumbnailView (`ReviewRow.swift:136`), restarting all visible decodes when
  one step changes. **Fix:** cache the edited/raw URL in the model per step; scope the refresh token per step.

---

## Checked and found OK (no finding)
- Tap re-enable on `tapDisabledByTimeout/UserInput`; tap removed/invalidated on stop and deinit;
  start failure doesn't leave `isActive` true.
- Retina/multi-display maths: `StepGeometry`, `screen(containing:)`, `CaptureGeometry.cropped`
  (point-space clamp, pixel-space crop), `StepZoom` (points; 400×300 pt = 800×600 px on 2×).
- Write ordering (reserved slots, stop flush with 10 s cap, late steps dropped by folder check);
  `isStopping` guards double Stop.
- Typing fail-closed path (secure input blanking, start/end field identity, terminals → unknown).
- ReviewModel undo mirror for image swaps; reconciled snapshots; delete/restore all-or-nothing.
- Export staging: work folder always removed (`defer`), cross-volume copy staged then renamed,
  Markdown images backup/restore, PDF temp removal on late completion.
- `MainActor.assumeIsolated` call sites in ReviewWindowController/Coordinator are reached on main
  (capture replacement completion is main-thread per `CaptureManager.beginCapture`).


# Appendix: product

# Clipr: Product Review and Monetisation Strategy

Date: 2026-10-04. Repo state: `main` @ b31470e, v0.1.3, about 11.5k lines of Swift, 54 test files.

---

## 0. Where Clipr stands today (from the repo)

**What it is.** Clipr is a native Swift/SwiftUI menu-bar app (`LSUIElement`) for macOS 14+ with two products inside it:

1. **Screenshot tool.** Carbon global hotkeys, so the hotkey needs no Accessibility permission. Area, window and full-screen capture via ScreenCaptureKit. Captures auto-save to a folder and copy to the clipboard. The annotation editor has rectangle, ellipse, arrow, freehand, text, highlighter, blur/pixelate and numbered stamps, plus undo/redo, a recent-captures sidebar and copy styles.
2. **Advanced Mode (guide maker).** A listen-only CGEventTap records a click-through session. It captures:
   - a click marker (ring or dot);
   - an optional cursor trail;
   - an optional zoom close-up on each click;
   - auto captions from the Accessibility tree, including roles, titles and menu paths;
   - optional typing steps. Privacy fails closed: a secure field, secure input or an unknown field state throws away the whole burst, and terminal password prompts are handled.

   The Review window offers layouts, reorder, caption editing, S/M/L/Full sizes, replace image and multi-select. Export is wired in: PDF, self-contained HTML, Markdown folder, GIF, and rich-text clipboard for Confluence, Notion and Google Docs.

**Distribution today.**
- Ad-hoc signed only (`codesign --sign -` in `Scripts/build-app.sh`) and **not notarised**.
- Shipped as a zip on GitHub Releases plus a Homebrew cask.
- `UpdateChecker` polls the GitHub API and *tells* the user to run `brew upgrade`; nothing installs itself.
- There is no licence, trial, payments, analytics or onboarding code. `grep onboard|welcome` finds nothing.

**Gaps against the guide-maker market, from what the specs leave out.**
- No themes, branding or logos.
- No video/MP4.
- No publishing or uploading.
- Steps can't be merged, split or added from Review.
- No automatic redaction. The editor blur is manual only.
- No README or landing page.

**Positioning insight.** Every major guide maker (Scribe, Tango, Guidde, Dubble, iorad) is a **cloud SaaS with a browser extension, priced per seat**. Desktop-app capture is usually locked behind their *paid* tier. Clipr is the reverse: native, local-first and desktop-wide by default. That makes it the **"Scribe for people who can't or won't upload their screens"**: IT admins, regulated industries (health, finance, gov contractors), consultants documenting client systems, and indie devs writing READMEs. That wedge is the whole strategy.

---

## 1. Competitive landscape (2025-2026 pricing)

| Product | Model | Price | Notes |
|---|---|---|---|
| **Scribe** | Cloud SaaS, per seat | Free (web only, branded, no export or redaction). Pro Personal **$25/seat/mo annual ($35 monthly)**. Pro Team **$13/seat/mo annual, 5-seat minimum** | Desktop capture, PDF/HTML/MD export, redaction and branding are all paid-only. Cloud-only.<br>[guidde.com breakdown](https://www.guidde.com/knowledge-hub/scribe-pricing-2026-complete-cost-breakdown), [dubble.so teardown](https://dubble.so/compare/scribe-pricing), [trainn.co](https://trainn.co/blog/scribe-pricing/) |
| **Tango** | Cloud SaaS, per seat | Pro **$22/user/mo annual** (1-2 users), **$15/user/mo** (3+) | Desktop capture and branded PDF/MD/HTML export are Pro.<br>[supademo.com](https://supademo.com/blog/tango-pricing), [dubble.so](https://dubble.so/compare/tango-pricing) |
| **Guidde** | Cloud SaaS, per creator | Free (25 videos). Pro **$19/creator/mo annual**. Business **$39/mo**. Enterprise by quote | Video-first, AI voice. Desktop capture is Business-only.<br>[trainn.co](https://trainn.co/blog/guidde-pricing/), [pricingsaas.com](https://pricingsaas.com/companies/guidde) |
| **Dubble** | Cloud SaaS | Generous free tier (unlimited guides, redaction, pre-record blur). Pro **$18/mo annual for 3 creators** (+$6 per extra) | Most aggressive free tier, Chrome-first.<br>[Capterra](https://www.capterra.co.uk/software/1041658/dubble), [Chrome Web Store](https://chrome.google.com/webstore/detail/odinmjjdainghmojdffgpjmkefajhlbn) |
| **iorad** | Cloud SaaS | Free tutorials are **public**. Individual about **$200/mo**. Team $500/mo + $50 per creator. Enterprise $40k-137k/yr | Enterprise L&D.<br>[vendr.com](https://www.vendr.com/marketplace/iorad), [trupeer.ai](https://www.trupeer.ai/es/tools-comparison/iorad-vs-trupeer-pricing) |
| **Snagit** | Desktop, subscription-only since 2025 | **$39/yr** individual, $48/yr business | Has step capture but no click-recorder guide flow.<br>[screensnap.pro](https://www.screensnap.pro/blog/snagit-pricing), [Capterra](https://www.capterra.com/p/209649/Snagit/pricing/) |
| **CleanShot X** | Desktop, one-time | **$29 one-time + 1 yr updates**, then $19/yr. Cloud Pro **$8/user/mo** | Benchmark Mac screenshot app; Setapp too.<br>[toolradar.com](https://toolradar.com/tools/cleanshot-x/pricing) |
| **Shottr** | Desktop, one-time | **$8 Basic / $30 "Friends Club"**, 30-day trial | Free tier became a trial in v1.8 (late 2024).<br>[screensnap.pro review](https://www.screensnap.pro/blog/shottr-mac-review), [stork.ai](https://www.stork.ai/en/shottr) |
| **Xnapper** | Desktop, one-time | **$29.99** (1 device, 1 yr updates). Renewal at 40% off. Team $5/device/mo | Clean licensing pattern to copy.<br>[xnapper.com/pricing](https://xnapper.com/pricing) |
| **ScreenFlow** | Desktop | about **$169** | Video editor, adjacent only.<br>[toolradar.com](https://toolradar.com/tools/screenflow/pricing) |

**What users push back on in the guide-maker category** (from the pricing teardowns above and privacy write-ups):
- **Per-seat cost scales painfully.** Scribe Pro Personal at $25/mo is $300/yr per author. iorad's free tier is public-only.
- **Paywalls on the basics.** Desktop capture, export and redaction are paid on Scribe and Tango.
- **Cloud-only data handling.** Screens of internal systems go to a vendor server ([screenpi.pe on Scribe](https://screenpi.pe/compare/scribe)). Scribe answers this with SOC 2 and "AI Smart Blur" ([scribe.com](https://scribe.com/tools/image-blur-redaction)), which shows that redaction is table stakes. Screenshot-data leaks such as the WorkComposer case (21M screenshots, [TechRadar](https://www.techradar.com/pro/security/time-tracker-tool-spilled-details-on-remote-workers-millions-of-screenshots-leaked)) make "never leaves your Mac" a credible selling point.
- **Browser-extension tools can't record native apps** on the free tier. Clipr records *any* macOS app.

---

## 2. Product improvements: top 10, prioritised

Scoring: Impact (I) and Effort (E) on a 1-5 scale. Ordered by I/E, then by how much each item enables the monetisation plan.

| # | Item | I | E | Why |
|---|---|---|---|---|
| 1 | **Notarisation, Developer ID signing and Sparkle auto-update** | 5 | 2 | Prerequisite for selling. An ad-hoc-signed app can't keep its TCC grants across updates: each rebuild has a new code identity, so users must re-grant Screen Recording and Accessibility. It also trips Gatekeeper and looks untrustworthy to IT buyers. |
| 2 | **First-run onboarding and permissions UX** | 5 | 2 | Two TCC grants, plus a monthly Screen Recording re-prompt on Sequoia and later. This is the #1 drop-off point. |
| 3 | **Auto-redaction (local)** | 5 | 3 | The privacy wedge needs a feature you can demo. Scribe and Dubble already market this. |
| 4 | **Branding and templates on export** | 4 | 2 | Scribe and Tango put this in paid tiers. It's the natural Pro gate and cheap because one HTML template drives HTML, PDF and clipboard. |
| 5 | **On-device AI caption rewrite and guide title/intro** | 4 | 2-3 | Closes the "AI" gap with zero inference cost and no cloud. |
| 6 | **Review editing completeness**: merge/split/insert steps, section headings, tip/warning callouts, undo | 4 | 3 | Today's Review can't add or merge steps. Real guides need sections and notes. |
| 7 | **Publish integrations**: Confluence, Notion, GitHub/GitLab wiki or repo PR | 4 | 3-4 | Removes the "export then upload" step that cloud tools avoid. Keeps local-first because the user's own account is the destination. |
| 8 | **Optional share link** (static guide hosting) | 3 | 4 | Matches the cloud tools' instant link while staying opt-in. Monetisable as an add-on. |
| 9 | **Video to guide**: import a screen recording, or record video alongside a session, and export MP4 | 3 | 4 | Guidde and Dubble are video-first. MP4 export is cheaper than full video-to-guide. |
| 10 | **Team library (folder-based)**: shared guide templates and branding packs, plus a guide index in a shared folder or Git repo | 3 | 3 | Team value without running a server. Justifies team pricing. |

### Detail per item

**1. Ship properly (signing, notarisation, updates).**
- Join the Apple Developer Program ($99/yr) and sign with Developer ID plus the hardened runtime.
- `notarytool submit --wait`, then `stapler staple`.
- Replace `UpdateChecker` with **Sparkle 2** (EdDSA-signed appcast, delta updates). Keep the Homebrew cask, but set `auto_updates true`.
- A stable designated requirement keeps the Screen Recording and Accessibility grants across updates. Today each ad-hoc build is a new identity to TCC. This is a real support-cost and churn fix, not just polish.
- Add crash reporting that is opt-in or local. Sentry is opt-in; MetricKit-style local logs plus a "Send diagnostics" button fit the privacy story.

**2. Onboarding and permissions.**
- A 3-screen welcome:
  1. Choose the hotkey.
  2. Grant Screen Recording, with a live checkmark that polls `CGPreflightScreenCaptureAccess`.
  3. An optional "Try Guide Mode" that asks for Accessibility **only** at that point, with a short animation of System Settings.
- Detect the monthly Sequoia re-prompt and the "app was updated, re-enable" state, and show a friendly in-app banner instead of a silent failure.
- Add a "Permission doctor" in Preferences that shows the state of each grant and has fix buttons.
- Add a sample guide recorded against a bundled demo window, so the first session succeeds.
- Teach users to stop a session: a menu-bar timer, Esc, or the step-hotkey control panel.

**3. Auto-redaction, local and on-device.**
- Use Vision `VNRecognizeTextRequest` on each step image to detect emails, phone numbers, IBANs, card numbers (Luhn check), API-key and token patterns, IPs, and a user-supplied keyword list (customer names, internal domains).
- Insert `blur` annotations into the sidecar, so they are editable and the raw image stays clean. This fits the existing "markers are annotations" design.
- AX can also mark secure or value-bearing fields for blur at capture time, since `ClickDescriber` already knows the field role.
- Add a "Review redactions" filter in Review. Before export, warn about "N steps contain detected PII not yet blurred".
- Market it as: *"Redaction runs on your Mac. Nothing is uploaded, ever."*

**4. Branding and templates.**
- Logo, accent colour, font, header/footer, cover page, and a "step N of M" style.
- Add a few templates: Clean, Corporate, Dark, and Compact (for READMEs).
- Store them as JSON plus an asset bundle so teams can share a `.cliprtheme` file (feeds item 10).
- The HTML/PDF/clipboard share one template, so the effort is low.
- Add a free-tier watermark: "Made with Clipr" in the footer. This is also the growth loop.

**5. On-device AI captions (FoundationModels, macOS 26+).**
- Apple's FoundationModels framework gives free, offline, private LLM inference ([Cult of Mac](https://www.cultofmac.com/news/apple-foundation-models-framework), [createwithswift](https://createwithswift.com/exploring-the-foundation-models-framework/)).
- Uses:
  - rewrite AX-derived captions into natural imperative sentences ("Click **Save** in the toolbar");
  - generate a guide title, intro and prerequisites;
  - suggest section breaks;
  - translate captions.
- Use `@Generable` structured output per step. Gate it with `#available(macOS 26, *)`; on macOS 14-15, fall back to the existing `CaptionFormatter`.
- Optionally let the user bring their own key for a cloud LLM (OpenAI, Anthropic). It must be off by default and clearly labelled, to protect the privacy reputation.

**6. Review completeness.**
- Merge or split steps, insert a blank or new capture, and add heading and callout blocks (Note, Warning, Tip).
- Add guide-level metadata (title, intro, author, version) and undo/redo across the manifest.
- Add duplicate-step detection, for example consecutive near-identical images found by perceptual hash.

**7. Publishing.**
- **Confluence**: the REST API with an API token in the Keychain. Upload attachments plus a storage-format page.
- **Notion**: an internal integration token, blocks API and file upload.
- **GitHub**: commit the `guide.md` plus `images/` folder to a repo or branch through the REST API or the local `git`. This is very strong for developer users.
- **Google Docs**: rich clipboard is probably enough.
- Each publisher is a `GuidePublisher` protocol that reuses `GuideDocument`.

**8. Share link (optional cloud).**
- Upload the self-contained HTML to Cloudflare R2 or Pages behind an unguessable URL.
- Support expiry, a password and delete-from-app. Uploads are opt-in per guide.
- This is the only server component, so keep it small: a Cloudflare Worker plus R2 is cents per GB. Sell it as an add-on (see §3).

**9. Video.**
- Phase 1: MP4 export of the step slideshow with captions and Ken Burns zooms on the click point, built with AVAssetWriter. This reuses the GIF pipeline.
- Phase 2: record ScreenCaptureKit video during a session and let the user pick frames.
- Phase 3: import an existing recording and auto-detect steps by frame differences.

**10. Team library.**
- Point Clipr at a shared folder (iCloud Drive, Dropbox, SMB) or a Git repo holding templates, branding, a redaction keyword list and published guides.
- MDM-deployable defaults through a configuration profile with a managed `UserDefaults` domain. These include forcing redaction on, disabling the share link and preloading the licence key. IT buyers value this a lot, and it is cheap to build.

**Smaller polish items, worth folding into the above.**
- A README and landing page with a 30-second GIF made in Clipr itself.
- A Sparkle "What's new" panel.
- Session list and search across past guides, plus a guide library window.
- Localisation of captions: AX titles already come in the user's language.
- Accessibility of exported HTML: alt text from captions.
- Capture-scope presets ("this app only", which ignores clicks in other apps).
- Pause and resume in a session.
- Keyboard-only step capture is already supported through the step hotkey.

---

## 3. Monetisation

### Constraints that shape the choice

- **The Mac App Store is effectively out for Advanced Mode.** The App Sandbox blocks cross-app Accessibility calls, and no entitlement unlocks them. Clipr's auto-captions rely on `AXUIElementCopyElementAtPosition` against other apps ([Apple forums 707680](https://developer.apple.com/forums/thread/707680), [forums 756130](https://developer.apple.com/forums/thread/756130)). A listen-only CGEventTap is possible under Input Monitoring, but the AX captions, which are the core differentiator, are not.
  - The MAS would take 15% under the Small Business Program ([Apple](https://developer.apple.com/app-store/small-business-program/)) and would offer only a crippled product.
  - Option: a later sandboxed "Clipr Lite" (screenshots only) on the MAS as a discovery funnel. It is not a priority.
- **Direct sales through a Merchant of Record.** Paddle and Lemon Squeezy both charge **5% + $0.50**. Lemon Squeezy adds surcharges for international cards and PayPal (about +1.5% each); Paddle doesn't ([dodopayments comparison](https://dodopayments.com/blogs/paddle-vs-lemon-squeezy/), [rework.com](https://resources.rework.com/tools/billing-revenue/paddle-vs-lemon-squeezy)).
  - On a $39 sale, the take is about $2.45 (6%) versus $5.85 (15%) on the MAS.
  - Both handle global VAT and sales tax, which matters for a solo developer.
- **Setapp's Mac catalogue is still running.** Setapp *Mobile*, the EU iOS store, closed in Feb 2026 ([AppleInsider](https://appleinsider.com/articles/26/01/15/setapp-mobile-eu-app-store-cleanmymac-business-both-close-down-for-good)).
  - Setapp pays **70% of the usage-weighted revenue share**, up to 90% for users you refer ([docs.setapp.com](https://docs.setapp.com/docs/distributing-revenue)).
  - It allows non-sandboxed apps, unlike the MAS, and CleanShot X is there.
  - Good for reach and steady small revenue. It can cannibalise direct sales to prosumers, but not to teams or IT.

### Model A: Free core + paid "Clipr Pro" one-time licence (RECOMMENDED)

**Free, forever, with no time limit:**
- the full screenshot tool and annotation editor (including manual blur);
- Advanced Mode recording and Review;
- exports in PDF, HTML, Markdown and clipboard, with a small "Made with Clipr" footer;
- guides up to about 15 steps.

The free tier must beat Scribe's free tier, which is web-only, branded and has no export. That is the acquisition engine: Clipr wins on "desktop capture + export, free" alone.

**Pro: one-time licence with 12 months of updates.** This is the Xnapper and CleanShot pattern that Mac users accept.
- **$39** for a personal licence on 2 Macs. Launch price: $29 for the first 2 weeks.
- Updates after year one are optional: **$19/yr renewal**, matching CleanShot's $19 ([toolradar](https://toolradar.com/tools/cleanshot-x/pricing)). Users keep the last version forever.
- Pro includes:
  - unlimited steps and no footer;
  - **auto-redaction**;
  - **branding and templates**;
  - **on-device AI captions**;
  - GIF and MP4;
  - typing steps, zoom close-ups and cursor trail. Or keep these free to make the free product delightful, and gate only output polish. The recommendation is to keep capture free and gate output.
  - publishing integrations (Confluence, Notion, GitHub);
  - the team library.

**Team / Business:**
- 5-pack at **$149** (about $30 per seat).
- 10+ seats at **$25 per seat** one-time, plus a 20%/yr maintenance option.
- Volume licence key and MDM config profile. Invoice and PO through Paddle.
- Benchmark: Scribe Pro Team is $13 × 12 × 5 = **$780/yr minimum**; Tango (3+ seats) is $15 × 12 = **$180 per user per year**. Clipr Team at $149 one-time for 5 seats is an easy budget line for an IT lead.

**Add-on: Clipr Share (optional cloud).**
- **$4/mo or $36/yr** per user for hosted share links: password, expiry, custom subdomain.
- This is the only recurring revenue. It's justified by real hosting cost and stays opt-in, so "local-first" remains true.

**Why A.**
- Mac indie buyers prefer one-time licences, and the main screenshot competitors (CleanShot, Shottr, Xnapper) all use them.
- The pitch "pay once vs $300/yr per seat for Scribe" is a powerful headline.
- Licence-key infrastructure is simple, and there is no backend unless Share ships.

### Model B: Freemium + subscription (Pro $5/mo or $48/yr; Team $8/seat/mo)

- **Pros:** predictable revenue that funds ongoing AI and integration work. It is still far cheaper than Scribe or Tango ($25 / $22 per month).
- **Cons:** Mac prosumers resist subscriptions for utilities. Snagit's move to subscription-only in 2025 drew complaints ([screensnap.pro](https://www.screensnap.pro/blog/snagit-pricing)). It also weakens the anti-SaaS positioning and needs entitlement checks on a schedule.
- **Use it only** if Share and publishing become the main value.

### Model C: Setapp + direct

- List on Setapp for reach and passive income, and keep direct sales (Model A) for teams and people who want to own the licence.
- Setapp needs its framework integrated (`Setapp.framework`) with a separate build flavour, and it requires that its version not be crippled.
- **Recommend adding C on top of A** about 3-6 months after launch, once the direct funnel and pricing are proven. It isn't a launch dependency.

### Recommendation

**Model A at launch (free core + Clipr Pro $39 one-time with 1 year of updates, Team 5-pack $149), with Clipr Share later as the only subscription, and Setapp added as a secondary channel within 6 months.** Distribute directly (notarised DMG, Sparkle, Homebrew cask), sell through **Paddle** for its flat international fees, invoice and PO support, and built-in licence and B2B checkout. Lemon Squeezy is fine if its licence-key API is preferred, but watch the international surcharges.

### Free vs paid matrix

| Feature | Free | Pro | Team |
|---|---|---|---|
| Hotkey screenshots and annotation editor | ✓ | ✓ | ✓ |
| Guide recording, auto captions (AX), click marker | ✓ | ✓ | ✓ |
| Zoom, cursor trail, typing steps (privacy fail-closed) | ✓ | ✓ | ✓ |
| Review: reorder, captions, sizes, replace | ✓ | ✓ | ✓ |
| Export PDF/HTML/MD/clipboard | ✓ (≤15 steps, footer) | Unlimited, no footer | ✓ |
| GIF / MP4 export | GIF ≤ 10 frames | ✓ | ✓ |
| Auto-redaction (OCR + patterns + keywords) | Preview: detect and warn only | ✓ | ✓ + enforced via MDM |
| Branding and templates | Clean only | ✓ | Shared theme packs |
| On-device AI rewrite, titles, translate | n/a | ✓ (macOS 26+) | ✓ |
| Publish to Confluence/Notion/GitHub | n/a | ✓ | ✓ |
| Team library, MDM config, volume key | n/a | n/a | ✓ |
| Share links | n/a | Add-on | Add-on |

"Detect and warn" in Free is deliberate. It shows users the risk, and Pro fixes it in one click. This is a strong conversion moment.

---

## 4. Licensing and code changes

**Infrastructure.**
- **Apple Developer Program** ($99/yr), with a Developer ID Application certificate and the hardened runtime. Entitlements are needed only if JIT etc. require them. Screen Recording and Accessibility are TCC grants, not entitlements.
- Release pipeline in `Scripts/release.sh`: `codesign --options runtime --timestamp`, then a DMG via `create-dmg`, then `xcrun notarytool submit --wait`, then `xcrun stapler staple`, then `generate_appcast` for Sparkle, then upload. Add `Info.plist` keys `SUFeedURL` and `SUPublicEDKey`, and `NSHumanReadableCopyright`.
- **Sparkle 2** through SPM. It replaces `UpdateChecker`, and an "Install update" button replaces the brew instructions. The Homebrew cask stays, with `auto_updates true`.
- **Paddle Billing** for checkout and licence keys, either through Paddle's licence product or a tiny licence service of your own. The simplest robust option is offline-verifiable signed licences:
  - On purchase, a webhook makes a small serverless function (Cloudflare Worker) sign a payload `{email, tier, seats, updatesUntil, licenseId}` with an **Ed25519 private key**.
  - The key is emailed or delivered through a `clipr://activate?key=…` URL scheme.
  - The app verifies it offline with the embedded public key using CryptoKit's `Curve25519.Signing`. No phone-home is needed, which matches the privacy brand.
  - An optional periodic revocation check against a static list of revoked IDs on R2 can be turned off.
- `updatesUntil` enforces "1 year of updates": the app (and Sparkle, via an appcast filter or a version check) refuses to *install* builds whose release date is after `updatesUntil`, but keeps running forever.

**Code changes in Clipr.**
1. A `Licensing/` module:
   - `LicenseKey` (decode and verify the Ed25519 signature);
   - `LicenseStore` (Keychain, not UserDefaults);
   - `Entitlements` (computed `isPro`, `isTeam`, `updatesUntil`, `trialDaysLeft`);
   - a `@Observable LicenseManager` injected the way `SettingsStore` is.
2. A **feature-gate API**: `Feature` enum (`.unlimitedSteps`, `.redaction`, `.branding`, `.aiCaptions`, `.publish`, `.mp4`, `.teamLibrary`) and `Entitlements.allows(_:)`. Gate checks go:
   - at the **export** boundary (`ExportSheetModel` / `GuideExporter`): step cap, footer injection in the HTML template and Markdown writer, GIF frame cap;
   - in the redaction apply action;
   - on the template picker;
   - on publish targets.

   Never gate capture paths, so a lapsed licence can't break recording.
3. **Trial**: a 14-day Pro trial that starts at the first export, not first launch. Store the start date in the Keychain plus a file under Application Support. Accept that it can be reset; don't fight pirates.
4. **UI**:
   - a Preferences "License" tab (status, activate, buy, manage seats, deactivate);
   - upgrade prompts at the gate moments: export with more than 15 steps, a redaction warning, picking a template;
   - a menu-bar "Upgrade to Pro…" item.
5. **MDM**: read a managed preferences domain (`com.shancox.clipr`) for the licence key and policy flags, for example `forceRedaction` and `disableShareLinks`.
6. **Setapp build flavour** (later): a compile flag `SETAPP` that swaps `LicenseManager` for Setapp's framework and strips Sparkle (Setapp handles updates).
7. Bundle-ID decision: keep `com.shancox.clipr` stable from the first notarised release onwards, because TCC grants key on it and the designated requirement.

---

## 5. Launch plan

**T-6 to T-2 weeks.**
- Notarised 1.0 with Sparkle.
- Landing page: hero GIF made in Clipr; "Scribe-style guides, 100% on your Mac"; a comparison table against Scribe and Tango (price per year, cloud vs local, desktop capture free).
- Docs page about privacy: what the app reads (AX titles, never field values) and the fail-closed typing design. This is a real differentiator, so explain it.
- Collect a waitlist. Seed 20-30 beta users from IT, help desk and customer success.

**Launch week.**
- **Product Hunt**: Tuesday-Thursday, 12:01 PT. Lead with the redaction and on-device AI demo.
- **r/macapps**: the community likes one-time pricing and gets a launch discount code. Also r/sysadmin, r/msp and r/ITManagers framed as "documenting procedures without uploading screens". r/technicalwriting, r/CustomerSuccess, r/selfhosted (local-first angle).
- **Hacker News "Show HN"** with an engineering-story angle, for example "How we caption clicks from the macOS Accessibility tree without ever reading field values".
- Mac newsletters and sites: MacStories, 9to5Mac indie, Mac Power Users, iOS Dev Weekly (for the GitHub publish angle).
- A launch price of $29 for 7-14 days, then $39.

**Ongoing.**
- SEO comparison pages: "Scribe alternative for Mac", "Tango alternative offline", "free step recorder Mac".
- The "Made with Clipr" footer on free exports.
- Template gallery.
- Outreach to MSPs and IT consultancies offering Team 5-packs.
- Setapp application at about month 3-6.
- Optional: a bundle deal (CleanShot users are a natural audience). Avoid AppSumo-style lifetime deals: they draw a high support load for low revenue.

**Success metrics.**
- Activation: the percentage of installs that complete one guide export.
- Trial-to-paid: 3-6% of active free users is a typical indie freemium benchmark; treat it as a target, not data.
- Refund rate.
- Team-pack share of revenue.

---

## 6. Risks and mitigations

| Risk | Detail | Mitigation |
|---|---|---|
| **Apple permission friction** | Screen Recording plus Accessibility (plus Input Monitoring semantics for the tap). Sequoia+ re-prompts for screen-capture permission **monthly** ([9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)). Ad-hoc builds lose grants on update. | Notarise with a stable identity; onboarding and permission doctor; ask for Accessibility only when Advanced Mode is first used (already the design); explain each prompt in-app. |
| **Privacy reputation** | A tool that taps every click and keystroke looks like spyware to IT security, and one leaked password in a guide could be fatal. | Keep fail-closed typing (already strong); auto-redaction; no telemetry by default; a published privacy design doc; open-source the capture and redaction core or have it audited; MDM policy lock; avoid cloud features by default. |
| **Competitors' free tiers** | Dubble's free tier is unlimited, with redaction ([Capterra](https://www.capterra.co.uk/software/1041658/dubble)); Scribe and Guidde have free tiers; Scribe could ship a native Mac recorder. | Compete on *native desktop + local + one-time*. Keep Clipr's free tier more generous on desktop capture and export than Scribe's. Speed of iteration as a solo developer. |
| **Mac App Store absence** | Less discovery, and some corporate users can only install MAS apps. | Homebrew, Setapp, MDM-friendly signed pkg; later a sandboxed screenshot-only MAS Lite. |
| **macOS-only TAM** | Teams with Windows users need a cross-platform tool. | Position for Mac-heavy orgs (startups, design, dev, creative), and keep guide output format-neutral (HTML/MD). |
| **AX caption quality varies** | Electron and web apps expose poor AX trees, which gives generic captions. | On-device AI rewrite; OCR near the click point as a fallback label; quick caption editing in Review (exists). |
| **Solo-developer support load** | Licences, refunds, permissions issues. | Paddle handles billing support and tax; self-serve licence recovery page; permission doctor; FAQ. |
| **Piracy** | Offline licences are crackable. | Accept it. The target buyers (IT, teams) pay for invoices and MDM. |
| **AI platform dependency** | FoundationModels needs macOS 26 and Apple Intelligence-capable hardware. | Keep the deterministic `CaptionFormatter` as the baseline; AI is an enhancement, not a requirement. |

---

## 7. 90-day roadmap summary

1. **Weeks 1-3:** Developer ID, notarisation, Sparkle, onboarding and permission doctor, landing page, Paddle and the licence module with the 14-day trial and export gating.
2. **Weeks 4-7:** auto-redaction (Vision OCR plus patterns plus keywords), branding and templates, guide title/intro, Review callouts and headings. **Launch 1.0** (Product Hunt, r/macapps, Show HN).
3. **Weeks 8-12:** on-device AI captions (macOS 26), GitHub/Confluence/Notion publishing, MP4 export, Team 5-pack with MDM keys. Apply to Setapp. Evaluate demand for the Clipr Share add-on.
