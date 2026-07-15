import SwiftUI

struct BridgeSettingsView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject private var localBridge: LocalBridgeController
    @State private var textJobInput = ""

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
                LabeledContent("Device ID", value: LocalBridgeController.defaultDeviceID)
                Button("Refresh Stats") {
                    Task {
                        _ = await localBridge.refreshRemoteStats()
                    }
                }
            }

            Section("Command composer") {
                Text("Queue work for this Mac through the configured bridge. Text jobs still require Mac-side approval before anything is typed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Queue Active Window Context") {
                    Task {
                        _ = await localBridge.queueContextJob()
                    }
                }

                TextField("Text to type after approval", text: $textJobInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
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
}
