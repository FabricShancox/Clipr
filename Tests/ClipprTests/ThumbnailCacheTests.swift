import XCTest
import Cocoa
@testable import Clipr

final class ThumbnailCacheTests: XCTestCase {
    func testStoreAndRetrieveByURL() {
        let cache = ThumbnailCache.shared
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png")
        XCTAssertNil(cache.image(for: url))

        let image = NSImage(size: NSSize(width: 1, height: 1))
        cache.store(image, for: url)
        XCTAssertNotNil(cache.image(for: url))
    }

    func testDifferentURLsDoNotCollide() {
        let cache = ThumbnailCache.shared
        let urlA = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png")
        let urlB = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png")
        cache.store(NSImage(size: NSSize(width: 1, height: 1)), for: urlA)
        XCTAssertNil(cache.image(for: urlB))
    }
}
