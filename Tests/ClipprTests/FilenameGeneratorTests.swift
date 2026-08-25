import XCTest
@testable import Clipr

final class FilenameGeneratorTests: XCTestCase {
    func testRawScreenshotName() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 14, minute: 30, second: 12))!
        XCTAssertEqual(FilenameGenerator.rawScreenshotName(date: date, timeZone: cal.timeZone), "Screenshot_2026-08-25_143012.png")
    }

    func testEditedName() {
        XCTAssertEqual(FilenameGenerator.editedName(fromRaw: "Screenshot_2026-08-25_143012.png"), "Screenshot_2026-08-25_143012_edited.png")
    }

    func testSessionFolderName() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 15, minute: 5, second: 0))!
        XCTAssertEqual(FilenameGenerator.sessionFolderName(date: date, timeZone: cal.timeZone), "Session_2026-08-25_150500")
    }

    func testStepNamePadding() {
        XCTAssertEqual(FilenameGenerator.stepName(index: 1), "Step_01.png")
        XCTAssertEqual(FilenameGenerator.stepName(index: 12), "Step_12.png")
    }
}
