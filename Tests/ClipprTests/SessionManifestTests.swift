import XCTest
@testable import Clipr

final class SessionManifestTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([0]))
    }

    private func record(_ file: String, caption: String? = nil) -> StepRecord {
        StepRecord(id: UUID(), file: file, kind: .click, caption: caption, clickPoint: CGPoint(x: 1, y: 2),
                   zoomFile: nil, appName: "Safari", capturedAt: Date(timeIntervalSince1970: 1000))
    }

    func testRoundTripPreservesOrderAndFields() throws {
        touch("Step_01.png"); touch("Step_02.png")
        let manifest = SessionManifest(createdAt: Date(timeIntervalSince1970: 0),
                                       steps: [record("Step_02.png", caption: "B"), record("Step_01.png", caption: "A")])
        try SessionManifestStore.save(manifest, in: folder)
        XCTAssertEqual(SessionManifestStore.load(from: folder), manifest)
    }

    func testMissingManifestReconstructsFromPNGs() {
        touch("Step_10.png"); touch("Step_2.png"); touch("Step_01.png")
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.file), ["Step_01.png", "Step_2.png", "Step_10.png"])
        XCTAssertTrue(loaded.steps.allSatisfy { $0.kind == .manual && $0.caption == nil })
    }

    func testCorruptManifestReconstructs() throws {
        touch("Step_01.png")
        try Data("not json".utf8).write(to: folder.appendingPathComponent(SessionManifestStore.fileName))
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.map(\.file), ["Step_01.png"])
    }

    func testReconstructionIgnoresDerivedFiles() {
        touch("Step_01.png"); touch("Step_01_edited.png"); touch("Step_01_zoom.png")
        touch("Step_01_annotations.json"); touch(".DS_Store")
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.map(\.file), ["Step_01.png"])
    }

    func testOrphanPNGsAreAppendedAndMissingFilesDropped() throws {
        touch("Step_01.png"); touch("Step_03.png")
        let manifest = SessionManifest(createdAt: Date(), steps: [record("Step_02.png"), record("Step_01.png", caption: "keep")])
        try SessionManifestStore.save(manifest, in: folder)
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.file), ["Step_01.png", "Step_03.png"])
        XCTAssertEqual(loaded.steps[0].caption, "keep")
        XCTAssertEqual(loaded.steps[1].kind, .manual)
    }

    func testZoomName() {
        XCTAssertEqual(FilenameGenerator.zoomName(fromStep: "Step_03.png"), "Step_03_zoom.png")
    }

    func testSaveSafelyWritesWhenFolderListable() throws {
        touch("Step_01.png")
        let m = SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: [record("Step_01.png", caption: "A")])
        try SessionManifestStore.saveSafely(m, in: folder)
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.first?.caption, "A")
    }

    /// Write-and-search but no read permission: a plain save would succeed here, which is exactly
    /// the case where a manifest built from an empty listing could overwrite real captions.
    func testSaveSafelyRefusesWhenFolderUnlistable() throws {
        touch("Step_01.png")
        try SessionManifestStore.save(SessionManifest(createdAt: Date(), steps: [record("Step_01.png", caption: "keep")]), in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertThrowsError(try SessionManifestStore.saveSafely(SessionManifest(createdAt: Date()), in: folder)) {
            XCTAssertEqual($0 as? SessionManifestStore.StoreError, .folderUnreadable)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.first?.caption, "keep")
    }

    func testLoadDropsDuplicateEntries() throws {
        touch("Step_01.png")
        let m = SessionManifest(createdAt: Date(timeIntervalSince1970: 0),
                                steps: [record("Step_01.png", caption: "first"), record("Step_01.png", caption: "dup")])
        try SessionManifestStore.save(m, in: folder)
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.caption), ["first"])
    }

    func testNewerVersionIsReadOnly() {
        var m = SessionManifest(createdAt: Date())
        XCTAssertFalse(SessionManifestStore.isReadOnly(m))
        m.version = SessionManifestStore.currentVersion + 1
        XCTAssertTrue(SessionManifestStore.isReadOnly(m))
    }
}
