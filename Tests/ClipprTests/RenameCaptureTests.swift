import XCTest
import Cocoa
@testable import Clipr

/// Renaming a capture has to move three files that are all keyed off its name — the raw PNG, the
/// flattened `_edited.png`, and the annotations sidecar — without ever clobbering another
/// capture that happens to share the requested name.
final class RenameCaptureTests: XCTestCase {
    private var folder: URL!
    private var storage: StorageManager!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipr-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storage = StorageManager(baseFolder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Helpers

    private func touch(_ name: String, contents: String = "x") {
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent(name).path,
            contents: Data(contents.utf8)
        )
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    /// A capture plus both of the files that follow its name around.
    private func makeCapture(_ base: String) -> URL {
        touch("\(base).png", contents: base)
        touch("\(base)_edited.png", contents: "\(base)-edited")
        touch("\(base)_annotations.json", contents: "[]")
        return folder.appendingPathComponent("\(base).png")
    }

    // MARK: - Sanitising

    func testSanitiserStripsATypedExtensionSoItIsNotDoubled() {
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName("Login screen.png"), "Login screen")
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName("Login screen.PNG"), "Login screen")
    }

    func testSanitiserFoldsPathSeparatorsRatherThanEscapingTheFolder() {
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName("Step 3/4"), "Step 3-4")
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName("a:b"), "a-b")

        // Separators fold first and the leading-dot strip then runs on the result, so a traversal
        // attempt loses its leading `..` too. What matters is only that no separator survives and
        // the name can't start with a dot.
        let traversal = FilenameGenerator.sanitizedBaseName("../../etc/passwd")
        XCTAssertEqual(traversal, "-..-etc-passwd")
        XCTAssertFalse(traversal!.contains("/"))
        XCTAssertFalse(traversal!.hasPrefix("."))
    }

    func testSanitiserDropsLeadingDotsSoARenameCannotHideTheCapture() {
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName(".hidden"), "hidden")
        XCTAssertEqual(FilenameGenerator.sanitizedBaseName("...hidden"), "hidden")
    }

    func testSanitiserRejectsNamesWithNothingUsableLeft() {
        XCTAssertNil(FilenameGenerator.sanitizedBaseName(""))
        XCTAssertNil(FilenameGenerator.sanitizedBaseName("   "))
        XCTAssertNil(FilenameGenerator.sanitizedBaseName("."))
        XCTAssertNil(FilenameGenerator.sanitizedBaseName(".png"))
        XCTAssertNil(FilenameGenerator.sanitizedBaseName(String(repeating: "a", count: 201)))
    }

    // MARK: - Renaming

    func testRenameMovesTheRawEditedAndSidecarTogether() throws {
        let original = makeCapture("Screenshot_2026")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "Login screen")

        XCTAssertEqual(renamed.lastPathComponent, "Login screen.png")
        XCTAssertTrue(exists("Login screen.png"))
        XCTAssertTrue(exists("Login screen_edited.png"))
        XCTAssertTrue(exists("Login screen_annotations.json"))
        XCTAssertFalse(exists("Screenshot_2026.png"))
        XCTAssertFalse(exists("Screenshot_2026_edited.png"))
        XCTAssertFalse(exists("Screenshot_2026_annotations.json"))
    }

    func testRenameCarriesTheFileContentsAcross() throws {
        let original = makeCapture("before")
        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "after")

        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "before")
        let edited = folder.appendingPathComponent("after_edited.png")
        XCTAssertEqual(try String(contentsOf: edited, encoding: .utf8), "before-edited")
    }

    func testRenameWorksForACaptureThatWasNeverEdited() throws {
        touch("solo.png")
        let original = folder.appendingPathComponent("solo.png")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "renamed")

        XCTAssertTrue(exists("renamed.png"))
        XCTAssertFalse(exists("solo.png"))
        XCTAssertFalse(exists("renamed_edited.png"), "no companions should be invented")
        XCTAssertEqual(renamed.lastPathComponent, "renamed.png")
    }

    /// The safety property that matters most: a rename must never destroy a different capture.
    func testRenameOntoAnExistingCaptureSuffixesInsteadOfOverwriting() throws {
        let original = makeCapture("mine")
        _ = makeCapture("taken")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "taken")

        XCTAssertEqual(renamed.lastPathComponent, "taken_1.png")
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "mine")
        // The capture that was already called "taken" is untouched.
        XCTAssertEqual(
            try String(contentsOf: folder.appendingPathComponent("taken.png"), encoding: .utf8),
            "taken"
        )
        XCTAssertEqual(
            try String(contentsOf: folder.appendingPathComponent("taken_edited.png"), encoding: .utf8),
            "taken-edited"
        )
    }

    /// A stray `_edited.png` with no capture behind it still blocks the name, so the sidecar and
    /// preview of the renamed capture can't land on top of it.
    func testRenameAvoidsANameWhoseCompanionFilesAreTaken() throws {
        let original = makeCapture("mine")
        touch("orphan_edited.png", contents: "orphan")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "orphan")

        XCTAssertEqual(renamed.lastPathComponent, "orphan_1.png")
        XCTAssertEqual(
            try String(contentsOf: folder.appendingPathComponent("orphan_edited.png"), encoding: .utf8),
            "orphan"
        )
    }

    func testRenamingToTheSameNameIsANoOpRatherThanSuffixing() throws {
        let original = makeCapture("same")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "same")

        XCTAssertEqual(renamed, original)
        XCTAssertTrue(exists("same.png"))
        XCTAssertFalse(exists("same_1.png"))
    }

    /// The extension is managed for the user, so typing it into the field must not double it up.
    func testRenameWithATypedExtensionDoesNotProduceDoubleExtension() throws {
        let original = makeCapture("shot")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "final.png")

        XCTAssertEqual(renamed.lastPathComponent, "final.png")
        XCTAssertFalse(exists("final.png.png"))
    }

    func testRenameCannotEscapeTheCapturesFolder() throws {
        let original = makeCapture("escape")

        let renamed = try storage.renameCapture(rawURL: original, toBaseName: "../outside")

        XCTAssertEqual(renamed.deletingLastPathComponent().standardizedFileURL.path, folder.standardizedFileURL.path)
        XCTAssertEqual(renamed.lastPathComponent, "-outside.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent("outside.png").path),
            "nothing may be written outside the captures folder"
        )
    }

    func testRenameToAnUnusableNameThrowsAndLeavesFilesAlone() throws {
        let original = makeCapture("keep")

        XCTAssertThrowsError(try storage.renameCapture(rawURL: original, toBaseName: "   ")) { error in
            guard case StorageError.invalidFilename = error else {
                return XCTFail("expected invalidFilename, got \(error)")
            }
        }
        XCTAssertTrue(exists("keep.png"))
        XCTAssertTrue(exists("keep_edited.png"))
        XCTAssertTrue(exists("keep_annotations.json"))
    }

    /// Annotations must survive the rename, since the sidecar is what makes reopening a capture
    /// restore editable objects instead of a flat image.
    func testAnnotationsAreStillLoadableUnderTheNewName() throws {
        let raw = folder.appendingPathComponent("annotated.png")
        touch("annotated.png")
        let annotation = AnnotationObject(
            id: UUID(), kind: .rectangle,
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
            strokeWidth: 2
        )
        try storage.saveAnnotations([annotation], rawURL: raw)

        let renamed = try storage.renameCapture(rawURL: raw, toBaseName: "annotated renamed")

        let restored = storage.loadAnnotations(rawURL: renamed)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.frame, annotation.frame)
        XCTAssertTrue(storage.loadAnnotations(rawURL: raw).isEmpty, "old sidecar should be gone")
    }
}
