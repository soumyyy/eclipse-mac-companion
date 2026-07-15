import AppKit
import Combine
import Foundation

@MainActor
final class ContextDiagnosticsModel: ObservableObject {
    @Published private(set) var renderedSnapshot = "Capture a snapshot to inspect the privacy-filtered local context."
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCapturedAt: Date?
    @Published private(set) var screenshot: NSImage?
    @Published private(set) var screenshotMetadata: WindowCaptureMetadata?
    @Published private(set) var isCapturingWindow = false

    private let collector: any ContextCollecting
    private let windowCapturer: any WindowCapturing

    init(
        collector: any ContextCollecting = AccessibilityContextCollector(),
        windowCapturer: any WindowCapturing = ActiveWindowCapturer()
    ) {
        self.collector = collector
        self.windowCapturer = windowCapturer
    }

    func capture() {
        do {
            let snapshot = try collector.capture()
            render(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureWindow() {
        guard !isCapturingWindow else { return }
        isCapturingWindow = true
        errorMessage = nil

        Task { @MainActor in
            defer { isCapturingWindow = false }
            do {
                let snapshot = try collector.capture()
                render(snapshot)
                let result = try await windowCapturer.capture(snapshot: snapshot)
                screenshot = NSImage(cgImage: result.image, size: .zero)
                screenshotMetadata = result.metadata
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func render(_ snapshot: ContextSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(snapshot)
            renderedSnapshot = String(decoding: data, as: UTF8.self)
            errorMessage = nil
            lastCapturedAt = snapshot.capturedAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
