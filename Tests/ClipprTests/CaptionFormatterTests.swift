import XCTest
@testable import Clipr

final class CaptionFormatterTests: XCTestCase {
    private func t(_ role: String?, _ label: String?, menu: [String] = []) -> ClickTarget {
        ClickTarget(role: role, subrole: nil, label: label, menuPath: menu)
    }

    func testMenuItemUsesPath() {
        XCTAssertEqual(CaptionFormatter.click(t("AXMenuItem", "Export…", menu: ["File", "Export…"]), appName: "Pages"),
                       "Choose **File ▸ Export…**")
    }

    func testButtonLikeRoles() {
        for role in ["AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXTab"] {
            XCTAssertEqual(CaptionFormatter.click(t(role, "Save"), appName: "Safari"), "Click **Save** in Safari", role)
        }
    }

    func testTextFieldRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(CaptionFormatter.click(t(role, "Name"), appName: "Safari"), "Click the **Name** field", role)
        }
    }

    func testLink() {
        XCTAssertEqual(CaptionFormatter.click(t("AXLink", "Pricing"), appName: "Safari"), "Click the **Pricing** link")
    }

    func testOtherLabelledRole() {
        XCTAssertEqual(CaptionFormatter.click(t("AXImage", "Logo"), appName: "Finder"), "Click **Logo** in Finder")
    }

    func testFallbacks() {
        XCTAssertEqual(CaptionFormatter.click(nil, appName: "Finder"), "Click in **Finder**")
        XCTAssertEqual(CaptionFormatter.click(t("AXButton", "   "), appName: "Finder"), "Click in **Finder**")
        XCTAssertEqual(CaptionFormatter.click(nil, appName: nil), "Click")
        XCTAssertEqual(CaptionFormatter.click(t("AXButton", "Save"), appName: nil), "Click **Save**")
    }

    func testTypingAndShortcut() {
        XCTAssertEqual(CaptionFormatter.typing("John", fieldLabel: "Name"), #"Type "John" in **Name**"#)
        XCTAssertEqual(CaptionFormatter.typing("John", fieldLabel: nil), #"Type "John""#)
        XCTAssertEqual(CaptionFormatter.shortcut("⌘S"), "Press **⌘S**")
    }

    func testCleanCollapsesWhitespaceTruncatesAndEscapes() {
        XCTAssertEqual(CaptionFormatter.clean("  Save\n\n  As  "), "Save As")
        XCTAssertEqual(CaptionFormatter.clean(String(repeating: "a", count: 70)), String(repeating: "a", count: 60) + "…")
        XCTAssertEqual(CaptionFormatter.clean(#"**Bold** "q""#), #"\*\*Bold\*\* \"q\""#)
        XCTAssertNil(CaptionFormatter.clean(" \n "))
        XCTAssertNil(CaptionFormatter.clean(nil))
    }

    func testTypingTextIsCleanedToo() {
        XCTAssertEqual(CaptionFormatter.typing(#"say "hi""#, fieldLabel: nil), #"Type "say \"hi\"""#)
    }
}
