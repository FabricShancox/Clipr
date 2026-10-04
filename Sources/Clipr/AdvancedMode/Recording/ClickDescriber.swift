import AppKit
@preconcurrency import ApplicationServices

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
                // The app comes from the focused element's own pid — the process that actually
                // receives the keys — rather than the frontmost app, which needs the main thread
                // and could already be a different app by the time this read runs.
                var pid: pid_t = 0
                let bundleID = AXUIElementGetPid(focused, &pid) == .success
                    ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
                let role = Self.read(focused, kAXRoleAttribute)
                let subrole = Self.read(focused, kAXSubroleAttribute)
                var roleString: String?, subroleString: String?
                if case .value(let r) = role { roleString = r }
                if case .value(let r) = subrole { subroleString = r }
                let label = Self.label(of: focused, role: roleString, allowValue: false)
                let size = Self.size(of: focused)
                let facts = FocusedElementFacts(
                    bundleID: bundleID, role: roleString, subrole: subroleString, size: size,
                    domClassList: Self.strings(focused, "AXDOMClassList"), label: label,
                    readFailed: role == .failed || subrole == .failed
                )
                let security = TypingInputPolicy.security(of: facts)
                continuation.resume(returning: FocusedField(
                    label: security == .notSecure ? label : nil, security: security, element: focused,
                    frame: Self.position(of: focused).flatMap { origin in size.map { CGRect(origin: origin, size: $0) } }
                ))
            }
        }
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
    /// Controls whose own AXValue is their visible name.
    private static let controlValueRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXLink"]
    /// Roles whose AXValue is on-screen *content* — a message body, a spreadsheet cell, a revealed
    /// password or recovery code. Used only when short, and never when it looks like a secret.
    private static let contentValueRoles: Set<String> = ["AXStaticText", "AXCell", "AXHeading"]
    static let maxContentValueLength = 40
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
        if allowValue, let role, let s = string(element, kAXValueAttribute) { return valueLabel(s, role: role) }
        return nil
    }

    /// A clicked element's AXValue as its caption label, or nil when it shouldn't be quoted:
    /// any role outside the allowlists (it may hold what the user typed), content longer than
    /// `maxContentValueLength`, or anything that looks like a code, key or account number.
    static func valueLabel(_ value: String, role: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksSecret(trimmed) else { return nil }
        if controlValueRoles.contains(role) { return capped(trimmed) }
        if contentValueRoles.contains(role), trimmed.count <= maxContentValueLength { return trimmed }
        return nil
    }

    /// One-time codes and account numbers (6+ digits in a row, or 12+ in spaced/dashed groups),
    /// and key- or token-like words (16+ characters mixing letters and digits).
    static func looksSecret(_ text: String) -> Bool {
        if text.range(of: #"\d{6,}"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?:\d[ -]?){12,}"#, options: .regularExpression) != nil { return true }
        return text.split(whereSeparator: \.isWhitespace).contains { word in
            word.count >= 16 && word.contains(where: \.isLetter) && word.contains(where: \.isNumber)
        }
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

    /// Nil when there's no readable size — the policy treats that as unknown.
    private static func size(of el: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func position(of el: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func strings(_ el: AXUIElement, _ attribute: String) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return [] }
        return (value as? [String]) ?? []
    }

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
