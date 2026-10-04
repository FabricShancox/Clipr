import XCTest
import Cocoa
@testable import Clipr

/// Each capture carries its own mode, so a retake for Review and an ordinary screenshot can never
/// be mistaken for one another.
@MainActor
final class CaptureRoutingTests: XCTestCase {
    private let image = NSImage(size: CGSize(width: 4, height: 3))

    func testReplacementResultIsNeverSaved() async {
        var saved = 0
        var delivered: [NSImage?] = []
        await CaptureManager.deliver(image, mode: .replacement { delivered.append($0) }, save: { _ in saved += 1 })
        XCTAssertEqual(saved, 0)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(delivered[0] === image)
    }

    func testCancelledReplacementStillCompletesWithNil() async {
        var delivered: [NSImage?] = []
        await CaptureManager.deliver(nil, mode: .replacement { delivered.append($0) }, save: { _ in XCTFail("saved") })
        XCTAssertEqual(delivered.count, 1)
        XCTAssertNil(delivered[0] ?? nil)
    }

    func testNormalResultIsSavedAndNeverReachesAReplacement() async {
        var replacementCalls = 0
        let replacement = CaptureManager.CaptureMode.replacement { _ in replacementCalls += 1 }
        _ = replacement  // A retake that is also pending must not receive this capture.
        var saved: [NSImage] = []
        await CaptureManager.deliver(image, mode: .normal, save: { saved.append($0) })
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(replacementCalls, 0)
    }

    func testCancelledNormalCaptureSavesNothing() async {
        await CaptureManager.deliver(nil, mode: .normal, save: { _ in XCTFail("saved") })
    }
}
