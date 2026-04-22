//
//  PermissionsSettingsView.swift
//  Docky
//

import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject private var service = PermissionsService.shared

    var body: some View {
        Form {
            permissionSection(for: .userFolders)
            permissionSection(for: .finderAutomation)
            permissionSection(for: .accessibility)
            permissionSection(for: .screenCapture)

            Section {
                Button("Re-check Permissions") {
                    service.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func permissionSection(for permission: Permission) -> some View {
        Section(permission.title) {
            LabeledContent("Status") {
                Text(statusText(for: permission))
                    .foregroundStyle(statusColor(for: permission))
            }

            if let grantMethod = grantMethodText(for: permission) {
                LabeledContent("Access Via") {
                    Text(grantMethod)
                }
            }

            Text(permission.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    service.openSystemSettings(for: permission)
                }

                if permission == .finderAutomation || permission == .accessibility || permission == .screenCapture {
                    requestButton(for: permission)
                }

                if permission == .finderAutomation, service.finderAutomation != .notDetermined {
                    Button("Forget Status") {
                        service.clearAutomationStatus(for: permission)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func requestButton(for permission: Permission) -> some View {
        if permission == .finderAutomation || permission == .accessibility || permission == .screenCapture {
            Button(buttonTitle(for: permission)) {
                Task {
                    _ = await service.requestPermission(for: permission)
                }
            }
        }
    }

    private func statusText(for permission: Permission) -> String {
        switch service.status(for: permission) {
        case .granted: return "Granted"
        case .denied: return "Missing"
        case .notDetermined: return "Not Determined"
        }
    }

    private func statusColor(for permission: Permission) -> Color {
        switch service.status(for: permission) {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private func grantMethodText(for permission: Permission) -> String? {
        switch grantMethod(for: permission) {
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .screenCapture: return "Screen Recording"
        case .none: return nil
        }
    }

    private func grantMethod(for permission: Permission) -> GrantMethod? {
        switch permission {
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        case .accessibility:
            return service.accessibilityGrantMethod
        case .screenCapture:
            return service.screenCaptureGrantMethod
        }
    }

    private func buttonTitle(for permission: Permission) -> String {
        switch permission {
        case .userFolders: return "Open System Settings"
        case .finderAutomation: return "Request Finder Access"
        case .accessibility: return "Request Accessibility Access"
        case .screenCapture: return "Request Screen Recording Access"
        }
    }
}
