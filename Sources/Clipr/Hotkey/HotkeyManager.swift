import Carbon.HIToolbox
import Cocoa

final class HotkeyManager {
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installEventHandler()
    }

    /// Registers a global hotkey, reporting whether the system accepted it.
    ///
    /// Returns false when the combination is already owned by macOS or another app (or by this
    /// app's other binding). The result matters: registration drops the previous binding first, so
    /// a silently-failed register used to leave the user with the old hotkey gone, no new one
    /// working, and nothing said about it. Callers should tell the user and offer another combo.
    @discardableResult
    func register(_ binding: HotkeyBinding, id: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5052), id: id) // "CLPR"
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            NSLog("Clipr: could not register hotkey \(binding.displayString) (status \(status))")
            return false
        }
        hotKeyRefs[id] = ref
        // Only after the system accepted it, so a dead binding can't leave a handler that will
        // never fire looking registered.
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs[id] = nil
        }
        handlers[id] = nil
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef, let userData = userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}
