import Combine
import Foundation

@MainActor
final class ContextDiagnosticsModel: ObservableObject {
    @Published private(set) var renderedSnapshot = "Capture a snapshot to inspect the privacy-filtered local context."
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCapturedAt: Date?

    private let collector: any ContextCollecting

    init(collector: any ContextCollecting = AccessibilityContextCollector()) {
        self.collector = collector
    }

    func capture() {
        do {
            let snapshot = try collector.capture()
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
