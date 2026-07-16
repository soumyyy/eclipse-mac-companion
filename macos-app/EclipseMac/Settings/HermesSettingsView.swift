import SwiftUI

struct HermesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var tokenDraft = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("Hermes API") {
                TextField("Base URL", text: $settings.hermesBaseURLString)
                    .textFieldStyle(.roundedBorder)
                    .help("Examples: http://127.0.0.1:8642/v1, http://<tailscale-ip>:8642/v1, https://eclipse-api.example.com/v1")

                TextField("Conversation ID", text: $settings.conversationID)
                    .textFieldStyle(.roundedBorder)

                SecureField("API_SERVER_KEY", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        tokenDraft = settings.apiToken
                    }

                HStack {
                    Button("Save Token to Keychain") {
                        saveToken()
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
                LabeledContent("Token") {
                    Text(settings.tokenStatus)
                        .foregroundStyle(.secondary)
                }
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

    private func saveToken() {
        do {
            try settings.saveToken(tokenDraft)
            statusIsError = false
            statusMessage = "Token saved."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
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

