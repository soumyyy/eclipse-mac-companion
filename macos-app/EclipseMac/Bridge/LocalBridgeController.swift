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
    @Published private(set) var remoteQueuedJobs: [BridgeJobEnvelope] = []
    @Published private(set) var remoteResults: [BridgeJobResultEnvelope] = []
    @Published private(set) var lastActivityRefreshAt: Date?
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

    var pendingAutomationApproval: BridgeAutomationApprovalRequest? {
        guard pendingJob != nil else { return nil }
        return latestResult?.output?.automationApproval
    }

    init(
        deviceID: String = LocalBridgeController.defaultDeviceID,
        setTextActions: SetTextActionController,
        collector: any ContextCollecting = AccessibilityContextCollector(),
        keyPressExecutor: (any KeyPressExecuting)? = nil,
        clickElementExecutor: (any ClickElementExecuting)? = nil,
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
            keyPressExecutor: keyPressExecutor ?? KeyPressActionExecutor(collector: collector),
            clickElementExecutor: clickElementExecutor ?? ClickElementActionExecutor(collector: collector),
            textActions: setTextActions,
            store: bridgeStore
        )
        refreshOutboxCount()
    }

    deinit {
        pollingTask?.cancel()
    }

    func submitMockSetTextJob(text: String) async {
        let job = BridgeJobEnvelope.mock(
            deviceID: deviceID,
            kind: .uiSetText,
            risk: .reversible,
            input: .setText(text)
        )
        let result = await processor.process(job)
        latestResult = result
        pendingJob = result.status == .pendingApproval ? job : nil
        refreshOutboxCount()
    }

    func submitMockActiveWindowJob() async {
        let job = BridgeJobEnvelope.mock(
            deviceID: deviceID,
            kind: .contextGetActiveWindow,
            risk: .read,
            input: .empty
        )
        latestResult = await processor.process(job)
        pendingJob = nil
        refreshOutboxCount()
    }

    func completePendingSetTextJob(with actionResult: SetTextActionResult?) {
        guard !expirePendingJobIfNeeded() else { return }
        guard let pendingJob, let actionResult else { return }
        latestResult = processor.completionResult(for: pendingJob, actionResult: actionResult)
        self.pendingJob = nil
        bridgeMessage = "Queued final receipt for local bridge"
        refreshOutboxCount()
    }

    func completePendingAutomationJob() {
        guard !expirePendingJobIfNeeded() else { return }
        guard let pendingJob,
              let approval = latestResult?.output?.automationApproval else { return }
        latestResult = processor.automationCompletionResult(for: pendingJob, approval: approval)
        self.pendingJob = nil
        switch latestResult?.status {
        case .succeeded:
            bridgeMessage = "Automation action completed"
        case .rejected:
            bridgeMessage = latestResult?.error?.message ?? "Automation action rejected"
        case .failed:
            bridgeMessage = latestResult?.error?.message ?? "Automation action failed"
        case .expired, .pendingApproval, .none:
            bridgeMessage = "Automation action finished"
        }
        refreshOutboxCount()
    }

    @discardableResult
    func expirePendingJobIfNeeded(now: Date = Date()) -> Bool {
        guard let pendingJob,
              let deadline = pendingApprovalDeadline(for: pendingJob, result: latestResult),
              deadline < now else {
            return false
        }

        latestResult = processor.expirationResult(
            for: pendingJob,
            message: "Approval expired before the Mac completed the job.",
            completedAt: now
        )
        self.pendingJob = nil
        bridgeMessage = "Queued expired receipt for local bridge"
        refreshOutboxCount()
        return true
    }

    func cancelPendingJob() {
        guard let pendingJob else { return }
        latestResult = processor.rejectionResult(for: pendingJob)
        self.pendingJob = nil
        bridgeMessage = "Queued cancellation receipt for local bridge"
        refreshOutboxCount()
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

    func queueCaptureWindowJob(ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .contextCaptureWindow,
                risk: .read,
                input: .empty,
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued capture job"
        )
    }

    func queueNotificationJob(title: String, body: String = "", ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            bridgeMessage = "Enter a notification title before queueing"
            return nil
        }

        return await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .notificationShow,
                risk: .reversible,
                input: .notification(
                    title: trimmedTitle,
                    body: body.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued notification job"
        )
    }

    func queuePressKeyJob(key: String, modifiers: [String] = [], ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else {
            bridgeMessage = "Enter a key before queueing"
            return nil
        }

        return await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .uiPressKey,
                risk: .reversible,
                input: .keyPress(key: normalizedKey, modifiers: modifiers),
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued key job"
        )
    }

    func queueClickElementJob(role: String = "AXButton", label: String? = nil, ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty else {
            bridgeMessage = "Enter an element role before queueing"
            return nil
        }

        return await queueJob(
            BridgeCreateJobRequest(
                deviceID: deviceID,
                kind: .uiClickElement,
                risk: .consequential,
                input: .clickElement(role: trimmedRole, label: trimmedLabel?.isEmpty == true ? nil : trimmedLabel),
                ttlSeconds: ttlSeconds,
                idempotencyKey: nil
            ),
            successMessage: "Queued click job"
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

    func queueCommandPhrase(_ phrase: String, ttlSeconds: Int = 60) async -> BridgeJobEnvelope? {
        switch LocalBridgeCommandInterpreter.interpret(phrase) {
        case .context:
            return await queueContextJob(ttlSeconds: ttlSeconds)
        case .capture:
            return await queueCaptureWindowJob(ttlSeconds: ttlSeconds)
        case .notification(let title, let body):
            return await queueNotificationJob(title: title, body: body, ttlSeconds: ttlSeconds)
        case .setText(let text):
            return await queueSetTextJob(text: text, ttlSeconds: ttlSeconds)
        case .pressKey(let key):
            return await queuePressKeyJob(key: key, ttlSeconds: ttlSeconds)
        case .click(let label):
            return await queueClickElementJob(label: label, ttlSeconds: ttlSeconds)
        case .unsupported:
            bridgeMessage = "Try: get active window, capture window, notify Title | Body, type Hello, press escape, click Continue"
            return nil
        }
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

    func refreshRemoteActivity(updateMessage: Bool = true) async -> Bool {
        if !usesInjectedTransport {
            guard saveBridgeBaseURL() else { return false }
        }
        let previousMessage = bridgeMessage
        let previousStatus = bridgeStatus
        do {
            async let stats = transport.fetchStats()
            async let queuedJobs = transport.fetchQueuedJobs()
            async let results = transport.fetchResults()

            bridgeStats = try await stats
            remoteQueuedJobs = try await queuedJobs
            remoteResults = try await results
            lastActivityRefreshAt = Date()
            if updateMessage {
                bridgeMessage = "Bridge activity refreshed"
                bridgeStatus = isPolling ? "Connected; polling every \(Int(normalPollingInterval))s" : "Connected"
            } else {
                bridgeMessage = previousMessage
                bridgeStatus = previousStatus
            }
            return true
        } catch {
            lastTransportRequestFailed = true
            bridgeMessage = error.localizedDescription
            bridgeStatus = "Bridge unavailable"
            return false
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
            _ = await refreshRemoteActivity(updateMessage: false)
            bridgeMessage = "\(successMessage): \(job.jobID)"
            bridgeStatus = isPolling ? "Connected; polling every \(Int(normalPollingInterval))s" : "Job queued"
            return job
        } catch {
            lastTransportRequestFailed = true
            bridgeMessage = error.localizedDescription
            bridgeStatus = "Bridge unavailable"
            return nil
        }
    }

    func cancelRemoteQueuedJob(
        _ job: BridgeJobEnvelope,
        message: String = "Cancelled from Eclipse Mac"
    ) async -> Bool {
        if !usesInjectedTransport {
            guard saveBridgeBaseURL() else { return false }
        }

        do {
            let response = try await transport.cancelJob(jobID: job.jobID, message: message)
            if response.cancelled {
                bridgeMessage = "Cancelled queued job: \(job.jobID)"
            } else {
                bridgeMessage = "Job already finished: \(job.jobID)"
            }
            latestResult = response.result
            _ = await refreshRemoteActivity(updateMessage: false)
            bridgeStatus = isPolling ? "Connected; polling every \(Int(normalPollingInterval))s" : "Connected"
            return response.cancelled
        } catch {
            lastTransportRequestFailed = true
            bridgeMessage = error.localizedDescription
            bridgeStatus = "Bridge unavailable"
            return false
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

        _ = expirePendingJobIfNeeded()

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
        let messageBeforeActivityRefresh = bridgeMessage
        let statusBeforeActivityRefresh = bridgeStatus
        _ = await refreshRemoteActivity(updateMessage: false)
        bridgeMessage = messageBeforeActivityRefresh
        bridgeStatus = statusBeforeActivityRefresh
        return normalPollingInterval
    }

    func fetchNextRemoteJob() async -> BridgeJobResultEnvelope? {
        do {
            guard let job = try await transport.fetchNextJob(deviceID: deviceID) else {
                lastTransportRequestFailed = false
                bridgeMessage = "No queued local bridge job"
                return nil
            }

            let result = await processor.process(job)
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

    private func pendingApprovalDeadline(
        for job: BridgeJobEnvelope,
        result: BridgeJobResultEnvelope?
    ) -> Date? {
        let approvalDeadline = result?.output?.approval?.expiresAt
        let automationDeadline = result?.output?.automationApproval?.expiresAt
        return [job.expiresAt, approvalDeadline, automationDeadline]
            .compactMap { $0 }
            .min()
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

private enum LocalBridgeCommand {
    case context
    case capture
    case notification(title: String, body: String)
    case setText(String)
    case pressKey(String)
    case click(String)
    case unsupported
}

private enum LocalBridgeCommandInterpreter {
    static func interpret(_ phrase: String) -> LocalBridgeCommand {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unsupported }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("capture") || lowercased.contains("screenshot") {
            return .capture
        }
        if lowercased.contains("active window") || lowercased.contains("current window") || lowercased == "context" {
            return .context
        }
        if let notification = parseNotification(trimmed) {
            return notification
        }
        if let text = parseValue(trimmed, prefixes: ["type ", "write ", "insert text "]) {
            return .setText(text)
        }
        if let key = parseValue(trimmed, prefixes: ["press ", "hit "]) {
            return .pressKey(normalizeKey(key))
        }
        if let label = parseValue(trimmed, prefixes: ["click ", "tap "]) {
            return .click(label)
        }
        return .unsupported
    }

    private static func parseNotification(_ phrase: String) -> LocalBridgeCommand? {
        guard let raw = parseValue(phrase, prefixes: ["notify ", "notification ", "show notification "]) else {
            return nil
        }
        let parts = raw.split(separator: "|", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let title = parts.first, !title.isEmpty else { return nil }
        let body = parts.count > 1 ? parts[1] : ""
        return .notification(title: title, body: body)
    }

    private static func parseValue(_ phrase: String, prefixes: [String]) -> String? {
        let lowercased = phrase.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            return String(phrase.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func normalizeKey(_ key: String) -> String {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "esc":
            return "escape"
        case "↩", "return":
            return "return"
        case "up", "arrow up", "up arrow":
            return "arrow_up"
        case "down", "arrow down", "down arrow":
            return "arrow_down"
        case "left", "arrow left", "left arrow":
            return "arrow_left"
        case "right", "arrow right", "right arrow":
            return "arrow_right"
        default:
            return key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
}
