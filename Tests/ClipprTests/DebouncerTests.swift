import XCTest
@testable import Clipr

final class DebouncerTests: XCTestCase {
    func testOnlyLastCallFiresWithinWindow() {
        let debouncer = Debouncer(delay: 0.05, queue: .main)
        var fireCount = 0
        var lastValue = -1

        let expectation = expectation(description: "debounced call fires once")

        debouncer.call { fireCount += 1; lastValue = 1 }
        debouncer.call { fireCount += 1; lastValue = 2 }
        debouncer.call { fireCount += 1; lastValue = 3; expectation.fulfill() }

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fireCount, 1, "only the last scheduled call should fire")
        XCTAssertEqual(lastValue, 3)
    }

    func testCallsOutsideWindowBothFire() {
        let debouncer = Debouncer(delay: 0.05, queue: .main)
        var fireCount = 0
        let first = expectation(description: "first call fires")
        let second = expectation(description: "second call fires")

        debouncer.call { fireCount += 1; first.fulfill() }
        wait(for: [first], timeout: 1.0)

        debouncer.call { fireCount += 1; second.fulfill() }
        wait(for: [second], timeout: 1.0)

        XCTAssertEqual(fireCount, 2)
    }
}
