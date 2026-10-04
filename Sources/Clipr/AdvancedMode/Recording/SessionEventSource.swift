import Foundation

/// Delivers a session's input events: `SessionEventTap` in the app, a fake in tests.
protocol SessionEventSource: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start(options: SessionEventOptions) throws
    func stop()
}
