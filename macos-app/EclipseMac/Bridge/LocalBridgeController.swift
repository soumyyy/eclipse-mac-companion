import Combine
import Foundation

@MainActor
final class LocalBridgeController: ObservableObject {
    static let defaultDeviceID = "mac_soumya_local"

    @Published private(set) var pendingJob: BridgeJobEnvelope?
    @Published private(set) var latestResult: BridgeJobResultEnvelope?

    private let processor: LocalBridgeProcessor
    private let deviceID: String

    init(
        deviceID: String = LocalBridgeController.defaultDeviceID,
        setTextActions: SetTextActionController,
        collector: any ContextCollecting = AccessibilityContextCollector()
    ) {
        self.deviceID = deviceID
        processor = LocalBridgeProcessor(
            deviceID: deviceID,
            collector: collector,
            textActions: setTextActions
        )
    }

    func submitMockSetTextJob(text: String) {
        let job = BridgeJobEnvelope.mock(
            deviceID: deviceID,
            kind: .uiSetText,
            risk: .reversible,
            input: .setText(text)
        )
        let result = processor.process(job)
        latestResult = result
        pendingJob = result.status == .pendingApproval ? job : nil
    }

    func submitMockActiveWindowJob() {
        let job = BridgeJobEnvelope.mock(
            deviceID: deviceID,
            kind: .contextGetActiveWindow,
            risk: .read,
            input: .empty
        )
        latestResult = processor.process(job)
        pendingJob = nil
    }

    func completePendingSetTextJob(with actionResult: SetTextActionResult?) {
        guard let pendingJob, let actionResult else { return }
        latestResult = processor.completionResult(for: pendingJob, actionResult: actionResult)
        self.pendingJob = nil
    }

    func cancelPendingJob() {
        pendingJob = nil
    }
}

private extension BridgeJobEnvelope {
    static func mock(
        deviceID: String,
        kind: BridgeJobKind,
        risk: BridgeRisk,
        input: BridgeJobInput
    ) -> BridgeJobEnvelope {
        BridgeJobEnvelope(
            jobID: "job_\(UUID().uuidString.lowercased())",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: deviceID,
            kind: kind,
            risk: risk,
            input: input,
            expiresAt: Date().addingTimeInterval(30),
            idempotencyKey: "idem_\(UUID().uuidString.lowercased())"
        )
    }
}
