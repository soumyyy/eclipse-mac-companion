import SwiftUI

struct HermesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("Hermes API - fixed for this app") {
                LabeledContent("Base URL") {
                    Text(settings.hermesBaseURLString)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Conversation") {
                    Text(settings.trimmedConversationID)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Token") {
                    Text(settings.apiToken.isEmpty ? "Missing from Keychain" : "Loaded from Keychain")
                        .foregroundStyle(settings.apiToken.isEmpty ? .red : .green)
                }
                HStack {
                    Button("Reload token") {
                        settings.reloadTokenFromKeychain()
                        statusIsError = settings.apiToken.isEmpty
                        statusMessage = settings.tokenStatus
                    }
                    Button("Test connection") {
                        testConnection()
                    }
                    .disabled(isTesting)
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Status") {
                LabeledContent("Session header") {
                    Text("X-Hermes-Session-Key: \(settings.trimmedConversationID)")
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Responses endpoint") {
                    Text((settings.hermesBaseURL?.appendingPathComponent("responses").absoluteString) ?? "Invalid Base URL")
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .textSelection(.enabled)
                }
            }

            Section("Contract") {
                Text("Eclipse calls Hermes only. It does not call OpenAI directly, does not own agent logic, and relies on Hermes conversation storage for memory.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("Hermes")
    }

    private func testConnection() {
        isTesting = true
        statusMessage = nil
        Task {
            do {
                let client = try settings.makeHermesClient()
                _ = try await client.healthCheck()
                statusIsError = false
                statusMessage = "Hermes health check succeeded."
            } catch {
                statusIsError = true
                statusMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}
