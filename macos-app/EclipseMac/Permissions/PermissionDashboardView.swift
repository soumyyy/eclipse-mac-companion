import SwiftUI

struct PermissionDashboardView: View {
    @ObservedObject var permissionCenter: PermissionCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Local access, under your control")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("Eclipse checks permissions on this Mac. It does not send context anywhere in Phase 1.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Recheck") {
                        permissionCenter.refresh()
                    }
                }

                SectionCard {
                    VStack(spacing: 0) {
                        ForEach(Array(SystemPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                            PermissionRow(
                                permission: permission,
                                status: permissionCenter.status(for: permission),
                                request: { permissionCenter.request(permission) },
                                openSettings: { permissionCenter.openSystemSettings(for: permission) }
                            )
                            if index < SystemPermission.allCases.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }

                Label(
                    "Secure fields, clipboard contents, and continuous screenshots remain unavailable by design.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .background(EclipseTheme.canvas.opacity(0.035))
        .navigationTitle("Permissions")
    }
}

private struct PermissionRow: View {
    let permission: SystemPermission
    let status: PermissionStatus
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: permission.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(status.isGranted ? EclipseTheme.mint : EclipseTheme.ink)
                .frame(width: 38, height: 38)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(permission.title).font(.headline)
                    Text(status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.isGranted ? EclipseTheme.mint : .secondary)
                }
                Text(permission.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if status.isGranted {
                Button("Open Settings", action: openSettings)
            } else {
                Button("Allow", action: request)
                    .buttonStyle(.borderedProminent)
                    .tint(EclipseTheme.violet)
            }
        }
        .padding(.vertical, 14)
    }
}
