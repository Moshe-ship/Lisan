import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLoginServiceError: Error, LocalizedError {
    /// System Settings → General → Login Items needs user approval.
    case requiresApproval
    /// Signing not trusted for SMAppService. User must reinstall a properly
    /// signed copy from /Applications.
    case notTrusted
    /// Unknown service manager failure.
    case failed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Launch at login needs approval in System Settings → General → Login Items → Allow in the Background → Lisan."
        case .notTrusted:
            return "Launch at login requires a properly signed copy of Lisan installed in /Applications. Drag Lisan.app into /Applications and relaunch."
        case .failed(let underlying):
            return "Unable to update launch at login: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class LaunchAtLoginService {

    /// Turn launch-at-login on or off. When the underlying SMAppService
    /// call fails, inspect the service status to give the user an
    /// actionable error instead of the opaque "Operation not permitted".
    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            switch SMAppService.mainApp.status {
            case .requiresApproval:
                throw LaunchAtLoginServiceError.requiresApproval
            case .notFound:
                // The app isn't in a location macOS considers valid for
                // SMAppService registration (usually /Applications).
                throw LaunchAtLoginServiceError.notTrusted
            default:
                throw LaunchAtLoginServiceError.failed(underlying: error)
            }
        }
    }

    /// Convenience: opens the System Settings pane where the user grants
    /// Lisan permission to run at login. Called from the UI when the user
    /// hits the approval wall.
    func openLoginItemsSettings() {
        // macOS 13+ URL for the Login Items pane. Falls back to the
        // General pane if the specific URL is not recognized.
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.general")!
        NSWorkspace.shared.open(url)
    }

    /// Current status, exposed so the UI can show correct state on first paint.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
