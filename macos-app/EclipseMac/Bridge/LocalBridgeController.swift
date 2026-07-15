import Combine
import Foundation

@MainActor
final class LocalBridgeController: ObservableObject {
    static let defaultDeviceID = "mac_soumya_local"

    @Published private(set) var pendingJob: BridgeJobEnvelope?
    @Published private(set) var latestResult: BridgeJobResultEnvelope?
    @Published private(set) var outboxCount = 0
    @Published private(set) var bridgeMessage = "Local bridge ready"
    @Published private(set) var bridgeStatus = "Polling stopped"
    @Published private(set) var isPolling = false
    @Published private(set) var bridgeStats: BridgeStats?
    @Published private(set) var lastQueuedJob: BridgeJobEnvelope?
    @Published var bridgeBaseURLString: String
    @Published var bridgeBearerToken: String

    private let processor: LocalBridgeProcessor
    private let configurationStore: LocalBridgeConfigurationStore
    private var transport: any LocalBridgeTransporting
    private let usesInjectedTransport: Bool
    private let deviceID: String
    private var pollingTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var lastTransportRequestFailed = false
    private let normalPollingInterval: TimeInterval = 3
    private let failurePollingInterval: TimeInterval = 8

    init(
        deviceID: String = LocalBridgeController.defaultDeviceID,
        setTextActions: SetTextActionController,
        collector: any ContextCollecting = AccessibilityContextCollector(),
        store: (any BridgeResultStoring)? = nil,
        configurationStore: LocalBridgeConfigurationStore = LocalBridgeConfigurationStore(),
        transport: (any LocalBridgeTransporting)? = nil
    ) {
        self.deviceID = deviceID
        self.configurationStore = configurationStore
        let configuration = configurationStore.load()
        bridgeBaseURLString = configuration.baseURLString
        bridgeBearerToken = configuration.bearerToken
        usesInjectedTransport = transport != nil
        if let transport {
            self.transport = transport
        } else if let url = configuration.baseURL {
            self.transport = LocalBridgeHTTPClient(baseURL: url, bearerToken: configuration.normalizedBearerToken)
        } else {
            self.transport = LocalBridgeHTTPClient()
            bridgeBaseURLString = LocalBridgeConfiguration.defaultBaseURLString
            bridgeBearerToken = ""
        }
        let bridgeStore = store ?? Self.makeDefaultStore()
        processor = LocalBridgeProcessor(
            deviceID: deviceID,
            collector: collector,
            textActions: setTextActions,
            store: bridgeStore
        )
        refreshOutboxCount()
    }

    deinit {
        pollingTask?.cancel()
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

    func queueContextJob(ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .contextGetActiveWindow,
                risk: .read,
                input: .empty,
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued context job"
        )
    }

    func queueSetTextJob(text: String, ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bridgeMessage = "Enter text before queueing a text job"
            return nil
        }

        return await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .uiSetText,
                risk: .reversible,
                input: .setText(trimmed),
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued text job"
        )
    }

    func refreshRemoteStats() async -> BridgeStats? {
        if !usesInjectedTransport {
            guard saveBridgeBaseURL() else { return nil }
        }
        do {
            let stats = try await transport.fetchStats()
            bridgeStats = stats
            bridgeMessage = "Bridge stats refreshed"
            return stats
        } catch {
            lastTransportRequestFailed = true
            bridgeMessage = error.localizedDescription
            bridgeStatus = "Bridge unavailable"
            return nil
        }
    }

    @discardableResult
    func saveBridgeBaseURL() -> Bool {
        let trimmed = bridgeBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            bridgeStatus = "Invalid bridge URL"
            bridgeMessage = "Use an http:// or https:// bridge URL"
            return false
        }

        bridgeBaseURLString = trimmed
        bridgeBearerToken = bridgeBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = LocalBridgeConfiguration(
            baseURLString: trimmed,
            bearerToken: bridgeBearerToken
        )
        do {
            try configurationStore.save(configuration)
        } catch {
            bridgeStatus = "Could not save bridge token"
            bridgeMessage = error.localizedDescription
            return false
        }
        if !usesInjectedTransport {
            transport = LocalBridgeHTTPClient(baseURL: url, bearerToken: configuration.normalizedBearerToken)
        }
        consecutiveFailures = 0
        bridgeStatus = isPolling ? "Polling \(trimmed)" : "Bridge URL saved"
        bridgeMessage = "Bridge URL saved"
        return true
    }

    private func queueJob(
        _ request: BridgeCreateJobRequest,
        successMessage: String
    ) async -> BridgeJobEnvelope? {
        if !usesInjectedTransport {
            guard saveBridgeBaseURL() else { return nil }
        }
        do {
            let job = try await transport.createJob(request)
            lastQueuedJob = job
            bridgeMessage = "\(successMessage): \(job.jobID)"
            bridgeStatus = isPolling ? "Connected; polling every \(Int(normalPollingInterval))s" : "Job queued"
            bridgeStats = try? await transport.fetchStats()
            return job
        } catch {
            lastTransportRequestFailed = true
            bridgeMessage = error.localizedDescription
            bridgeStatus = "Bridge unavailable"
            return nil
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        guard saveBridgeBaseURL() else { return }
        isPolling = true
        bridgeStatus = "Polling \(bridgeBaseURLString)"
        bridgeMessage = "Local bridge polling started"
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollOnce()
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        bridgeStatus = "Polling stopped"
        bridgeMessage = "Local bridge polling stopped"
    }

    @discardableResult
    func pollOnce() async -> TimeInterval {
        lastTransportRequestFailed = false

        if pendingJob == nil {
            _ = await fetchNextRemoteJob()
        } else {
            bridgeMessage = "Waiting for approval before fetching another job"
        }

        if outboxCount > 0 {
            _ = await postOutbox()
        }

        if lastTransportRequestFailed {
            consecutiveFailures += 1
            bridgeStatus = "Bridge unavailable; retrying in \(Int(failurePollingInterval))s"
            return failurePollingInterval
        }

        consecutiveFailures = 0
        if pendingJob != nil {
            bridgeStatus = "Waiting for approval"
        } else {
            bridgeStatus = isPolling ? "Connected; polling every \(Int(normalPollingInterval))s" : "Connected"
        }
        return normalPollingInterval
    }

    func fetchNextRemoteJob() async -> BridgeJobResultEnvelope? {
        do {
            guard let job = try await transport.fetchNextJob(deviceID: deviceID) else {
                lastTransportRequestFailed = false
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
            lastTransportRequestFailed = true
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
            lastTransportRequestFailed = false
            bridgeMessage = "Posted \(postedCount) receipt(s) to local bridge"
            return postedCount
        } catch {
            lastTransportRequestFailed = true
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
