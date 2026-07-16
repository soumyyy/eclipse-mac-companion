import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject var appSettings: AppSettings
    @State private var selection: SettingsDestination? = .hermes

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Eclipse Mac", systemImage: "circle.hexagongrid.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)

                List(selection: $selection) {
                    Label("Hermes", systemImage: "brain.head.profile")
                        .tag(SettingsDestination.hermes)
                    Label("Permissions", systemImage: "hand.raised")
                        .tag(SettingsDestination.permissions)
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                        .tag(SettingsDestination.diagnostics)
                    Label("Bridge", systemImage: "network")
                        .tag(SettingsDestination.bridge)
                }
                .listStyle(.sidebar)

                Spacer()
                Text("Development build")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
            .padding(16)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .permissions {
            case .hermes:
                HermesSettingsView(settings: appSettings)
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
    case hermes
    case permissions
    case diagnostics
    case bridge
}
