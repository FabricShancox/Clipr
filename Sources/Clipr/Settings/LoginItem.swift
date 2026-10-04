import Cocoa
import Foundation
import ServiceManagement

/// The app's login item — a seam so tests never register the test runner to open at login.
protocol LoginItem {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}
