import Cocoa
import ApplicationServices

final class ClickCaptureManager {
    private let storage: StorageManager
    private let debouncer = Debouncer(delay: 0.2)
    private var eventTap: CFMachPort?
    private var sessionFolder: URL?
    private var stepURLs: [URL] = []
    private var nextStepIndex = 1

    var ownWindowIDs: Set<CGWindowID> = []
    var isActive: Bool { sessionFolder != nil }

    init(storage: StorageManager) {
        self.storage = storage
    }

    func start() throws -> URL {
        guard PermissionsManager.hasAccessibilityPermission() else {
            PermissionsManager.requestAccessibilityPermission()
            throw ClickCaptureError.accessibilityNotGranted
        }
        let folder = try storage.createSessionFolder(date: Date())
        sessionFolder = folder
        stepURLs = []
        nextStepIndex = 1
        installEventTap()
        return folder
    }

    func stop() -> [URL] {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        sessionFolder = nil
        return stepURLs
    }

    private func installEventTap() {
        let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ClickCaptureManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.debouncer.call { manager.captureFrontmostWindow() }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else { return }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
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
                let image = try await CaptureManager.captureWindow(topWindow)
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

enum ClickCaptureError: Error {
    case accessibilityNotGranted
}
