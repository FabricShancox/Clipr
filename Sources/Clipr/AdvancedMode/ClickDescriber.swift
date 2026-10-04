// Sources/Clipr/AdvancedMode/ClickDescriber.swift
import AppKit
import ApplicationServices

protocol ClickDescribing: AnyObject {
    /// What's under `point` (Quartz global). `nil` if Accessibility can't say.
    func describe(at point: CGPoint) async -> ClickTarget?
    /// The focused element's label (for "Type … in **Name**"), whether it's a password field,
    /// and the element itself so a burst can be checked to start and end in the same field.
    func focusedField() async -> FocusedField
}

/// Whether the focused element is a password field. `unknown` whenever Accessibility couldn't
/// say for sure (no focused element, timeout, any other read error) — typing steps treat it
/// like `secure`, so a failed read can never let a password through.
enum FieldSecurity: Equatable {
    case secure, notSecure, unknown
}

struct FocusedField {
    var label: String?
    var security: FieldSecurity
    /// `nil` when there's no focused element (security is then `unknown`), and in test fakes.
    var element: AXUIElement?
}

/// Reads the UI under a click through Accessibility. Runs on its own serial queue with a short
/// messaging timeout: a hung target app would otherwise block for AX's default ~6 s, and this
/// must never run on the main thread where the event tap lives (a blocked tap gets disabled).
final class ClickDescriber: ClickDescribing {
    private let queue = DispatchQueue(label: "Clipr.ClickDescriber")
    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    func describe(at point: CGPoint) async -> ClickTarget? {
        await withCheckedContinuation { continuation in
            queue.async { [systemWide] in
                var element: AXUIElement?
                guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
                      let element else { return continuation.resume(returning: nil) }
                continuation.resume(returning: Self.target(for: element))
            }
        }
    }

    func focusedField() async -> FocusedField {
        await withCheckedContinuation { continuation in
            queue.async { [systemWide] in
                guard let focused = Self.element(systemWide, kAXFocusedUIElementAttribute) else {
                    return continuation.resume(returning: FocusedField(label: nil, security: .unknown, element: nil))
                }
                // Terminals never mark a sudo/ssh/password prompt as an AX secure field, so the
                // subrole check below can't protect them: any field in a terminal is `unknown`.
                // The app comes from the focused element's own pid — the process that actually
                // receives the keys — rather than the frontmost app, which needs the main thread
                // and could already be a different app by the time this read runs.
                var pid: pid_t = 0
                guard AXUIElementGetPid(focused, &pid) == .success,
                      !Self.isTerminal(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) else {
                    return continuation.resume(returning: FocusedField(label: nil, security: .unknown, element: focused))
                }
                let role = Self.read(focused, kAXRoleAttribute)
                let subrole = Self.read(focused, kAXSubroleAttribute)
                let security: FieldSecurity
                if case .failed = role { security = .unknown }
                else if case .failed = subrole { security = .unknown }
                else if case .value("AXSecureTextField") = subrole { security = .secure }
                else { security = .notSecure }
                var roleString: String?
                if case .value(let r) = role { roleString = r }
                continuation.resume(returning: FocusedField(
                    label: Self.label(of: focused, role: roleString, allowValue: false), security: security, element: focused
                ))
            }
        }
    }

    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "org.alacritty", "com.mitchellh.ghostty", "com.github.wez.wezterm"
    ]

    /// An unknown app (`nil`) isn't treated as a terminal here; a failed pid lookup is already
    /// `unknown` on its own path.
    static func isTerminal(bundleID: String?) -> Bool {
        bundleID.map(terminalBundleIDs.contains) ?? false
    }

    private enum AttributeRead: Equatable {
        case value(String?)
        /// Anything but "attribute unsupported" / "no value" — a timeout, `cannotComplete`, an
        /// invalid element. The security check fails closed on these.
        case failed
    }

    private static func read(_ el: AXUIElement, _ attribute: String) -> AttributeRead {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(el, attribute as CFString, &value) {
        case .success: return .value(value as? String)
        case .attributeUnsupported, .noValue: return .value(nil)
        default: return .failed
        }
    }

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Roles whose own AXValue is display text rather than user input.
    private static let valueLabelRoles: Set<String> = ["AXStaticText", "AXCell", "AXButton", "AXMenuButton", "AXPopUpButton", "AXLink", "AXHeading"]
    private static let maxLabelLength = 200

    private static func target(for element: AXUIElement) -> ClickTarget {
        let role = string(element, kAXRoleAttribute)
        var target = ClickTarget(role: role, subrole: string(element, kAXSubroleAttribute), label: label(of: element, role: role, allowValue: true))
        if role == kAXMenuItemRole as String { target.menuPath = menuPath(from: element) }
        return target
    }

    /// AXValue is only used for an allowlist of display-text roles (anything else, e.g. text fields,
    /// web areas or unknown custom controls, may hold what the user typed), and never for the
    /// focused element, which is by definition what they are typing into. Capped so a huge
    /// static-text value can't end up in a caption.
    private static func label(of element: AXUIElement, role: String?, allowValue: Bool) -> String? {
        let candidates = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute as String, kAXHelpAttribute]
        for attribute in candidates {
            if let s = string(element, attribute), !s.trimmingCharacters(in: .whitespaces).isEmpty { return capped(s) }
        }
        if let titleElement = Self.element(element, kAXTitleUIElementAttribute) {
            let titleRole = string(titleElement, kAXRoleAttribute)
            let isField = titleRole.map(fieldRoles.contains) ?? false
            if !isField, string(titleElement, kAXSubroleAttribute) != "AXSecureTextField",
               let s = string(titleElement, kAXValueAttribute) { return capped(s) }
        }
        if allowValue, let role, valueLabelRoles.contains(role), let s = string(element, kAXValueAttribute) { return capped(s) }
        return nil
    }

    private static func capped(_ s: String) -> String { String(s.prefix(maxLabelLength)) }

    /// Menu bar item → … → clicked item, by walking up through AXMenu parents.
    private static func menuPath(from item: AXUIElement) -> [String] {
        var titles: [String] = []
        var current: AXUIElement? = item
        var depth = 0
        while let el = current, depth < 10 {
            let role = string(el, kAXRoleAttribute)
            if role == kAXMenuItemRole as String || role == kAXMenuBarItemRole as String,
               let title = string(el, kAXTitleAttribute), !title.isEmpty {
                titles.append(title)
            }
            if role == kAXMenuBarItemRole as String { break }
            current = element(el, kAXParentAttribute)
            depth += 1
        }
        return titles.reversed()
    }

    private static func string(_ el: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
