import Cocoa
import ApplicationServices

final class ClickCaptureManager {
    private let storage: StorageManager
    private let debouncer = Debouncer(delay: 0.2)
    private var eventTap: CFMachPort?
    /// Kept so `stop()` can take the tap back out of the run loop. Dropping only the `CFMachPort`
    /// reference left the source attached and the port alive, so every start/stop cycle leaked one
    /// of each for the life of the process.
    private var runLoopSource: CFRunLoopSource?
    private var sessionFolder: URL?
    private var stepURLs: [URL] = []
    private var nextStepIndex = 1

    var ownWindowIDs: Set<CGWindowID> = []
    var isActive: Bool { sessionFolder != nil }
    /// Mirrors `CaptureManager.captureCursor` / `SettingsStore.captureCursor` for the per-click
    /// window captures this manager takes — kept in sync by `AppDelegate`.
    var captureCursor = false
    /// Fired on the main actor after each successful step capture, with the running count —
    /// Advanced Mode has no on-screen overlay of its own, so this is the only way `AppDelegate`
    /// can show the user it's actually doing something (see `StatusItemController.setAdvancedModeStepCount`).
    var onStepCaptured: ((Int) -> Void)?

    init(storage: StorageManager) {
        self.storage = storage
    }

    func start() throws -> URL {
        guard PermissionsManager.hasAccessibilityPermission() else {
            PermissionsManager.requestAccessibilityPermission()
            throw ClickCaptureError.accessibilityNotGranted
        }
        let folder = try storage.createSessionFolder(date: Date())
        stepURLs = []
        nextStepIndex = 1
        // Before `sessionFolder` is set, so a failure can't leave `isActive` true with no tap
        // installed — the session would report as running while recording nothing.
        try installEventTap()
        sessionFolder = folder
        return folder
    }

    func stop() -> [URL] {
        teardownEventTap()
        sessionFolder = nil
        return stepURLs
    }

    deinit {
        teardownEventTap()
    }

    private func installEventTap() throws {
        let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ClickCaptureManager>.fromOpaque(userInfo).takeUnretainedValue()
                // The system disables a tap that takes too long to respond, which any blocking
                // main-thread work will trigger (an open panel, a modal alert, a slow capture).
                // Left unhandled the session stays "active" while silently recording nothing, so
                // re-arm instead of dropping every subsequent click on the floor.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    manager.reenableEventTap()
                    return Unmanaged.passUnretained(event)
                }
                manager.debouncer.call { manager.captureFrontmostWindow() }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { throw ClickCaptureError.eventTapCreationFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        NSLog("Clipr: advanced mode event tap was disabled by the system; re-enabled")
    }

    /// Fully unwinds `installEventTap`. Disabling the tap alone leaves the run-loop source
    /// attached and the Mach port alive.
    private func teardownEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func captureFrontmostWindow() {
        guard let sessionFolder, let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        // `ownWindowIDs` is a start-time snapshot of Clipr's own on-screen window IDs, but
        // NSMenu windows (e.g. the status-bar menu) are created on-demand only when actually
        // opened, so they're never in that snapshot. The most common way to stop an Advanced
        // Mode session is clicking the menu-bar icon and choosing "Stop Advanced Mode" - that
        // icon click itself schedules a debounced capture before the "Stop" item click
        // registers, and by then Clipr's own menu is frontmost. Guard on process identity too
        // (this subsumes `ownWindowIDs` whenever Clipr itself is frontmost, but `ownWindowIDs`
        // still matters for windows that are visible-but-not-frontmost, so keep both checks).
        guard frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let windows = WindowPicker.onScreenWindows()
        guard let topWindow = WindowPicker.frontmostWindow(ownedBy: frontmostApp.processIdentifier, in: windows),
              !ownWindowIDs.contains(topWindow.windowID) else { return }

        Task {
            do {
                let image = try await CaptureManager.captureWindow(topWindow, showsCursor: self.captureCursor)
                // Hop onto the main actor for the index-read + increment + save + append
                // sequence so two overlapping captures (e.g. two clicks whose 200ms debounce
                // gap is shorter than the ScreenCaptureKit capture + PNG encode above) can
                // never interleave their mutation of `nextStepIndex`/`stepURLs`. Without this,
                // each `Task` above could resume around the same time on different threads and
                // race on a plain `Int` and `Array`, which is a real data race (possible
                // corruption/crash), not merely a step-ordering quirk.
                await MainActor.run {
                    let index = self.nextStepIndex
                    self.nextStepIndex += 1
                    do {
                        let url = try self.storage.saveStep(image, index: index, in: sessionFolder)
                        self.stepURLs.append(url)
                        self.onStepCaptured?(self.stepURLs.count)
                    } catch {
                        NSLog("Clipr: advanced mode step capture failed: \(error)")
                    }
                }
            } catch {
                NSLog("Clipr: advanced mode step capture failed: \(error)")
            }
        }
    }
}
