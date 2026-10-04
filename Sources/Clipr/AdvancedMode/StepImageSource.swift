import Cocoa

/// Captures the image for an Advanced Mode step; faked in tests.
protocol StepImageSource: AnyObject {
    var ownWindowIDs: Set<CGWindowID> { get set }
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame?
}
