import Cocoa

/// Turning a click, a typing burst or a shortcut into a step: its capture target, caption and
/// the checks that can drop it.
extension ClickCaptureManager {
    func fire(_ click: PendingClick) {
        let caption: (String?) async -> String? = { [autoCaptions = settings.autoCaptions, describe = click.describe] appName in
            guard autoCaptions else { return nil }
            let target = await TaskTimeout.value(of: describe, timeout: 0.5)
            return CaptionFormatter.click(target ?? nil, appName: appName)
        }
        // The clicked window's app, not whichever app is frontmost when the capture runs: a click
        // on a non-activating panel or another app's palette doesn't change the frontmost app.
        let appName = click.window?.isCapturable == true ? click.window?.appName : nil
        enqueue(kind: .click, target: scopeTarget(for: click.point, window: click.window), click: click.point,
                appName: appName, trail: click.trail,
                slot: click.slot, caption: caption)
    }

    func emit(_ typed: TypingEvent, fields: TypingBurstTracker.FieldReads) {
        switch typed {
        case .shortcut(let keys):
            enqueue(kind: .typing, target: typingTarget(near: lastClickPoint), click: nil, trail: [],
                    caption: { _ in CaptionFormatter.shortcut(keys) })
        case .text(let text):
            let start = fields.start, last = fields.last
            // The aggregator never emits an empty burst; checked here too because an empty
            // typing step would be a screenshot captioned `Type ""`.
            guard !text.isEmpty else { return }
            // The focused-field check is the second line of defence after `IsSecureEventInputEnabled`
            // (some password fields don't turn secure input on). It fails closed: the field read
            // at the burst's first key and at its last key must be the same element, known not
            // secure both times, or the step is dropped before anything is captured. Focus can
            // move mid-burst without a click or Tab, so one read could vouch for one field while
            // the text went into a password field.
            // Screen scope: the display the field is on, read with the burst's first key.
            let fallback = typingTarget(near: lastClickPoint)
            enqueue(kind: .typing, target: fallback, resolveTarget: {
                guard case .screenContaining = fallback, let frame = await start?.value.frame else { return fallback }
                return .screenContaining(CGPoint(x: frame.midX, y: frame.midY))
            }, click: nil, trail: [], skipIf: {
                guard let start, let last else { return true }
                return !Self.isSameNonSecureField(await start.value, await last.value)
            }, caption: { _ in
                CaptionFormatter.typing(text, fieldLabel: await start?.value.label)
            })
        }
    }

    /// Both reads known not secure, and of the same element. Fakes have no element, so two `nil`s
    /// count as the same field — but only when both reads are `notSecure` anyway.
    private static func isSameNonSecureField(_ a: FocusedField, _ b: FocusedField) -> Bool {
        guard a.security == .notSecure, b.security == .notSecure else { return false }
        switch (a.element, b.element) {
        case (nil, nil): return true
        case let (x?, y?): return CFEqual(x, y)
        default: return false
        }
    }

    /// Typing has no click point. In Screen scope the display where the user last clicked is a
    /// better guess than wherever the pointer has drifted to since.
    func typingTarget(near point: CGPoint?) -> CaptureTarget {
        scopeTarget(for: settings.scope == .screen ? point : nil)
    }

    func scopeTarget(for click: CGPoint?, window: ClickedWindow? = nil) -> CaptureTarget {
        .forScope(settings.scope, click: click, window: window, area: area)
    }
}
