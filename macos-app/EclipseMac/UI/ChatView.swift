import AppKit
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = [
        ChatMessage(
            role: .system,
            text: "Connected to Hermes Agent. Configure your Base URL and API token in Settings, then send a message."
        )
    ]
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func send() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isSending else { return }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: input))
        isSending = true

        Task {
            do {
                let client = try settings.makeHermesClient()
                let response = try await client.sendMessage(input: input)
                messages.append(ChatMessage(role: .assistant, text: response))
            } catch {
                let message = error.localizedDescription
                errorMessage = message
                messages.append(ChatMessage(role: .error, text: message))
            }
            isSending = false
        }
    }
}

struct ChatView: View {
    @StateObject private var model: ChatViewModel
    @ObservedObject private var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    init(settings: AppSettings) {
        _model = StateObject(wrappedValue: ChatViewModel(settings: settings))
        self.settings = settings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            composer
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            EclipseOrb(state: model.isSending ? .thinking : .idle)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Eclipse")
                    .font(.title3.weight(.semibold))
                Text(settings.trimmedConversationID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if model.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Hermes is thinking…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                        .id("thinking")
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isSending) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Hermes…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit { model.send() }
                Button {
                    model.send()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.thinMaterial)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            if model.isSending {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 64) }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.body)
            }
            .padding(12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
            if message.role != .user { Spacer(minLength: 64) }
        }
    }

    private var title: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Hermes"
        case .error: "Error"
        case .system: "Eclipse"
        }
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .assistant:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        case .error:
            return AnyShapeStyle(Color.red.opacity(0.14))
        case .system:
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }
    }
}
