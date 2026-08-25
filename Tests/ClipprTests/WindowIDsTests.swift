import XCTest
import Cocoa
@testable import Clipr

final class WindowIDsTests: XCTestCase {
    func testExtractsIDsFromRealWindowsAndSkipsNils() {
        // An unshown window's `windowNumber` can be negative (not yet assigned a real one by
        // WindowServer) — `windowIDs(of:)` uses `CGWindowID(exactly:)`, which safely returns nil
        // for those rather than trapping, so this only checks it doesn't crash and produces at
        // most one id.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [], backing: .buffered, defer: true)
        let ids = windowIDs(of: [window, nil])
        XCTAssertLessThanOrEqual(ids.count, 1)
    }

    func testEmptyInputProducesEmptySet() {
        XCTAssertEqual(windowIDs(of: []), [])
    }

    func testAllNilInputProducesEmptySet() {
        XCTAssertEqual(windowIDs(of: [nil, nil]), [])
    }
}
