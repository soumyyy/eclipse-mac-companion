import SwiftUI

struct ContextDiagnosticsView: View {
    @ObservedObject var model: ContextDiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Active window context")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Captured locally through Accessibility, then filtered before display.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Capture Snapshot") {
                    model.capture()
                }
                .buttonStyle(.borderedProminent)
                .tint(EclipseTheme.violet)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(EclipseTheme.amber)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EclipseTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Sanitized JSON", systemImage: "curlybraces")
                            .font(.headline)
                        Spacer()
                        if let lastCapturedAt = model.lastCapturedAt {
                            Text(lastCapturedAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                    ScrollView([.horizontal, .vertical]) {
                        Text(model.renderedSnapshot)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Label(
                "Secure fields are never read. Password managers are blocked before window or element inspection.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(EclipseTheme.canvas.opacity(0.035))
        .navigationTitle("Diagnostics")
    }
}
