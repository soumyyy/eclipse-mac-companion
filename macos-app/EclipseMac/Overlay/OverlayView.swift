import SwiftUI

struct OverlayView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject private var textActions: SetTextActionController
    @ObservedObject private var localBridge: LocalBridgeController
    @ObservedObject private var speech: SpeechTranscriptionController
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(runtime: RuntimeModel) {
        self.runtime = runtime
        textActions = runtime.setTextActions
        localBridge = runtime.localBridge
        speech = runtime.speech
    }

    var body: some View {
        if overlayPresentation == .buddy {
            buddyDot
        } else {
            VStack(alignment: .leading, spacing: 16) {
                header

                if overlayPresentation == .approval {
                    if let pending = textActions.pendingAction?.presentation {
                        approvalCard(pending)
                    } else if let automationApproval = localBridge.pendingAutomationApproval {
                        automationApprovalCard(automationApproval)
                    } else if let result = textActions.result {
                        resultCard(result)
                    }
                } else if overlayPresentation == .companion {
                    companionCard
                }
            }
            .padding(overlayPresentation == .approval ? 22 : 16)
            .frame(width: overlaySize.width, height: overlaySize.height, alignment: .topLeading)
            .background(.ultraThinMaterial)
            .background(EclipseTheme.canvas.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .onReceive(timer) { value in
                now = value
            }
            .padding(8)
        }
    }

    private var overlayPresentation: CompanionOverlayPresentation {
        runtime.overlayPresentation
    }

    private var overlaySize: CGSize {
        switch overlayPresentation {
        case .buddy:
            CGSize(width: 28, height: 28)
        case .companion:
            CGSize(width: 430, height: 246)
        case .approval:
            CGSize(width: 540, height: 380)
        }
    }

    private var buddyDot: some View {
        Text("AI")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.78))
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .frame(width: overlaySize.width, height: overlaySize.height)
            .accessibilityLabel("Eclipse companion active")
    }

    private var header: some View {
        HStack(spacing: 14) {
            EclipseOrb(state: runtime.state, size: overlayPresentation == .approval ? 46 : 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.state.title)
                    .font(.system(size: overlayPresentation == .approval ? 17 : 15, weight: .semibold, design: .rounded))
                Text(runtime.debugMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if overlayPresentation == .companion {
                Button {
                    runtime.collapseCompanion()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Collapse to buddy")
            }
            Text("⌥ Space")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(localBridge.isPolling ? "Hermes bridge active" : "Hermes bridge paused", systemImage: localBridge.isPolling ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(localBridge.bridgeStatus.hasPrefix("Bridge unavailable") || localBridge.bridgeStatus.hasPrefix("Invalid") ? .orange : .secondary)
                    .lineLimit(1)
                Spacer()
                Text("eyes + hands")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            TextField("Ask Hermes about this screen…", text: $runtime.companionPrompt)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    runtime.prepareCompanionAskForHermes()
                }
                .onChange(of: speech.transcript) { _, transcript in
                    guard speech.isListening else { return }
                    runtime.companionPrompt = transcript
                }

            Text(runtime.companionContextSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let response = runtime.companionResponseText {
                Text(response)
                    .font(.callout)
                    .foregroundStyle(EclipseTheme.ink)
                    .lineLimit(3)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            if let speechError = speech.errorMessage {
                Label(speechError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button {
                    runtime.toggleCompanionVoiceInput()
                } label: {
                    Label(speech.isListening ? "Stop" : "Voice", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isListening ? EclipseTheme.coral : EclipseTheme.blue)

                Button("Ask Hermes") {
                    runtime.prepareCompanionAskForHermes()
                }
                .buttonStyle(.bordered)
                .tint(EclipseTheme.violet)
                .disabled(runtime.companionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(localBridge.isPolling ? "Pause Bridge" : "Start Bridge") {
                    runtime.toggleLocalBridgePolling()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Settings") {
                    runtime.openSettings()
                }
                .buttonStyle(.borderless)
            }
        }
        .approvalSurface()
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bridge worker", systemImage: "network")
                .font(.headline)
            Text("Eclipse is connected to the configured bridge and will only run local actions after the existing policy and approval checks pass.")
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
            HStack(spacing: 8) {
                Button(localBridge.isPolling ? "Stop Polling" : "Start Polling") {
                    runtime.toggleLocalBridgePolling()
                }
                .buttonStyle(.borderedProminent)
                .tint(localBridge.isPolling ? .gray : EclipseTheme.violet)

                Button("Bridge Settings") {
                    runtime.openSettings()
                }
                Spacer()
            }
        }
        .approvalSurface()
    }

    private var bridgeControls: some View {
        VStack(alignment: .leading, spacing: 7) {
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
            Text(localBridge.bridgeBaseURLString)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func approvalCard(_ pending: SetTextActionPresentation) -> some View {
        let expiresAt = pending.createdAt.addingTimeInterval(SetTextActionPolicy.default.maximumApprovalAge)
        let expired = approvalExpired(expiresAt)
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Approval required", systemImage: "hand.raised.fill")
                    .font(.headline)
                Spacer()
                Text(expiryLabel(expiresAt))
                    .font(.caption)
                    .foregroundStyle(expired ? .red : .orange)
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
                Label("Approval is bound to this app, window, focused field, and a short freshness window.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .disabled(expired)
            }
        }
        .approvalSurface()
    }

    private func automationApprovalCard(_ pending: BridgeAutomationApprovalRequest) -> some View {
        let expired = approvalExpired(pending.expiresAt)
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Approval required", systemImage: "hand.raised.fill")
                    .font(.headline)
                Spacer()
                Text("\(pending.risk.rawValue) · \(expiryLabel(pending.expiresAt))")
                    .font(.caption)
                    .foregroundStyle(expired || pending.risk == .consequential ? .orange : .secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(pending.targetApp?.name ?? "Current app")
                    .font(.subheadline.weight(.semibold))
                Text(automationTargetDescription(pending))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let jobID = localBridge.pendingJob?.jobID {
                    Text(jobID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(pending.summary)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

                if pending.kind == .uiClickElement {
                    Label("Click execution requires an exact role and label match. Risky labels such as Send, Delete, Pay, and Submit are blocked locally.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Label("Approval is target-bound. If the app, window, or element changes, the action is rejected locally.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    runtime.cancelAutomationAction()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if pending.kind == .uiPressKey || pending.kind == .uiClickElement {
                    Button(pending.kind == .uiPressKey ? "Approve & Press Key" : "Approve & Click") {
                        runtime.approveAutomationAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EclipseTheme.violet)
                    .disabled(expired)
                }
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

    private func automationTargetDescription(_ pending: BridgeAutomationApprovalRequest) -> String {
        let windowTitle = pending.targetWindow?.title ?? "active window"
        if let windowID = pending.targetWindow?.id {
            return "\(windowTitle) · window \(windowID)"
        }
        return windowTitle
    }

    private func approvalExpired(_ expiresAt: Date) -> Bool {
        expiresAt <= now
    }

    private func expiryLabel(_ expiresAt: Date) -> String {
        let seconds = Int(ceil(expiresAt.timeIntervalSince(now)))
        if seconds <= 0 {
            return "Expired"
        }
        return "Expires in \(seconds)s"
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
