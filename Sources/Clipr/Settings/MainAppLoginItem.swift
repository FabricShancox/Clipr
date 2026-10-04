import Cocoa
import Foundation
import ServiceManagement

/// The real login item, registered through `SMAppService`.
struct MainAppLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
