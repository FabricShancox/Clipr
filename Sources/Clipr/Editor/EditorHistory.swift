import Foundation

/// The editor's undo/redo stacks, lifted out so `EditorWindowController` can carry them across a
/// content-view rebuild.
///
/// Undo lives in `EditorView`'s `@State`, which is discarded whenever the hosting view is
/// replaced. That is correct for most rebuilds — opening a different capture should not let you
/// undo into the previous one's history — but a rename changes nothing about the image or its
/// annotations, so losing the history there is pure loss.
///
/// Crop and canvas-resize deliberately keep clearing it. Restoring pre-crop annotations onto a
/// cropped image would place every one of them wrongly, since the operation remaps their
/// coordinates; undo would have to restore the old image too, which is a larger change than this.
struct EditorHistory: Equatable {
    var undo: [[AnnotationObject]] = []
    var redo: [[AnnotationObject]] = []
}
