import XCTest
@testable import Clipr

final class RecentCapturesFinderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func touch(_ name: String, secondsAgo: TimeInterval) throws {
        let url = tempDir.appendingPathComponent(name)
        try Data().write(to: url)
        let date = Date().addingTimeInterval(-secondsAgo)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Compares by filename only — macOS's temp directory is reached through a `/var` ->
    /// `/private/var` symlink, and `contentsOfDirectory`/`resolvingSymlinksInPath()` don't
    /// consistently agree on which side of that alias a path comes back on, which is noise
    /// this test doesn't care about.
    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    func testSortsNewestFirst() throws {
        try touch("Screenshot_1.png", secondsAgo: 100)
        try touch("Screenshot_2.png", secondsAgo: 1)
        XCTAssertEqual(names(recentCaptures(in: tempDir)), ["Screenshot_2.png", "Screenshot_1.png"])
    }

    func testExcludesEditedCompanions() throws {
        try touch("Screenshot_1.png", secondsAgo: 10)
        try touch("Screenshot_1_edited.png", secondsAgo: 5)
        XCTAssertEqual(names(recentCaptures(in: tempDir)), ["Screenshot_1.png"])
    }

    func testExcludesNonPngFiles() throws {
        try touch("Screenshot_1.png", secondsAgo: 10)
        try touch("Screenshot_1_annotations.json", secondsAgo: 5)
        XCTAssertEqual(names(recentCaptures(in: tempDir)), ["Screenshot_1.png"])
    }

    func testRespectsLimit() throws {
        for i in 0..<5 {
            try touch("Screenshot_\(i).png", secondsAgo: TimeInterval(i))
        }
        XCTAssertEqual(recentCaptures(in: tempDir, limit: 3).count, 3)
    }

    func testReturnsEmptyForAMissingFolder() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        XCTAssertEqual(recentCaptures(in: missing), [])
    }
}
