// Sources/Clipr/AdvancedMode/SessionEventTap.swift
import Cocoa
import Carbon.HIToolbox

enum SessionEvent: Equatable {
    case click(CGPoint)
    /// A click on Clipr itself (menu-bar icon, control panel). Never a step, but it still ends a
    /// typing burst so text typed just before pressing Stop isn't lost.
    case ownClick
    case mouseMoved(CGPoint)
    case key(KeyInput)
}

struct SessionEventOptions: Equatable {
    var mouseMoves: Bool
    var keys: Bool
}

protocol SessionEventSource: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start(options: SessionEventOptions) throws
    func stop()
}

/// One listen-only tap for everything a session observes. The mask only includes what enabled
/// features need — mouse-moved events in particular arrive at display refresh rate, and keyboard
/// events need Input Monitoring. The callback only decodes and forwards: any real work on the
/// main thread here risks the system disabling the tap for being slow.
final class SessionEventTap: SessionEventSource {
    var onEvent: ((SessionEvent) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(options: SessionEventOptions) throws {
        var mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
        if options.mouseMoves {
            mask |= 1 << CGEventType.mouseMoved.rawValue | 1 << CGEventType.leftMouseDragged.rawValue
        }
        if options.keys { mask |= 1 << CGEventType.keyDown.rawValue }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                Unmanaged<SessionEventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw ClickCaptureError.eventTapCreationFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
    }

    deinit { stop() }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Re-arm rather than silently recording nothing for the rest of the session.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            NSLog("Clipr: advanced mode event tap was disabled by the system; re-enabled")
        case .leftMouseDown:
            // Resolved at click time: by the time a delayed capture runs, the menu or panel that
            // was clicked may be gone. See `WindowPicker.ownerPIDOfWindow`.
            let isOwn = WindowPicker.ownerPIDOfWindow(at: event.location) == ProcessInfo.processInfo.processIdentifier
            onEvent?(isOwn ? .ownClick : .click(event.location))
        case .mouseMoved, .leftMouseDragged:
            onEvent?(.mouseMoved(event.location))
        case .keyDown:
            guard let ns = NSEvent(cgEvent: event) else { return }
            onEvent?(.key(KeyInput(
                characters: ns.characters ?? "",
                baseCharacters: ns.charactersIgnoringModifiers ?? "",
                keyCode: ns.keyCode,
                modifiers: Self.modifiers(ns.modifierFlags),
                isSecure: IsSecureEventInputEnabled()
            )))
        default:
            break
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }
}
