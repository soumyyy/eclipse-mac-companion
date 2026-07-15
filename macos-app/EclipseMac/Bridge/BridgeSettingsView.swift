import SwiftUI

struct BridgeSettingsView: View {
    @ObservedObject var runtime: RuntimeModel
    @ObservedObject private var localBridge: LocalBridgeController

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
                LabeledContent("Device ID", value: LocalBridgeController.defaultDeviceID)
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
