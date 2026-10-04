import XCTest
@testable import Clipr

final class CaptureTimeoutAndScaleTests: XCTestCase {
    func testAFastOperationReturnsItsValue() async throws {
        let value = try await withTimeout(5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testAnOperationThatNeverReturnsTimesOut() async {
        let started = Date()
        do {
            _ = try await withTimeout(0.2) { () async throws -> Int in
                // Ignores cancellation, like a stuck system call.
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return 1
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error is TimedOutError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testErrorsPassThrough() async {
        do {
            _ = try await withTimeout(5) { () async throws -> Int in throw CaptureError.cropFailed }
            XCTFail("expected the operation's error")
        } catch {
            XCTAssertTrue(error is CaptureError)
        }
    }

    // MARK: - Window scale

    private let retina = (rect: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: CGFloat(2))
    private let external = (rect: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: CGFloat(1))

    func testAWindowTakesTheScaleOfTheScreenHoldingMostOfIt() {
        // Top-left on the Retina screen, but mostly on the 1x external display.
        let window = CGRect(x: 1400, y: 100, width: 1000, height: 600)
        XCTAssertEqual(scaleFactor(for: window, screens: [retina, external], fallback: 2), 1)
    }

    func testAWindowWhoseOriginIsOffScreenStillGetsItsScreensScale() {
        let window = CGRect(x: -200, y: -50, width: 800, height: 600)
        XCTAssertEqual(scaleFactor(for: window, screens: [external, retina], fallback: 1), 2)
    }

    func testAWindowOnNoScreenUsesTheFallback() {
        XCTAssertEqual(scaleFactor(for: CGRect(x: 9000, y: 9000, width: 10, height: 10), screens: [retina], fallback: 3), 3)
    }
}
