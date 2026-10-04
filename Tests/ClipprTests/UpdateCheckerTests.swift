import XCTest
@testable import Clipr

final class UpdateCheckerTests: XCTestCase {
    private let fallback = URL(string: "https://github.com/FabricShancox/Clipr/releases")!

    func testAGitHubReleasePageIsOpenedAsIs() {
        let page = URL(string: "https://github.com/FabricShancox/Clipr/releases/tag/v1.2.0")!
        XCTAssertEqual(UpdateChecker.releasePage(for: page), page)
    }

    func testAnythingElseFallsBackToTheFixedReleasesPage() {
        let hostile = [
            "file:///Applications/Calculator.app",
            "http://github.com/FabricShancox/Clipr/releases/tag/v1.2.0",
            "https://github.com.evil.example/FabricShancox/Clipr/releases",
            "https://evil.example/FabricShancox/Clipr/releases",
            "https://github.com/someone-else/Clipr/releases/tag/v9",
            "https://github.com/FabricShancox/Clipr/../../evil/releases",
            "x-apple-systempreferences:com.apple.preference.security",
            "https://user@github.com/FabricShancox/Clipr/releases",
        ]
        for string in hostile {
            XCTAssertEqual(UpdateChecker.releasePage(for: URL(string: string)), fallback, string)
        }
        XCTAssertEqual(UpdateChecker.releasePage(for: nil), fallback)
    }

    func testAutomaticChecksAreOnByDefaultAndCanBeTurnedOff() {
        let defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.checkForUpdatesAutomatically)
        settings.checkForUpdatesAutomatically = false
        XCTAssertFalse(UpdateChecker(defaults: defaults).isAutomaticCheckEnabled)
    }
}
