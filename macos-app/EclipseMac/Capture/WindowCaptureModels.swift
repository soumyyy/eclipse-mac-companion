import CoreGraphics
import Foundation

struct ValidatedWindowCaptureRequest: Equatable, Sendable {
    let snapshotID: String
    let windowID: CGWindowID
    let bundleID: String
}

struct WindowCaptureMetadata: Equatable, Sendable {
    let captureID: String
    let snapshotID: String
    let windowID: CGWindowID
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
}

struct WindowCaptureResult: @unchecked Sendable {
    let image: CGImage
    let metadata: WindowCaptureMetadata
}

enum WindowCaptureError: LocalizedError, Equatable {
    case screenRecordingPermissionRequired
    case missingApplication
    case missingWindow
    case blockedContext
    case staleContext
    case windowUnavailable
    case applicationChanged
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            "Screen Recording permission is required to capture the active window."
        case .missingApplication:
            "The context snapshot does not identify an active application."
        case .missingWindow:
            "The context snapshot does not identify an active window."
        case .blockedContext:
            "The active application or window is blocked by the local privacy policy."
        case .staleContext:
            "The active-window context is stale. Capture a new snapshot before taking a screenshot."
        case .windowUnavailable:
            "The active window is no longer available for capture."
        case .applicationChanged:
            "The window owner changed after context collection, so capture was cancelled."
        case .captureFailed:
            "ScreenCaptureKit could not produce an image for the active window."
        }
    }
}
