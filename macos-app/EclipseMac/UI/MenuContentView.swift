import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var runtime: RuntimeModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: runtime.state.symbolName)
            .accessibilityLabel("Eclipse Mac")
            .onReceive(NotificationCenter.default.publisher(for: .openEclipseSettings)) { _ in
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct MenuContentView: View {
    @ObservedObject var runtime: RuntimeModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                EclipseOrb(state: runtime.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eclipse Mac")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(runtime.debugMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(16)

            Divider().opacity(0.55)

            VStack(spacing: 7) {
                MenuActionButton(title: "Open Chat", symbol: "message.badge.waveform") {
                    openWindow(id: "eclipse-chat")
                    MenuBarController.activateAppForWindowPresentation()
                }
                MenuActionButton(title: "Show Orb", symbol: "sparkles", shortcut: "⌥ Space") {
                    NotificationCenter.default.post(name: .toggleEclipseOverlay, object: nil)
                }
                SettingsLink {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 18)
                        Text("Settings")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(9)

            Divider().opacity(0.55)

            Button("Quit Eclipse Mac") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 330)
        .background(.ultraThinMaterial)
    }
}

private struct MenuActionButton: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let toggleEclipseOverlay = Notification.Name("toggleEclipseOverlay")
    static let openEclipseSettings = Notification.Name("openEclipseSettings")
}
