import SwiftUI

struct BridgeSettingsView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject private var localBridge: LocalBridgeController
    @State private var textJobInput = ""
    @State private var commandInput = ""

    init(runtime: RuntimeModel) {
        self.runtime = runtime
        localBridge = runtime.localBridge
    }

    var body: some View {
        Form {
            Section("Bridge") {
                TextField("Bridge URL", text: $localBridge.bridgeBaseURLString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runtime.saveLocalBridgeBaseURL()
                    }

                SecureField("Bearer token", text: $localBridge.bridgeBearerToken)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runtime.saveLocalBridgeBaseURL()
                    }

                HStack {
                    Button("Save") {
                        runtime.saveLocalBridgeBaseURL()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(localBridge.isPolling ? "Stop Polling" : "Start Polling") {
                        runtime.toggleLocalBridgePolling()
                    }

                    Button("Poll Once") {
                        runtime.pollLocalBridgeOnce()
                    }

                    Spacer()
                }
            }

            Section("Status") {
                LabeledContent("Bridge", value: localBridge.bridgeStatus)
                LabeledContent("Outbox", value: "\(localBridge.outboxCount)")
                if let stats = localBridge.bridgeStats {
                    LabeledContent("Queued jobs", value: "\(stats.queuedJobs)")
                    LabeledContent("Remote results", value: "\(stats.results)")
                }
                if let refreshedAt = localBridge.lastActivityRefreshAt {
                    LabeledContent("Activity refreshed", value: refreshedAt.formatted(date: .omitted, time: .standard))
                }
                LabeledContent("Device ID", value: LocalBridgeController.defaultDeviceID)
                Button("Refresh Activity") {
                    Task {
                        _ = await localBridge.refreshRemoteActivity()
                    }
                }
            }

            Section("Command composer") {
                Text("Queue work for this Mac through the configured bridge. Text jobs still require Mac-side approval before anything is typed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Try: capture window, get active window, notify Title | Body, type Hello, press escape, click Continue", text: $commandInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        queueCommand()
                    }

                HStack {
                    Button("Queue Command") {
                        queueCommand()
                    }
                    .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                TextField("Text to type after approval", text: $textJobInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Active Window") {
                        Task {
                            _ = await localBridge.queueContextJob()
                        }
                    }

                    Button("Capture Window") {
                        Task {
                            _ = await localBridge.queueCaptureWindowJob()
                        }
                    }

                    Button("Press Escape") {
                        Task {
                            _ = await localBridge.queuePressKeyJob(key: "escape")
                        }
                    }

                    Button("Queue Text Job") {
                        Task {
                            if await localBridge.queueSetTextJob(text: textJobInput) != nil {
                                textJobInput = ""
                            }
                        }
                    }
                    .disabled(textJobInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                if let job = localBridge.lastQueuedJob {
                    LabeledContent("Last queued", value: job.jobID)
                    LabeledContent("Kind", value: job.kind.rawValue)
                }
            }

            Section("Activity") {
                if localBridge.remoteQueuedJobs.isEmpty {
                    Text("No queued jobs visible on the bridge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(localBridge.remoteQueuedJobs.prefix(5)), id: \.jobID) { job in
                        DisclosureGroup {
                            jobDetail(job)
                            Button("Cancel Queued Job") {
                                cancelQueuedJob(job)
                            }
                            .buttonStyle(.bordered)
                            .disabled(localBridge.pendingJob?.jobID == job.jobID)
                        } label: {
                            activityLabel(title: job.kind.rawValue, subtitle: lifecycleStatus(for: job))
                        }
                    }
                }

                if localBridge.remoteResults.isEmpty {
                    Text("No remote results yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(localBridge.remoteResults.suffix(5).reversed()), id: \.jobID) { result in
                        DisclosureGroup {
                            resultDetail(result)
                        } label: {
                            activityLabel(title: result.status.rawValue, subtitle: result.jobID)
                        }
                    }
                }
            }

            Section("VPS bridge") {
                Text("Current remote endpoint:")
                    .foregroundStyle(.secondary)
                Text("https://bridge.eclipsn.com")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("Token is stored locally in Keychain after saving. Source token lives on the VPS at ~/eclipse-mac-bridge/.bridge-token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("Bridge")
    }

    private func queueCommand() {
        Task {
            if await localBridge.queueCommandPhrase(commandInput) != nil {
                commandInput = ""
            }
        }
    }

    private func cancelQueuedJob(_ job: BridgeJobEnvelope) {
        Task {
            _ = await localBridge.cancelRemoteQueuedJob(job)
        }
    }

    private func lifecycleStatus(for job: BridgeJobEnvelope) -> String {
        if let result = localBridge.remoteResults.first(where: { $0.jobID == job.jobID }) {
            return "\(job.jobID) · \(result.status.rawValue)"
        }
        if localBridge.pendingJob?.jobID == job.jobID {
            return "\(job.jobID) · waiting approval"
        }
        return "\(job.jobID) · queued"
    }

    private func activityLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func jobDetail(_ job: BridgeJobEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Job ID", value: job.jobID)
            LabeledContent("Kind", value: job.kind.rawValue)
            LabeledContent("Risk", value: job.risk.rawValue)
            LabeledContent("Input", value: inputSummary(job.input))
            LabeledContent("Expires", value: job.expiresAt.formatted(date: .omitted, time: .standard))
            LabeledContent("Idempotency", value: job.idempotencyKey)
        }
        .font(.caption)
        .textSelection(.enabled)
    }

    private func resultDetail(_ result: BridgeJobResultEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Job ID", value: result.jobID)
            LabeledContent("Status", value: result.status.rawValue)
            LabeledContent("Completed", value: result.completedAt.formatted(date: .omitted, time: .standard))
            LabeledContent("Output", value: outputSummary(result.output))
            if let error = result.error {
                LabeledContent("Error", value: "\(error.code): \(error.message)")
            }
            LabeledContent("Idempotency", value: result.idempotencyKey)
        }
        .font(.caption)
        .textSelection(.enabled)
    }

    private func inputSummary(_ input: BridgeJobInput) -> String {
        if let text = input.text { return "text: \(text)" }
        if let title = input.title { return "notification: \(title)" }
        if let key = input.key { return "key: \(((input.modifiers ?? []) + [key]).joined(separator: "+"))" }
        if let role = input.elementRole {
            return [role, input.elementLabel].compactMap { $0 }.joined(separator: " · ")
        }
        return "{}"
    }

    private func outputSummary(_ output: BridgeJobOutput?) -> String {
        guard let output else { return "none" }
        if output.context != nil { return "context snapshot" }
        if let approval = output.approval { return "text approval: \(approval.proposedText)" }
        if let automation = output.automationApproval { return "approval: \(automation.summary)" }
        if let action = output.actionResult { return "typed \(action.charactersWritten) chars" }
        if let capture = output.capture { return "capture \(capture.pixelWidth)x\(capture.pixelHeight)" }
        if output.notification != nil { return "notification delivered" }
        if let keyPress = output.keyPress { return "pressed \(((keyPress.modifiers) + [keyPress.key]).joined(separator: "+"))" }
        if let click = output.click { return "clicked \(click.elementRole) · \(click.elementLabel)" }
        return "none"
    }
}
