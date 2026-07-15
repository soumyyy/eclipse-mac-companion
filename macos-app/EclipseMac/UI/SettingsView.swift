import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: RuntimeModel
    @State private var selection: SettingsDestination? = .permissions

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Eclipse Mac", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)

                List(selection: $selection) {
                    Label("Permissions", systemImage: "hand.raised")
                        .tag(SettingsDestination.permissions)
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                        .tag(SettingsDestination.diagnostics)
                    Label("Bridge", systemImage: "network")
                        .tag(SettingsDestination.bridge)
                }
                .listStyle(.sidebar)

                Spacer()
                Text("Phase 1B")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
            .padding(16)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .permissions {
            case .permissions:
                PermissionDashboardView(permissionCenter: runtime.permissions)
            case .diagnostics:
                ContextDiagnosticsView(model: runtime.contextDiagnostics)
            case .bridge:
                BridgeSettingsView(runtime: runtime)
            }
        }
    }
}

private enum SettingsDestination: Hashable {
    case permissions
    case diagnostics
    case bridge
}
