import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var statuses: [SystemPermission: PermissionStatus] = [:]

    init() {
        refresh()
    }

    func status(for permission: SystemPermission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    func refresh() {
        statuses[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        statuses[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .denied
        statuses[.microphone] = microphoneStatus
    }

    func request(_ permission: SystemPermission) {
        switch permission {
        case .accessibility:
            // The imported global is not concurrency-annotated in the macOS SDK.
            // Its documented CFString value is stable and avoids crossing actors.
            let promptKey = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            openSystemSettings(for: permission)
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() {
                openSystemSettings(for: permission)
            }
            refresh()
        case .microphone:
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        }
    }

    func openSystemSettings(for permission: SystemPermission) {
        let pane: String
        switch permission {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .microphone: pane = "Privacy_Microphone"
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var microphoneStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }
}
