import XCTest
@testable import Clipr

final class ClickDescriberTests: XCTestCase {
    func testKnownTerminalsAreTerminals() {
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
                   "org.alacritty", "com.mitchellh.ghostty", "com.github.wez.wezterm"] {
            XCTAssertTrue(ClickDescriber.isTerminal(bundleID: id), id)
        }
    }

    func testOtherAppsAreNotTerminals() {
        XCTAssertFalse(ClickDescriber.isTerminal(bundleID: "com.apple.Safari"))
        XCTAssertFalse(ClickDescriber.isTerminal(bundleID: nil))
    }
}
