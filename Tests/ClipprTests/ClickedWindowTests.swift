import XCTest
@testable import Clipr

final class ClickedWindowTests: XCTestCase {
    private func entry(_ id: CGWindowID, pid: pid_t, _ rect: CGRect, layer: Int = 0, alpha: CGFloat = 1, owner: String = "App") -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: ["X": rect.minX, "Y": rect.minY, "Width": rect.width, "Height": rect.height] as [String: CGFloat],
        ]
    }

    func testFloatingPaletteInFrontOfDocumentIsTheClickedWindow() {
        let entries = [
            entry(7, pid: 50, CGRect(x: 100, y: 100, width: 200, height: 200), layer: 3, owner: "Pixelmator"),
            entry(8, pid: 50, CGRect(x: 0, y: 0, width: 1000, height: 800), owner: "Pixelmator"),
        ]
        let hit = ClickHitTest.resolve(CGPoint(x: 150, y: 150), in: entries, ownPID: 1)
        XCTAssertEqual(hit, .other(ClickedWindow(windowID: 7, ownerPID: 50, layer: 3, appName: "Pixelmator")))
        if case .other(let window?) = hit { XCTAssertTrue(window.isCapturable) }
    }

    func testOwnWindowOnTopIsOwnClick() {
        let entries = [
            entry(1, pid: 99, CGRect(x: 0, y: 0, width: 300, height: 50), layer: 3),
            entry(2, pid: 50, CGRect(x: 0, y: 0, width: 1000, height: 800)),
        ]
        XCTAssertEqual(ClickHitTest.resolve(CGPoint(x: 10, y: 10), in: entries, ownPID: 99), .own)
    }

    func testTransparentWindowsAreSkipped() {
        let entries = [
            entry(1, pid: 60, CGRect(x: 0, y: 0, width: 1000, height: 800), layer: 25, alpha: 0),
            entry(2, pid: 50, CGRect(x: 0, y: 0, width: 1000, height: 800), owner: "Safari"),
        ]
        XCTAssertEqual(ClickHitTest.resolve(CGPoint(x: 10, y: 10), in: entries, ownPID: 99),
                       .other(ClickedWindow(windowID: 2, ownerPID: 50, layer: 0, appName: "Safari")))
    }

    func testDockAndMenusAreNotCapturable() {
        XCTAssertFalse(ClickedWindow(windowID: 1, ownerPID: 1, layer: ClickedWindow.dockLayer, appName: nil).isCapturable)
        XCTAssertFalse(ClickedWindow(windowID: 1, ownerPID: 1, layer: 101, appName: nil).isCapturable)
        XCTAssertFalse(ClickedWindow(windowID: 1, ownerPID: 1, layer: -2147483603, appName: nil).isCapturable)
        XCTAssertTrue(ClickedWindow(windowID: 1, ownerPID: 1, layer: 0, appName: nil).isCapturable)
    }

    func testNothingUnderClick() {
        XCTAssertEqual(ClickHitTest.resolve(CGPoint(x: 5000, y: 5000), in: [entry(2, pid: 50, CGRect(x: 0, y: 0, width: 10, height: 10))], ownPID: 1), .other(nil))
    }

    func testAppNameLookupWins() {
        let hit = ClickHitTest.resolve(CGPoint(x: 1, y: 1), in: [entry(2, pid: 50, CGRect(x: 0, y: 0, width: 10, height: 10), owner: "raw")],
                                       ownPID: 1, appName: { _ in "Localized" })
        XCTAssertEqual(hit, .other(ClickedWindow(windowID: 2, ownerPID: 50, layer: 0, appName: "Localized")))
    }
}
