import XCTest
@testable import Clipr

final class ClickDescriberTests: XCTestCase {
    /// An ordinary text field in an ordinary app: the one case typing is recorded for.
    private func field(_ edit: (inout FocusedElementFacts) -> Void = { _ in }) -> FocusedElementFacts {
        var facts = FocusedElementFacts(bundleID: "com.apple.Safari", role: "AXTextField", subrole: nil,
                                        size: CGSize(width: 200, height: 22), domClassList: [], label: "Search")
        edit(&facts)
        return facts
    }

    private func security(_ edit: (inout FocusedElementFacts) -> Void) -> FieldSecurity {
        TypingInputPolicy.security(of: field(edit))
    }

    func testStandardEditableFieldInOrdinaryAppIsNotSecure() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(security { $0.role = role }, .notSecure, role)
        }
        XCTAssertEqual(security { $0.bundleID = "com.apple.TextEdit"; $0.role = "AXTextArea"; $0.label = nil }, .notSecure)
    }

    func testSecureTextFieldIsSecure() {
        XCTAssertEqual(security { $0.subrole = "AXSecureTextField" }, .secure)
    }

    func testFailedReadsAreUnknown() {
        XCTAssertEqual(security { $0.readFailed = true }, .unknown)
        XCTAssertEqual(security { $0.size = nil }, .unknown, "size unreadable")
        XCTAssertEqual(security { $0.bundleID = nil }, .unknown, "app unknown")
    }

    func testTerminalsIDEsAndRemoteViewersAreUnknown() {
        let ids = [
            // Terminals
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp-Preview",
            "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.mitchellh.ghostty", "com.github.wez.wezterm",
            "co.zeit.hyper", "org.tabby",
            // Editors and IDEs (integrated terminals)
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.todesktop.230313mzl4w4u92",
            "com.exafunction.windsurf", "com.jetbrains.intellij", "com.jetbrains.pycharm.ce", "com.jetbrains.goland",
            "com.google.android.studio", "dev.zed.Zed", "com.apple.dt.Xcode",
            // Remote desktop, screen sharing and VMs
            "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.p5sys.jump.mac.viewer",
            "com.citrix.receiver.icaviewer.mac", "com.parallels.desktop.console", "com.vmware.fusion",
            "com.utmapp.UTM", "org.virtualbox.app.VirtualBoxVM", "com.teamviewer.TeamViewer",
            "com.philandro.anydesk", "com.carriez.rustdesk",
            "com.vandyke.SecureCRT", "com.lemonmojo.RoyalTSX.App", "com.sublimetext.3", "tv.parsec.www",
            "com.moonlight-stream.Moonlight", "com.google.chromeremotedesktop.app", "org.vim.MacVim", "org.gnu.Emacs",
        ]
        for id in ids {
            XCTAssertEqual(security { $0.bundleID = id }, .unknown, id)
            XCTAssertTrue(TypingInputPolicy.isUntrustedApp(bundleID: id), id)
        }
    }

    func testAppMatchingIgnoresCase() {
        XCTAssertTrue(TypingInputPolicy.isUntrustedApp(bundleID: "COM.MICROSOFT.VSCODE"))
        XCTAssertTrue(TypingInputPolicy.isUntrustedApp(bundleID: "com.JetBrains.WebStorm"))
    }

    func testOrdinaryAppsAreTrusted() {
        for id in ["com.apple.Safari", "com.google.Chrome", "com.apple.mail", "com.microsoft.Word", "com.apple.Notes"] {
            XCTAssertFalse(TypingInputPolicy.isUntrustedApp(bundleID: id), id)
        }
        XCTAssertFalse(TypingInputPolicy.isUntrustedApp(bundleID: "com.jetbrainsx.thing"), "prefix is the whole component")
    }

    func testMoreWebTerminalMarkersAreUnknown() {
        for cls in ["hterm-cursor", "Guacamole-display", "noVNC_canvas"] {
            XCTAssertEqual(security { $0.role = "AXTextArea"; $0.domClassList = [cls] }, .unknown, cls)
        }
    }

    func testWebTerminalsAreUnknown() {
        XCTAssertEqual(security { $0.role = "AXTextArea"; $0.domClassList = ["xterm-helper-textarea"] }, .unknown, "xterm.js")
        XCTAssertEqual(security { $0.role = "AXTextArea"; $0.domClassList = ["foo", "Terminal-Input"] }, .unknown)
        XCTAssertEqual(security { $0.role = "AXTextArea"; $0.label = "Terminal input" }, .unknown, "xterm.js aria-label")
        XCTAssertEqual(security { $0.role = "AXTextArea"; $0.domClassList = ["comment-box"] }, .notSecure)
    }

    func testNonEditableOrMissingRoleIsUnknown() {
        for role in ["AXWebArea", "AXGroup", "AXButton", "AXScrollArea", "AXUnknown"] {
            XCTAssertEqual(security { $0.role = role }, .unknown, role)
        }
        XCTAssertEqual(security { $0.role = nil }, .unknown)
    }

    func testTinyFieldIsUnknown() {
        XCTAssertEqual(security { $0.size = .zero }, .unknown)
        XCTAssertEqual(security { $0.size = CGSize(width: 1, height: 1) }, .unknown, "hidden input")
        XCTAssertEqual(security { $0.size = CGSize(width: 300, height: 2) }, .unknown)
        XCTAssertEqual(security { $0.size = CGSize(width: 40, height: 14) }, .notSecure, "a small but real field")
    }

    func testSecureFieldInsideUntrustedAppIsStillNotRecorded() {
        // Either answer drops the burst; the app check comes first.
        XCTAssertNotEqual(security { $0.bundleID = "com.microsoft.VSCode"; $0.subrole = "AXSecureTextField" }, .notSecure)
    }
}

// Security #5: a clicked element's on-screen content isn't quoted into captions when it could be
// secret or is long content rather than a control's name.
final class ClickValueLabelTests: XCTestCase {
    func testControlValuesAreKept() {
        XCTAssertEqual(ClickDescriber.valueLabel("Save", role: "AXButton"), "Save")
        XCTAssertEqual(ClickDescriber.valueLabel("Pricing", role: "AXLink"), "Pricing")
    }

    func testShortStaticTextIsKept() {
        XCTAssertEqual(ClickDescriber.valueLabel("General", role: "AXStaticText"), "General")
        XCTAssertEqual(ClickDescriber.valueLabel("Due 2026-10-04", role: "AXCell"), "Due 2026-10-04")
    }

    func testLongContentIsDropped() {
        let message = "Hi Sam, the board meeting moved to Thursday, can you bring the numbers?"
        XCTAssertNil(ClickDescriber.valueLabel(message, role: "AXStaticText"))
    }

    func testSecretLookingValuesAreDropped() {
        for secret in ["482913", "Code: 123456", "4111 1111 1111 1111", "ghp_a1B2c3D4e5F6g7H8i9J0", "sk-live-9f8e7d6c5b4a3f2e"] {
            XCTAssertNil(ClickDescriber.valueLabel(secret, role: "AXStaticText"), secret)
            XCTAssertNil(ClickDescriber.valueLabel(secret, role: "AXButton"), secret)
        }
    }

    func testOtherRolesNeverQuoteTheirValue() {
        XCTAssertNil(ClickDescriber.valueLabel("hello", role: "AXTextField"))
        XCTAssertNil(ClickDescriber.valueLabel("hello", role: "AXWebArea"))
    }
}
