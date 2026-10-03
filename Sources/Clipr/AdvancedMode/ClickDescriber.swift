// Sources/Clipr/AdvancedMode/ClickDescriber.swift
import ApplicationServices
import Foundation

protocol ClickDescribing: AnyObject {
    /// What's under `point` (Quartz global). `nil` if Accessibility can't say.
    func describe(at point: CGPoint) async -> ClickTarget?
    /// The focused element's label (for "Type … in **Name**") and whether it's a password field.
    func focusedField() async -> (label: String?, isSecure: Bool)
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

    func focusedField() async -> (label: String?, isSecure: Bool) {
        await withCheckedContinuation { continuation in
            queue.async { [systemWide] in
                guard let focused = Self.element(systemWide, kAXFocusedUIElementAttribute) else {
                    return continuation.resume(returning: (nil, false))
                }
                let isSecure = Self.string(focused, kAXSubroleAttribute) == "AXSecureTextField"
                continuation.resume(returning: (Self.label(of: focused, role: Self.string(focused, kAXRoleAttribute), allowValue: false), isSecure))
            }
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
