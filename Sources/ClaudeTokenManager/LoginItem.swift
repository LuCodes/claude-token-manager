import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status != .enabled { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}
