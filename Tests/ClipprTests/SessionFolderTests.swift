import XCTest
@testable import Clipr

final class SessionFolderTests: XCTestCase {
    var base: URL!

    override func setUp() {
        super.setUp()
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
        super.tearDown()
    }

    func testSameSecondGetsANewFolderAndLeavesTheOldOneAlone() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try SessionFolder.create(in: base, date: date)
        try Data("old".utf8).write(to: first.appendingPathComponent("session.json"))
        let second = try SessionFolder.create(in: base, date: date)
        let third = try SessionFolder.create(in: base, date: date)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(second, third)
        XCTAssertEqual(second.lastPathComponent, first.lastPathComponent + "_2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("session.json").path))
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("session.json")), "old")
    }

    func testFolderIsOwnerOnly() throws {
        let folder = try SessionFolder.create(in: base, date: Date())
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testRestrictMakesFileOwnerOnly() throws {
        let folder = try SessionFolder.create(in: base, date: Date())
        let file = folder.appendingPathComponent("Step_01.png")
        try Data([1]).write(to: file)
        SessionFolder.restrict(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
