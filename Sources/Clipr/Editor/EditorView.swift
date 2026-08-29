import SwiftUI

/// The editor window's root view. This type's implementation is split across several files by
/// responsibility, all extensions of this one struct (so member visibility below is `internal`,
/// not `private`, purely so those other files can see it — there is still exactly one component
/// here):
/// - `EditorView.swift` (this file): properties, `body`, small shared helpers.
/// - `EditorView+KeyboardShortcuts.swift`: number-key tool shortcuts.
/// - `EditorView+Sidebar.swift`: the Recent-captures sidebar.
/// - `EditorView+Header.swift`: filename + Copy/Share header bar.
/// - `EditorView+Toolbar.swift`: the tool/color/stroke toolbar and its button styles.
/// - `EditorView+ColorStrokeBindings.swift`: color/stroke bindings that retarget to a selection.
/// - `EditorView+TextStyleControls.swift`: font/alignment controls for text annotations.
/// - `EditorView+Canvas.swift`: the zoomable/scrollable canvas area.
/// - `EditorView+CanvasResizeHandles.swift`: the four corner canvas-resize handles.
/// - `EditorView+Persistence.swift`: auto-save scheduling, undo/redo, the annotations binding.
struct EditorView: View {
    let image: NSImage
    let currentURL: URL
    let recentCaptures: [URL]

    @State var annotations: [AnnotationObject] = []
    @State var selectedTool: AnnotationTool = .select
    @State var currentColor = EditorView.swatchColors[5] // red
    @State var currentStrokeWidth: CGFloat = 4
    @State var currentTextStyle = TextStyle.default
    @State var selectedAnnotationID: UUID?
    @State var editingTextID: UUID?
    @State var undoStack: [[AnnotationObject]] = []
    @State var redoStack: [[AnnotationObject]] = []
    @State var zoomPercent: Double = 100
    @State var viewportSize: CGSize = .zero
    /// Once the user manually changes zoom (the +/- buttons), auto-fit-on-resize stops —
    /// clicking "Fit" explicitly re-requests it by clearing this back to `false`. Deliberately
    /// NOT a one-shot "did we auto-fit yet" flag: a `GeometryReader` can report several different
    /// transient sizes while the window's initial layout settles (e.g. right after opening
    /// maximized), and locking in after the first non-zero read was exactly the bug where the
    /// editor opened auto-fit to a stale, too-small size. Re-running `zoomToFit()` on every
    /// subsequent size change until the user actually takes control converges on the correct
    /// final fit regardless of how many intermediate layout passes happen first.
    @State var userSetZoom = false
    @State var nextStampNumber = 1
    /// Which stamp the toolbar's stamp slot currently offers, or `nil` for the auto-incrementing
    /// numbered one. Set from the slot's pull-down — see `EditorView+Toolbar.stampToolButton`.
    @State var selectedStampKind: StampKind?
    @State var showingStampAlternatives = false
    /// Style used for redactions placed from now on. Pixelate matches the tool's previous
    /// behaviour, so it stays the default.
    @State var redactionStyle: RedactionStyle = .pixelate
    @State var showingRedactionStyles = false
    @State var showSavedConfirmation = false
    @State var deletedRecentURLs: Set<URL> = []
    @State var pendingCanvasResize: CGRect?
    /// Header filename rename (see `EditorView+Header.swift`). These reset whenever the content
    /// view is rebuilt — after a rename it is, so the field correctly reverts to plain text
    /// showing the new name.
    @State var isRenaming = false
    @State var draftName = ""
    @FocusState var renameFieldFocused: Bool
    /// Debounces auto-save so every single keystroke/drag doesn't hit disk — only the trailing
    /// edit in a burst does. Cancelling and replacing this on every `annotations` change is what
    /// gives the debounce its "wait for a pause" behavior.
    @State var autoSaveTask: Task<Void, Never>?

