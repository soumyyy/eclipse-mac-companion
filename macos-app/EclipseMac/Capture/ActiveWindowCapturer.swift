import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
protocol WindowCapturing {
    func capture(snapshot: ContextSnapshot) async throws -> WindowCaptureResult
}

@MainActor
final class ActiveWindowCapturer: WindowCapturing {
    private let policy: WindowCapturePolicy
    private let maximumPixelDimension: CGFloat

    init(
        policy: WindowCapturePolicy = .default,
        maximumPixelDimension: CGFloat = 3_840
    ) {
        self.policy = policy
        self.maximumPixelDimension = maximumPixelDimension
    }

    func capture(snapshot: ContextSnapshot) async throws -> WindowCaptureResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw WindowCaptureError.screenRecordingPermissionRequired
        }

        let request = try policy.validate(snapshot: snapshot)
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )

        guard let window = content.windows.first(where: { $0.windowID == request.windowID }) else {
            throw WindowCaptureError.windowUnavailable
        }
        guard window.owningApplication?.bundleIdentifier == request.bundleID else {
            throw WindowCaptureError.applicationChanged
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let pixelSize = Self.pixelSize(
            for: window.frame.size,
            scale: CGFloat(filter.pointPixelScale),
            maximumDimension: maximumPixelDimension
        )
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw WindowCaptureError.captureFailed
        }

        return WindowCaptureResult(
            image: image,
            metadata: WindowCaptureMetadata(
                captureID: "cap_\(UUID().uuidString.lowercased())",
                snapshotID: request.snapshotID,
                windowID: request.windowID,
                capturedAt: Date(),
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        )
    }

    nonisolated static func pixelSize(
        for pointSize: CGSize,
        scale: CGFloat,
        maximumDimension: CGFloat
    ) -> (width: Int, height: Int) {
        let rawWidth = max(1, pointSize.width * max(1, scale))
        let rawHeight = max(1, pointSize.height * max(1, scale))
        let largestDimension = max(rawWidth, rawHeight)
        let downscale = min(1, maximumDimension / largestDimension)

        return (
            width: max(1, Int((rawWidth * downscale).rounded())),
            height: max(1, Int((rawHeight * downscale).rounded()))
        )
    }
}
