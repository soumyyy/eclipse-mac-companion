import Foundation

enum SystemPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case screenRecording
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.inset.filled.and.person.filled"
        case .microphone: "mic"
        }
    }

    var reason: String {
        switch self {
        case .accessibility:
            "Reads the active app, focused window, and selected interface elements. Secure fields are always excluded."
        case .screenRecording:
            "Captures one active window only when explicitly requested. Continuous display recording is not used."
        case .microphone:
            "Reserved for a later push-to-talk phase. Eclipse never listens in the background."
        }
    }
}

enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
    case unknown

    var title: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .unknown: "Unknown"
        }
    }

    var isGranted: Bool { self == .granted }
}
