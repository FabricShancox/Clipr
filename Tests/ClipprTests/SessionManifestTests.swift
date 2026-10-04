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

    // L7: two records sharing an id (a hand-edited or sync-merged session.json) must not crash
    // Review; the later one gets a fresh id and keeps everything else.
    func testDuplicateIDsAreMadeUnique() throws {
        touch("Step_01.png"); touch("Step_02.png")
        let first = record("Step_01.png", caption: "A")
        var second = record("Step_02.png", caption: "B")
        second = StepRecord(id: first.id, file: second.file, kind: second.kind, caption: second.caption,
                            clickPoint: second.clickPoint, zoomFile: nil, appName: second.appName,
                            capturedAt: second.capturedAt, imageSize: .small)
        try SessionManifestStore.save(SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: [first, second]), in: folder)
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.file), ["Step_01.png", "Step_02.png"])
        XCTAssertEqual(loaded.steps[0].id, first.id)
        XCTAssertNotEqual(loaded.steps[1].id, first.id)
        XCTAssertEqual(loaded.steps[1].caption, "B")
        XCTAssertEqual(loaded.steps[1].imageSize, .small)
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

    func testLoadForReviewFlagsUndecodableAndNewerManifests() throws {
        touch("Step_01.png")
        let url = folder.appendingPathComponent(SessionManifestStore.fileName)
        XCTAssertNil(SessionManifestStore.loadForReview(from: folder).readOnly, "no session.json is writable")
        try SessionManifestStore.save(SessionManifest(createdAt: Date(), steps: [record("Step_01.png")]), in: folder)
        XCTAssertNil(SessionManifestStore.loadForReview(from: folder).readOnly)
        try Data(#"{"version": 3, "steps": "unknown shape"}"#.utf8).write(to: url)
        XCTAssertEqual(SessionManifestStore.loadForReview(from: folder).readOnly, .newerVersion)
        try Data("not json".utf8).write(to: url)
        let garbage = SessionManifestStore.loadForReview(from: folder)
        XCTAssertEqual(garbage.readOnly, .unreadable)
        XCTAssertEqual(garbage.manifest.steps.map(\.file), ["Step_01.png"])
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
    // MARK: Image size compatibility

    private func decode(_ json: String) throws -> SessionManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionManifest.self, from: Data(json.utf8))
    }

    private func manifestJSON(stepExtra: String) -> String {
        """
        {"version": 1, "createdAt": "2026-01-01T00:00:00Z", "steps": [
          {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "file": "Step_01.png", "kind": "click",
           "capturedAt": "2026-01-01T00:00:00Z"\(stepExtra)}
        ]}
        """
    }

    func testManifestWithImageSizeDecodes() throws {
        let m = try decode(manifestJSON(stepExtra: #", "imageSize": "medium""#))
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.steps[0].imageSize, .medium)
    }

    func testManifestWithoutImageSizeDecodesAsNil() throws {
        XCTAssertNil(try decode(manifestJSON(stepExtra: "")).steps[0].imageSize)
    }

    /// Unsized steps write no key at all, so a session nobody resized is byte-for-byte what an
    /// older Clipr wrote; sizing keeps version 1 because older builds ignore the unknown key.
    func testImageSizeRoundTripsAndNilWritesNoKey() throws {
        touch("Step_01.png"); touch("Step_02.png")
        var sized = record("Step_01.png")
        sized.imageSize = .small
        let m = SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: [sized, record("Step_02.png")])
        try SessionManifestStore.save(m, in: folder)
        XCTAssertEqual(SessionManifestStore.load(from: folder), m)
        let text = try String(contentsOf: folder.appendingPathComponent(SessionManifestStore.fileName), encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "imageSize").count - 1, 1)
        XCTAssertTrue(text.contains(#""version" : 1"#))
        XCTAssertNil(SessionManifestStore.loadForReview(from: folder).readOnly)
    }

    func testImageSizeWidthFractions() {
        XCTAssertEqual(ImageSize.allCases, [.small, .medium, .large, .full])
        XCTAssertEqual(ImageSize.allCases.map(\.widthFraction), [0.40, 0.60, 0.80, 1.0])
    }

    func testUnknownImageSizeLoadsAsFullStoredAsNilInsteadOfFailing() throws {
        touch("Step_01.png")
        let json = """
        {"version":1,"createdAt":"1970-01-01T00:00:00Z","steps":[{"id":"\(UUID().uuidString)","file":"Step_01.png","kind":"click","caption":"keep","capturedAt":"1970-01-01T00:00:00Z","imageSize":"huge"}]}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent(SessionManifestStore.fileName))
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.first?.caption, "keep")
        XCTAssertNil(loaded.steps.first?.imageSize, "Full is always stored as nil")
        XCTAssertNil(SessionManifestStore.loadForReview(from: folder).manifest.steps.first?.imageSize)
        XCTAssertNil(SessionManifestStore.loadForReview(from: folder).readOnly)
    }
}
