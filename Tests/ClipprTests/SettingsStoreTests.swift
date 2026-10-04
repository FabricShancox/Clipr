import XCTest
import Cocoa
@testable import Clipr

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
        store = SettingsStore(defaults: defaults)
    }

    func testDefaultsWhenUnset() {
        XCTAssertEqual(store.captureHotkey, HotkeyBinding.defaultCapture)
        XCTAssertEqual(store.advancedModeHotkey, HotkeyBinding.defaultAdvancedMode)
        XCTAssertEqual(store.saveFolder, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots"))
        XCTAssertFalse(store.launchAtLogin)
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

    func testLaunchAtLoginPersists() {
        store.launchAtLogin = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.launchAtLogin)
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