    /// Switching to a different Recent capture used to discard whatever was mid-edit, since the
    /// old flow only ever wrote to disk on an explicit Save click. Auto-save (`onAutoSave`, fired
    /// on every settled edit — see `scheduleAutoSave`) means there's no manual Save button
    /// anymore. Passing the current `annotations` along lets `EditorWindowController` flush the
    /// OUTGOING capture's latest edit synchronously before switching, so a very recent edit that
    /// hadn't reached its debounce yet is never lost.
    let onOpenCapture: (URL, [AnnotationObject]) -> Void
    /// The `URL` passed alongside `annotations` is the one this specific debounced save was
    /// scheduled for — see `scheduleAutoSave` and `EditorWindowController.autoSave(for:)` for why
    /// that matters (a switched-away-from capture's late-firing debounce must not write over
    /// whatever the window has since moved on to).
    let onAutoSave: (URL, [AnnotationObject]) -> Void
    /// Fired synchronously on every annotation change, unlike `onAutoSave`'s 800ms debounce, so
    /// `EditorWindowController` always holds the current state and can flush it when the window
    /// closes or the app quits — at which point the pending debounce will never fire.
    let onAnnotationsChanged: ([AnnotationObject]) -> Void
    /// Reports the undo/redo stacks alongside every annotation change, so the controller can hand
    /// them back when it rebuilds the content view for a rename — see `EditorHistory`.
    let onHistoryChanged: (EditorHistory) -> Void
    let onCopy: ([AnnotationObject]) -> Void
    /// Export a copy elsewhere, in a format the user picks — distinct from auto-save, which keeps
    /// the capture itself up to date in the save folder.
    let onSaveAs: ([AnnotationObject]) -> Void
    let onRevealInFinder: (URL) -> Void
    let onShare: ([AnnotationObject]) -> Void
    /// Crop rect in renderer space (the same y-up-from-bottom space `AnnotationObject.frame`
    /// uses), plus the annotations at the moment the crop was requested — `EditorWindowController`
    /// owns the base `NSImage` and does the actual pixel crop and annotation remap, since this
    /// view only has a `let image`, not a mutable one.
    let onCropApplied: (CGRect, [AnnotationObject]) -> Void
    /// Canvas-resize rect in top-left/y-down space (matching the corner handles themselves) —
    /// can extend beyond the image's own bounds (expand) or be smaller (shrink/crop) — plus the
    /// current annotations, for the same remap-not-discard treatment as crop.
    let onCanvasResize: (CGRect, [AnnotationObject]) -> Void
    let onDeleteCapture: (URL) -> Void
    /// Rename requested from the header: the capture being renamed, the new base name (no
    /// extension, unsanitised as typed), and the current annotations so the controller can flush
    /// them against the OLD name before any file moves — same reasoning as `onOpenCapture`.
    let onRename: (URL, String, [AnnotationObject]) -> Void

    static let swatchColors: [RGBAColor] = [
        RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
        RGBAColor(red: 0x91 / 255.0, green: 0x9E / 255.0, blue: 0xAB / 255.0, alpha: 1),
        RGBAColor(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0, alpha: 1),
        RGBAColor(red: 0x8E / 255.0, green: 0x33 / 255.0, blue: 0xFF / 255.0, alpha: 1),
        RGBAColor(red: 1.0, green: 0xB7 / 255.0, blue: 0x4D / 255.0, alpha: 1),
        RGBAColor(red: 0xF4 / 255.0, green: 0x43 / 255.0, blue: 0x36 / 255.0, alpha: 1),
    ]

    /// True while the user is typing into a text field — either a text annotation or the header's
    /// rename field. Every bare-key shortcut (the 1-0 tool keys, Delete, ⌘Z) must be disabled
    /// while this holds, or it fires instead of reaching the field: Backspace would delete the
    /// selected annotation rather than a character, and a digit would switch tools mid-word.
    var isTextEntryActive: Bool { editingTextID != nil || isRenaming }

    var numberTool: AnnotationTool { .stamp(stampKind(for: nextStampNumber)) }
    var visibleRecents: [URL] { recentCaptures.filter { !deletedRecentURLs.contains($0) } }

    /// The selected annotation's `.text` payload, if the current selection is a text
    /// annotation — used to decide whether the toolbar's text-style controls should edit
    /// "the next new text" (`currentTextStyle`) or the already-placed one that's selected.
    var selectedTextAnnotation: (id: UUID, style: TextStyle)? {
        guard let id = selectedAnnotationID, let annotation = annotations.first(where: { $0.id == id }),
              case .text(_, let style) = annotation.kind else { return nil }
        return (id, style)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                headerBar
                toolbar
                canvasArea
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(EditorColors.s0)
        .background(toolShortcuts)
        .background(annotationEditingShortcuts)
    }
}
