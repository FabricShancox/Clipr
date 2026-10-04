import XCTest
@testable import Clipr

@MainActor
final class AdvancedModeCoordinatorTests: XCTestCase {
    var base: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    private func session(_ name: String, steps: Int) throws -> URL {
        let folder = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<steps {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("Step_0\(i + 1).png").path, contents: Data([1]))
        }
        return folder
    }

    func testLatestSessionSkipsEmptyAndActiveFolders() throws {
        let older = try session("Session_2026-10-01_090000", steps: 2)
        let newer = try session("Session_2026-10-02_090000", steps: 1)
        try session("Session_2026-10-03_090000", steps: 0)
        XCTAssertEqual(AdvancedModeCoordinator.latestSessionWithSteps(in: base, excluding: nil)?.lastPathComponent,
                       newer.lastPathComponent)
        // The session being recorded is never offered, even if it's the newest with steps.
        XCTAssertEqual(AdvancedModeCoordinator.latestSessionWithSteps(in: base, excluding: newer)?.lastPathComponent,
                       older.lastPathComponent)
    }

    func testOnlyActiveSessionWithStepsMeansNone() throws {
        let active = try session("Session_2026-10-02_090000", steps: 3)
        XCTAssertNil(AdvancedModeCoordinator.latestSessionWithSteps(in: base, excluding: active))
    }

    func testOpeningSameFolderTwiceReusesController() throws {
        let folder = try session("Session_2026-10-02_090000", steps: 1)
        let coordinator = AdvancedModeCoordinator(storage: StorageManager(baseFolder: base))
        let first = coordinator.openReview(sessionFolder: folder)
        let second = coordinator.openReview(sessionFolder: folder.appendingPathComponent("."))
        XCTAssertTrue(first === second)
        XCTAssertEqual(coordinator.reviewWindows.count, 1)
        let other = coordinator.openReview(sessionFolder: try session("Session_2026-10-03_090000", steps: 1))
        XCTAssertFalse(other === first)
        XCTAssertEqual(coordinator.reviewWindows.count, 2)
        coordinator.reviewWindows.forEach { $0?.close() }
    }
}
