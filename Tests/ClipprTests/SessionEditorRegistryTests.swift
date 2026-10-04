import XCTest
@testable import Clipr

/// Editors opened from Review live per session, not per Review window, so closing Review leaves
/// them known to the next Review of that session and to quit's flush.
@MainActor
final class SessionEditorRegistryTests: XCTestCase {
    private final class FakeEditor {}

    func testEditorsSurviveAReviewAndReachTheNextOne() {
        let registry = SessionEditorRegistry()
        var firstReview: Set<UUID> = []
        registry.onStepsInEditorChanged = { firstReview = $0 }
        let editor = FakeEditor()
        let step = UUID()
        var flushed = 0
        registry.add(.init(editor: editor, stepID: step, flush: { flushed += 1 }, bringForward: {}))
        XCTAssertEqual(firstReview, [step])

        // First Review closes; a second attaches and still sees the open editor.
        registry.onStepsInEditorChanged = nil
        XCTAssertEqual(registry.stepIDs, [step])
        XCTAssertNotNil(registry.entry(for: step), "a reopened Review brings the open editor forward")
        registry.flushAll()
        XCTAssertEqual(flushed, 1)

        var secondReview: Set<UUID> = [step]
        var reloaded: [UUID] = []
        registry.onStepsInEditorChanged = { secondReview = $0 }
        registry.onEditorFinished = { reloaded.append($0) }
        registry.finished(editor)
        XCTAssertEqual(secondReview, [])
        XCTAssertEqual(reloaded, [step])
        XCTAssertTrue(registry.isEmpty)
    }

    func testCoordinatorKeepsOneRegistryPerSessionFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = base.appendingPathComponent("Session_A")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coordinator = AdvancedModeCoordinator(storage: StorageManager(baseFolder: base))
        let registry = coordinator.editorRegistry(for: folder)
        let editor = FakeEditor()
        var flushed = 0
        registry.add(.init(editor: editor, stepID: UUID(), flush: { flushed += 1 }, bringForward: {}))
        XCTAssertTrue(coordinator.editorRegistry(for: folder.appendingPathComponent("../Session_A")) === registry)
        coordinator.flushOpenReviews()
        XCTAssertEqual(flushed, 1, "quit reaches editors whose Review is closed")
        registry.finished(editor)
        XCTAssertFalse(coordinator.editorRegistry(for: folder) === registry, "an empty registry is dropped")
    }
}
