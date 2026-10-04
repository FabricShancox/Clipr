import Foundation
import CoreGraphics

/// One step of an Advanced Mode session as recorded in `session.json`.
struct StepRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case click, typing, manual }

    let id: UUID
    /// Filename relative to the session folder, e.g. "Step_03.png".
    var file: String
    var kind: Kind
    var caption: String?
    /// Image point space, top-left origin. `nil` when the click fell outside the captured image
    /// or the step had no click.
    var clickPoint: CGPoint?
    var zoomFile: String?
    var appName: String?
    var capturedAt: Date
    /// `nil` means Full. Optional, and never written when nil, so manifests from before sizing
    /// existed decode unchanged and unsized sessions stay exactly what older Clipr wrote. The
    /// manifest version stays 1: older builds ignore this key rather than misread it. The cost,
    /// accepted because the field is cosmetic: an older build that edits a sized session drops
    /// `imageSize` when it saves.
    var imageSize: ImageSize? = nil

    /// The same step under a fresh id.
    func withNewID() -> StepRecord {
        StepRecord(id: UUID(), file: file, kind: kind, caption: caption, clickPoint: clickPoint, zoomFile: zoomFile,
                   appName: appName, capturedAt: capturedAt, imageSize: imageSize)
    }
}
