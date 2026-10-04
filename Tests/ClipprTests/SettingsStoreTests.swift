import XCTest
import Cocoa
@testable import Clipr

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
        store = SettingsStore(defaults: defaults, loginItem: FakeLoginItem())
    }

    func testDefaultsWhenUnset() {
        XCTAssertEqual(store.captureHotkey, HotkeyBinding.defaultCapture)
        XCTAssertEqual(store.advancedModeHotkey, HotkeyBinding.defaultAdvancedMode)
        XCTAssertEqual(store.saveFolder, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots"))
        XCTAssertFalse(store.launchAtLogin)
    }

    /// Preferences and the editor each toggle one part; neither may overwrite the other's.
    func testCopyStylePartsAreIndependentKeys() {
        store.copyShadow = true
        let editorSide = SettingsStore(defaults: defaults)
        editorSide.copyBorder = true
        XCTAssertEqual(store.copyStyle, CopyStyle(border: true, shadow: true))
        editorSide.copyBorder = false
        XCTAssertTrue(store.copyShadow)
        XCTAssertTrue(defaults.bool(forKey: SettingsStore.copyShadowKey), "views bind @AppStorage to this key")
    }

    func testCaptureHotkeyPersists() {
        let custom = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.option.rawValue)
        store.captureHotkey = custom
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.captureHotkey, custom)
    }

    func testSaveFolderPersists() {
        let custom = URL(fileURLWithPath: "/tmp/clipr-test-folder")
        store.saveFolder = custom
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.saveFolder, custom)
    }

    func testLaunchAtLoginReflectsTheSystemNotAStoredFlag() throws {
        let item = FakeLoginItem()
        let store = SettingsStore(defaults: defaults, loginItem: item)
        try store.setLaunchAtLogin(true)
        XCTAssertTrue(store.launchAtLogin)
        item.isEnabled = false // switched off in System Settings
        XCTAssertFalse(SettingsStore(defaults: defaults, loginItem: item).launchAtLogin)
    }

    func testAFailedRegistrationThrowsAndStaysOff() {
        let item = FakeLoginItem()
        item.failure = CocoaError(.featureUnsupported)
        let store = SettingsStore(defaults: defaults, loginItem: item)
        XCTAssertThrowsError(try store.setLaunchAtLogin(true))
        XCTAssertFalse(store.launchAtLogin)
    }

    func testReviewLayoutDefaultsToListAndPersists() {
        XCTAssertEqual(store.reviewLayout, .list)
        store.reviewLayout = .guide
        XCTAssertEqual(SettingsStore(defaults: defaults).reviewLayout, .guide)
    }

    func testUnknownReviewLayoutFallsBackToList() {
        defaults.set("carousel", forKey: SettingsStore.reviewLayoutKey)
        XCTAssertEqual(store.reviewLayout, .list)
    }

    func testExportOptionsDefaultAndPersist() {
        XCTAssertEqual(store.exportOptions(title: "T"), ExportOptions(format: .pdf, title: "T", includeZoom: false, gifFrameSeconds: 2))
        store.rememberExportOptions(ExportOptions(format: .markdown, title: "Ignored", includeZoom: true, gifFrameSeconds: 4))
        XCTAssertEqual(SettingsStore(defaults: defaults).exportOptions(title: "New"),
                       ExportOptions(format: .markdown, title: "New", includeZoom: true, gifFrameSeconds: 4))
    }

    func testNonFiniteFrameTimeFallsBackToDefault() {
        for value in [Double.nan, .infinity, -.infinity] {
            defaults.set(value, forKey: "exportGIFFrameSeconds")
            XCTAssertEqual(store.exportOptions(title: "T").gifFrameSeconds, 2)
        }
    }

    func testExportOptionsToleratesUnknownFormatAndOutOfRangeFrameTime() {
        defaults.set("pptx", forKey: "exportFormat")
        defaults.set(12.0, forKey: "exportGIFFrameSeconds")
        let options = store.exportOptions(title: "T")
        XCTAssertEqual(options.format, .pdf)
        XCTAssertEqual(options.gifFrameSeconds, 5)
    }

    func testThumbnailCacheKeepsSizesApartAndRemovesAll() {
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png")
        let small = NSImage(size: CGSize(width: 1, height: 1)), big = NSImage(size: CGSize(width: 2, height: 2))
        ThumbnailCache.shared.store(small, for: url)
        ThumbnailCache.shared.store(big, for: url, maxPixelSize: ThumbnailCache.largePixelSize)
        XCTAssertTrue(ThumbnailCache.shared.image(for: url) === small)
        XCTAssertTrue(ThumbnailCache.shared.image(for: url, maxPixelSize: ThumbnailCache.largePixelSize) === big)
        ThumbnailCache.shared.remove(url)
        XCTAssertNil(ThumbnailCache.shared.image(for: url))
        XCTAssertNil(ThumbnailCache.shared.image(for: url, maxPixelSize: ThumbnailCache.largePixelSize))
    }
}

private final class FakeLoginItem: LoginItem {
    var isEnabled = false
    var failure: Error?
    func register() throws { if let failure { throw failure }; isEnabled = true }
    func unregister() throws { if let failure { throw failure }; isEnabled = false }
}
