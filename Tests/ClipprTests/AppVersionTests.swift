import XCTest
@testable import Clipr

final class AppVersionTests: XCTestCase {
    func testParsesTagWithLeadingV() {
        XCTAssertEqual(AppVersion("v1.2.3")?.components, [1, 2, 3])
    }

    func testRejectsNonNumericVersions() {
        XCTAssertNil(AppVersion("1.2.beta"))
        XCTAssertNil(AppVersion(""))
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertLessThan(AppVersion("1.0")!, AppVersion("1.0.1")!)
    }
}
