import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: RuntimeModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Eclipse Mac", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .padding(.bottom, 12)
                Label("Permissions", systemImage: "hand.raised")
                    .padding(.vertical, 6)
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                Spacer()
                Text("Phase 1A")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            PermissionDashboardView(permissionCenter: runtime.permissions)
        }
    }
}
