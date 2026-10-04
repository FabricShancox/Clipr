import CoreGraphics

/// What Accessibility said about the focused element when a typing burst was checked — read once
/// in `ClickDescriber`, decided on here, so the decision is a pure function that can be tested.
struct FocusedElementFacts: Equatable {
    /// The app that owns the element (and so receives the keys). Nil when it couldn't be found.
    var bundleID: String?
    var role: String?
    var subrole: String?
    /// Nil when the size couldn't be read.
    var size: CGSize?
    /// Web content only (`AXDOMClassList`); empty elsewhere.
    var domClassList: [String]
    /// Title/description/placeholder/help, as `ClickDescriber` reports it for the caption.
    var label: String?
    /// Any role/subrole read failed for a reason other than "unsupported" (timeout, invalid element…).
    var readFailed = false
}

/// Decides whether a typing burst's text may be recorded. Fails closed: the text is kept only for
/// a standard, visible editable field, known not secure, in an app where Accessibility's answer
/// means something. Anything else is `.unknown`, which drops the burst like `.secure` does.
///
/// Why an app list at all: terminals, IDEs with integrated terminals, and remote-desktop or VM
/// viewers take passwords (sudo, ssh, a guest's login screen) through elements that never report
/// themselves as secure, and the host's secure-input flag stays off.
enum TypingInputPolicy {
    /// Apps whose input is never trusted, matched case-insensitively. Exact IDs and prefixes live
    /// together here so this stays the one list to extend.
    static let untrustedBundleIDs: Set<String> = Set([
        // Terminals
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
        "com.mitchellh.ghostty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby", "com.termius-dmg.mac",
        "com.termius.mac", "com.panic.Prompt3", "com.raphaelamorim.rio",
        // Editors and IDEs with integrated terminals or consoles
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92" /* Cursor */, "com.exafunction.windsurf", "com.google.android.studio",
        "com.panic.Nova", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.apple.dt.Xcode", "com.sublimetext.4",
        // Screen sharing, remote desktop and virtual machines
        "com.apple.ScreenSharing", "com.apple.RemoteDesktop", "com.microsoft.rdc.macos", "com.microsoft.rdc.mac",
        "com.utmapp.UTM", "com.philandro.anydesk", "com.carriez.rustdesk", "com.realvnc.vncviewer",
    ].map { $0.lowercased() })

    /// Whole families: every app whose bundle ID starts with one of these.
    static let untrustedBundleIDPrefixes: [String] = [
        "dev.warp.",            // Warp (Stable, Preview…)
        "com.jetbrains.",       // IntelliJ, PyCharm, GoLand, WebStorm, Fleet, Toolbox…
        "com.p5sys.jump.",      // Jump Desktop
        "com.citrix.",          // Citrix Viewer / Workspace
        "com.parallels.",       // Parallels Desktop
        "com.vmware.",          // VMware Fusion, Horizon
        "org.virtualbox.",      // VirtualBox, VirtualBoxVM
        "com.teamviewer.",      // TeamViewer
        "com.nomachine.",       // NoMachine
        "com.edovia.screens",   // Screens
    ].map { $0.lowercased() }

    /// The only roles whose text is recorded. Web areas, groups and custom controls can be
    /// anything — a canvas-drawn terminal, a remote session — so they don't qualify.
    static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// A focused field narrower or shorter than this (points) is a hidden input catching keys for
    /// something drawn elsewhere — how xterm.js and similar web terminals work.
    static let minimumFieldSide: CGFloat = 8

    /// Lower-cased substrings of a DOM class or label that mark a web terminal.
    static let webTerminalMarkers = ["xterm", "terminal"]

    static func isUntrustedApp(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return untrustedBundleIDs.contains(id) || untrustedBundleIDPrefixes.contains { id.hasPrefix($0) }
    }

    static func security(of facts: FocusedElementFacts) -> FieldSecurity {
        guard !facts.readFailed, let bundleID = facts.bundleID, !isUntrustedApp(bundleID: bundleID) else { return .unknown }
        if facts.subrole == "AXSecureTextField" { return .secure }
        guard let role = facts.role, editableRoles.contains(role) else { return .unknown }
        guard let size = facts.size, size.width >= minimumFieldSide, size.height >= minimumFieldSide else { return .unknown }
        let hints = facts.domClassList + [facts.label].compactMap { $0 }
        if hints.contains(where: { hint in webTerminalMarkers.contains { hint.lowercased().contains($0) } }) { return .unknown }
        return .notSecure
    }
}
