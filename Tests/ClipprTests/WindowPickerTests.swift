import XCTest
@testable import Clipr

final class WindowPickerTests: XCTestCase {
    let windows = [
        WindowInfo(windowID: 1, ownerPID: 100, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0),
        WindowInfo(windowID: 2, ownerPID: 200, bounds: CGRect(x: 100, y: 100, width: 300, height: 300), layer: 0),
        WindowInfo(windowID: 3, ownerPID: 100, bounds: CGRect(x: 500, y: 500, width: 400, height: 400), layer: 0),
    ]

    func testWindowAtPointReturnsTopmostContaining() {
        let hit = WindowPicker.window(at: CGPoint(x: 150, y: 150), in: windows)
        XCTAssertEqual(hit?.windowID, 1, "first matching window in front-to-back order should win")
    }

    func testWindowAtPointOutsideAllReturnsNil() {
        XCTAssertNil(WindowPicker.window(at: CGPoint(x: 9999, y: 9999), in: windows))
    }

    func testFrontmostWindowOwnedByPID() {
        let hit = WindowPicker.frontmostWindow(ownedBy: 100, in: windows)
        XCTAssertEqual(hit?.windowID, 1, "first window in the (already front-to-back ordered) list owned by pid 100")
    }

    func testFrontmostWindowOwnedByUnknownPIDReturnsNil() {
        XCTAssertNil(WindowPicker.frontmostWindow(ownedBy: 999, in: windows))
    }

    /// `onScreenWindows()` filters at the source so no caller can ever resolve a hover/click to one
    /// of Clipr's own windows (the full-screen capture overlay above all else) or to system chrome
    /// living above the normal window layer. Vacuously true if the list comes back empty, which is
    /// fine - the point is that a violation can never appear.
    func testOnScreenWindowsExcludesOwnProcessAndNonNormalLayers() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in WindowPicker.onScreenWindows() {
            XCTAssertNotEqual(window.ownerPID, ownPID, "Clipr's own windows must never be selectable targets")
            XCTAssertEqual(window.layer, 0, "only normal-layer application windows are selectable targets")
        }
    }
}
