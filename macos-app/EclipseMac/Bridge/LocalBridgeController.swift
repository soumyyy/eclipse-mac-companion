import Combine
import Foundation

@MainActor
final class LocalBridgeController: ObservableObject {
    static let defaultDeviceID = "mac_soumya_local"

    @Published private(set) var pendingJob: BridgeJobEnvelope?
    @Published private(set) var latestResult: BridgeJobResultEnvelope?
    @Published private(set) var outboxCount = 0
    @Published private(set) var bridgeMessage = "Local bridge ready"

    private let processor: LocalBridgeProcessor
    private let transport: any LocalBridgeTransporting
    private let deviceID: String

    init(
        deviceID: String = LocalBridgeController.defaultDeviceID,
        setTextActions: SetTextActionController,
        collector: any ContextCollecting = AccessibilityContextCollector(),
        store: (any BridgeResultStoring)? = nil,
        transport: any LocalBridgeTransporting = LocalBridgeHTTPClient()
    ) {
        self.deviceID = deviceID
        self.transport = transport
        let bridgeStore = store ?? Self.makeDefaultStore()
        processor = LocalBridgeProcessor(
            deviceID: deviceID,
            collector: collector,
            textActions: setTextActions,
            store: bridgeStore
        )
        refreshOutboxCount()
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
        refreshOutboxCount()
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
        refreshOutboxCount()
    }

    func completePendingSetTextJob(with actionResult: SetTextActionResult?) {
        guard let pendingJob, let actionResult else { return }
        latestResult = processor.completionResult(for: pendingJob, actionResult: actionResult)
        self.pendingJob = nil
        bridgeMessage = "Queued final receipt for local bridge"
        refreshOutboxCount()
    }

    func cancelPendingJob() {
        pendingJob = nil
    }

    func markLatestResultPosted() {
        guard let latestResult else { return }
        processor.markPosted(jobID: latestResult.jobID)
        refreshOutboxCount()
    }

    func fetchNextRemoteJob() async -> BridgeJobResultEnvelope? {
        do {
            guard let job = try await transport.fetchNextJob(deviceID: deviceID) else {
                bridgeMessage = "No queued local bridge job"
                return nil
            }

            let result = processor.process(job)
            latestResult = result
            pendingJob = result.status == .pendingApproval ? job : nil
            refreshOutboxCount()

            switch result.status {
            case .pendingApproval:
                bridgeMessage = "Fetched job; waiting for approval"
            case .succeeded:
                bridgeMessage = "Fetched and completed job"
            case .failed, .rejected, .expired:
                bridgeMessage = result.error?.message ?? "Fetched job did not complete"
            }

            return result
        } catch {
            bridgeMessage = error.localizedDescription
            return nil
        }
    }

    func postOutbox() async -> Int {
        let results = processor.unpostedResults(limit: 50)
        guard !results.isEmpty else {
            bridgeMessage = "Outbox is empty"
            return 0
        }

        do {
            let response = try await transport.replayOutbox(results)
            for result in results {
                processor.markPosted(jobID: result.jobID)
            }
            refreshOutboxCount()
            let postedCount = response.accepted + response.duplicates
            bridgeMessage = "Posted \(postedCount) receipt(s) to local bridge"
            return postedCount
        } catch {
            bridgeMessage = error.localizedDescription
            refreshOutboxCount()
            return 0
        }
    }

    private func refreshOutboxCount() {
        outboxCount = processor.unpostedResults(limit: 1_000).count
    }

    private static func makeDefaultStore() -> any BridgeResultStoring {
        do {
            return try SQLiteBridgeResultStore.default()
        } catch {
            return InMemoryBridgeResultStore()
        }
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
