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
                continuation.resume(returning: (Self.label(of: focused, role: Self.string(focused, kAXRoleAttribute)), isSecure))
            }
        }
    }

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private static func target(for element: AXUIElement) -> ClickTarget {
        let role = string(element, kAXRoleAttribute)
        var target = ClickTarget(role: role, subrole: string(element, kAXSubroleAttribute), label: label(of: element, role: role))
        if role == kAXMenuItemRole as String { target.menuPath = menuPath(from: element) }
        return target
    }

    /// Never a text field's value: that's whatever the user typed, possibly private.
    private static func label(of element: AXUIElement, role: String?) -> String? {
        let candidates = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute as String, kAXHelpAttribute]
        for attribute in candidates {
            if let s = string(element, attribute), !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        if let titleElement = Self.element(element, kAXTitleUIElementAttribute),
           let s = string(titleElement, kAXValueAttribute) { return s }
        if let role, !fieldRoles.contains(role), role != "AXSecureTextField", let s = string(element, kAXValueAttribute) { return s }
        return nil
    }

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
