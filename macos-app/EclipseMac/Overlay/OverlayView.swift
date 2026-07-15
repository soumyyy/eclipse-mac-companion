import SwiftUI

struct OverlayView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject private var textActions: SetTextActionController
    @ObservedObject private var localBridge: LocalBridgeController

    init(runtime: RuntimeModel) {
        self.runtime = runtime
        textActions = runtime.setTextActions
        localBridge = runtime.localBridge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let pending = textActions.pendingAction?.presentation {
                approvalCard(pending)
            } else if let result = textActions.result {
                resultCard(result)
            } else {
                preparationCard
            }
        }
        .padding(22)
        .frame(width: 540, height: 380, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(EclipseTheme.canvas.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 14) {
            EclipseOrb(state: runtime.state, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.state.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(runtime.debugMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("⌥ Space")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approved text action", systemImage: "character.cursor.ibeam")
                .font(.headline)
            Text("Keep a normal text field focused, then prepare a one-time action. Nothing is written until you approve the exact target and text.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = textActions.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            bridgeControls

            Spacer(minLength: 0)
            Text("Demo: \"\(SetTextActionController.demoText)\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button("Fetch Job") {
                    runtime.fetchLocalBridgeJob()
                }
                Button("Post Outbox") {
                    runtime.postLocalBridgeOutbox()
                }
                Button(localBridge.isPolling ? "Stop Polling" : "Start Polling") {
                    runtime.toggleLocalBridgePolling()
                }
                Spacer()
                Button("Prepare") {
                    runtime.prepareDemoTextAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(EclipseTheme.violet)
            }
        }
        .approvalSurface()
    }

    private var bridgeControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("Bridge URL", text: $localBridge.bridgeBaseURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        runtime.saveLocalBridgeBaseURL()
                    }
                Button("Save") {
                    runtime.saveLocalBridgeBaseURL()
                }
                .controlSize(.small)
            }

            SecureField("Bearer token optional for localhost", text: $localBridge.bridgeBearerToken)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    runtime.saveLocalBridgeBaseURL()
                }

            HStack(spacing: 8) {
                Label(localBridge.bridgeStatus, systemImage: localBridge.isPolling ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
                    .foregroundStyle(localBridge.bridgeStatus.hasPrefix("Bridge unavailable") || localBridge.bridgeStatus.hasPrefix("Invalid") ? .orange : .secondary)
                    .lineLimit(1)
                Spacer()
                Text("outbox \(localBridge.outboxCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func approvalCard(_ pending: SetTextActionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Approval required", systemImage: "hand.raised.fill")
                    .font(.headline)
                Spacer()
                Text("Expires in 10 seconds")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(pending.target.applicationName)
                    .font(.subheadline.weight(.semibold))
                Text(targetDescription(pending.target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let jobID = localBridge.pendingJob?.jobID {
                    Text(jobID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(pending.proposedText)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Cancel") {
                    runtime.cancelTextAction()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Approve & Type") {
                    runtime.approveTextAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(EclipseTheme.violet)
            }
        }
        .approvalSurface()
    }

    private func resultCard(_ result: SetTextActionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Text action completed", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Eclipse wrote \(result.charactersWritten) characters after validating the original app, window, focused element, and approval age.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Text(result.actionID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if localBridge.latestResult?.status == .succeeded {
                    Text("outbox \(localBridge.outboxCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("Done") {
                    runtime.resetTextAction()
                }
            }
        }
        .approvalSurface()
    }

    private func targetDescription(_ target: SetTextTargetBinding) -> String {
        let field = target.elementLabel ?? target.elementRole
        if let title = target.windowTitle, !title.isEmpty {
            return "\(title) - \(field)"
        }
        return field
    }
}

private extension View {
    func approvalSurface() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}
