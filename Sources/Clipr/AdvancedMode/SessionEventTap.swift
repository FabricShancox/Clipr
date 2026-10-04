// Sources/Clipr/AdvancedMode/SessionEventTap.swift
import Cocoa
import Carbon.HIToolbox

enum SessionEvent: Equatable {
    /// `clickCount` is the system's click state: 2 for the second press of a double-click.
    /// `window` is what was under the click when it happened.
    case click(CGPoint, clickCount: Int = 1, window: ClickedWindow? = nil)
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

/// When the system disables the tap, whether and when to turn it back on, and what to log.
/// A timeout (the callback was slow) is re-armed at once, as is standard. A disable caused by user
/// input is the system's own signal, so it's logged and re-armed only after a pause instead of
/// fighting the system in a loop. Logging is rate-limited so a tap that keeps timing out can't
/// flood the log.
struct TapRearmPolicy {
    enum Action: Equatable {
        case rearmNow
        case rearmAfter(TimeInterval)
    }

    static let userInputBackoff: TimeInterval = 1
    private(set) var timeouts = 0
    private(set) var userInputDisables = 0

    mutating func handleDisable(byUserInput: Bool) -> (action: Action, log: String?) {
        if byUserInput {
            userInputDisables += 1
            let log = Self.shouldLog(userInputDisables)
                ? "Clipr: advanced mode event tap was disabled by user input (\(userInputDisables)x); re-arming in \(Self.userInputBackoff) s"
                : nil
            return (.rearmAfter(Self.userInputBackoff), log)
        }
        timeouts += 1
        let log = Self.shouldLog(timeouts)
            ? "Clipr: advanced mode event tap timed out (\(timeouts)x); re-enabled"
            : nil
        return (.rearmNow, log)
    }

    /// The first time, then every tenth.
    private static func shouldLog(_ count: Int) -> Bool { count == 1 || count % 10 == 0 }
}

/// One listen-only tap for everything a session observes. The mask only includes what enabled
/// features need — mouse-moved events in particular arrive at display refresh rate, and keyboard
/// events need Input Monitoring. The callback runs on the main thread and only decodes: the
/// window-list lookup a click needs runs on a serial queue, and every event (clicks, moves, keys)
/// goes through that queue and back to the main thread, so they still arrive in order. Slow work
/// in the callback is what makes the system disable a tap.
final class SessionEventTap: SessionEventSource {
    var onEvent: ((SessionEvent) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "Clipr.SessionEventTap")
    private var rearm = TapRearmPolicy()
    /// Bumped on every start and stop, so events still queued from an earlier tap are dropped.
    private var generation = 0

    func start(options: SessionEventOptions) throws {
        stop() // a second start must not leak the first tap
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
        rearm = TapRearmPolicy()
    }

    /// Must be called on the main thread: the tap's source lives on the main run loop.
    func stop() {
        generation += 1
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
            let (action, log) = rearm.handleDisable(byUserInput: type == .tapDisabledByUserInput)
            if let log { NSLog(log) }
            switch action {
            case .rearmNow:
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            case .rearmAfter(let delay):
                let generation = self.generation
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.generation == generation, let tap = self.tap else { return }
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        case .leftMouseDown:
            let location = event.location
            let clickCount = max(1, Int(event.getIntegerValueField(.mouseEventClickState)))
            // Resolved at click time, off the main thread: by the time a delayed capture runs,
            // the menu or panel that was clicked may be gone, or a new window may be in front.
            deliver {
                switch ClickHitTest.live(location) {
                case .own: return .ownClick
                case .other(let window): return .click(location, clickCount: clickCount, window: window)
                }
            }
        case .mouseMoved, .leftMouseDragged:
            let location = event.location
            deliver { .mouseMoved(location) }
        case .keyDown:
            guard let ns = NSEvent(cgEvent: event) else { return }
            // Password characters must never leave the tap, so blank them while secure input is on.
            let isSecure = IsSecureEventInputEnabled()
            let key = KeyInput(
                characters: isSecure ? "" : (ns.characters ?? ""),
                baseCharacters: isSecure ? "" : (ns.charactersIgnoringModifiers ?? ""),
                keyCode: ns.keyCode,
                modifiers: Self.modifiers(ns.modifierFlags),
                isSecure: isSecure
            )
            deliver { .key(key) }
        default:
            break
        }
    }

    /// `make` runs on the serial queue, then the event is handed over on the main thread. FIFO
    /// both ways, so events keep the order they happened in.
    private func deliver(_ make: @escaping () -> SessionEvent) {
        let generation = self.generation
        queue.async { [weak self] in
            let event = make()
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.onEvent?(event)
            }
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
