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
        let windows = WindowPicker.onScreenWindows()
        guard let topWindow = WindowPicker.frontmostWindow(ownedBy: frontmostApp.processIdentifier, in: windows),
              !ownWindowIDs.contains(topWindow.windowID) else { return }

        Task {
            do {
                let image = try await CaptureManager.captureWindow(topWindow)
                let index = nextStepIndex
                nextStepIndex += 1
                let url = try storage.saveStep(image, index: index, in: sessionFolder)
                stepURLs.append(url)
            } catch {
                NSLog("Clipr: advanced mode step capture failed: \(error)")
            }
        }
    }
}

enum ClickCaptureError: Error {
    case accessibilityNotGranted
}
