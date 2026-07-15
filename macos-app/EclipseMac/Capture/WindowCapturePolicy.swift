import CoreGraphics
import Foundation

struct WindowCapturePolicy: Sendable {
    let maximumSnapshotAge: TimeInterval

    static let `default` = WindowCapturePolicy(maximumSnapshotAge: 10)

    func validate(
        snapshot: ContextSnapshot,
        now: Date = Date()
    ) throws -> ValidatedWindowCaptureRequest {
        guard let application = snapshot.activeApp else {
            throw WindowCaptureError.missingApplication
        }
        guard let windowID = snapshot.window?.id else {
            throw WindowCaptureError.missingWindow
        }
        guard !snapshot.redactions.contains(.blockedApplication),
              !snapshot.redactions.contains(.blockedWindow) else {
            throw WindowCaptureError.blockedContext
        }

        let age = now.timeIntervalSince(snapshot.capturedAt)
        guard age >= 0, age <= maximumSnapshotAge else {
            throw WindowCaptureError.staleContext
        }

        return ValidatedWindowCaptureRequest(
            snapshotID: snapshot.snapshotID,
            windowID: CGWindowID(windowID),
            bundleID: application.bundleID
        )
    }
}
