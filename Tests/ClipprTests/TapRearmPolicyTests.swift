import XCTest
@testable import Clipr

final class TapRearmPolicyTests: XCTestCase {
    func testTimeoutRearmsAtOnce() {
        var policy = TapRearmPolicy()
        XCTAssertEqual(policy.handleDisable(byUserInput: false).action, .rearmNow)
    }

    func testUserInputDisableRearmsOnlyAfterBackoff() {
        var policy = TapRearmPolicy()
        XCTAssertEqual(policy.handleDisable(byUserInput: true).action, .rearmAfter(TapRearmPolicy.userInputBackoff))
    }

    func testLoggingIsRateLimited() {
        var policy = TapRearmPolicy()
        let logged = (1...25).map { _ in policy.handleDisable(byUserInput: false).log != nil }
        XCTAssertEqual(logged.enumerated().filter(\.element).map { $0.offset + 1 }, [1, 10, 20])
    }
}
