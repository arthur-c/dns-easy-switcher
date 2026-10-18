import AppKit
import ServiceManagement
import SwiftUI

struct LaunchAtLoginView: View {
    @State private var status = SMAppService.mainApp.status

    var body: some View {
        Group {
            Toggle("Launch at Login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { setEnabled($0) }
            ))

            if status == .requiresApproval {
                Text("Approval required in System Settings to launch at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Login Items Settings…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else if status == .notFound {
                Text("Launch at login is unavailable for this copy of the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        // macOS also lets users change login items outside the app.
        status = SMAppService.mainApp.status
    }

    private func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            switch service.status {
            case .enabled, .requiresApproval:
                if !enabled {
                    try service.unregister()
                }
            default:
                if enabled {
                    try service.register()
                }
            }
            refreshStatus()
        } catch {
            refreshStatus()

            // A denied registration can still leave the item awaiting approval.
            // Also tolerate another process having already applied the change.
            if enabled && (status == .enabled || status == .requiresApproval) {
                return
            }
            if !enabled && status == .notRegistered {
                return
            }

            // Present after menu tracking finishes so the alert can take focus.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could Not Change Launch at Login"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                NSApplication.shared.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }
}
