import XCTest
@testable import EclipseMac

@MainActor
final class LocalBridgeControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testFetchNextRemoteContextJobProcessesAndQueuesOutboxResult() async {
        let transport = FakeLocalBridgeTransport(nextJob: job(kind: .contextGetActiveWindow, risk: .read, input: .empty))
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let result = await controller.fetchNextRemoteJob()

        XCTAssertEqual(result?.status, .succeeded)
        XCTAssertEqual(controller.latestResult?.output?.context?.snapshotID, "ctx_test")
        XCTAssertEqual(controller.outboxCount, 1)
        XCTAssertEqual(controller.bridgeMessage, "Fetched and completed job")
    }

    func testPostOutboxReplaysReceiptsAndMarksThemPosted() async {
        let transport = FakeLocalBridgeTransport(nextJob: job(kind: .contextGetActiveWindow, risk: .read, input: .empty))
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )
        _ = await controller.fetchNextRemoteJob()

        let posted = await controller.postOutbox()

        XCTAssertEqual(posted, 1)
        XCTAssertEqual(controller.outboxCount, 0)
        XCTAssertEqual(transport.replayedResults.count, 1)
    }

    func testSaveBridgeBaseURLPersistsValidHTTPURL() {
        let defaults = makeDefaults()
        let tokenStore = InMemoryBridgeTokenStore()
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            configurationStore: LocalBridgeConfigurationStore(defaults: defaults, tokenStore: tokenStore),
            transport: FakeLocalBridgeTransport(nextJob: nil)
        )
        controller.bridgeBaseURLString = " https://bridge.example.test "
        controller.bridgeBearerToken = " dev-token "

        XCTAssertTrue(controller.saveBridgeBaseURL())
        XCTAssertEqual(controller.bridgeBaseURLString, "https://bridge.example.test")
        XCTAssertEqual(controller.bridgeBearerToken, "dev-token")
        XCTAssertEqual(defaults.string(forKey: "localBridge.baseURL"), "https://bridge.example.test")
        XCTAssertNil(defaults.string(forKey: "localBridge.bearerToken"))
        XCTAssertEqual(tokenStore.loadToken(), "dev-token")
        XCTAssertEqual(controller.bridgeStatus, "Bridge URL saved")
    }

    func testConfigurationStoreMigratesLegacyUserDefaultsTokenToTokenStore() {
        let defaults = makeDefaults()
        defaults.set("legacy-token", forKey: "localBridge.bearerToken")
        let tokenStore = InMemoryBridgeTokenStore()
        let store = LocalBridgeConfigurationStore(defaults: defaults, tokenStore: tokenStore)

        let configuration = store.load()

        XCTAssertEqual(configuration.bearerToken, "legacy-token")
        XCTAssertEqual(tokenStore.loadToken(), "legacy-token")
        XCTAssertNil(defaults.string(forKey: "localBridge.bearerToken"))
    }

    func testSaveBridgeBaseURLRejectsInvalidURL() {
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: FakeLocalBridgeTransport(nextJob: nil)
        )
        controller.bridgeBaseURLString = "not a url"

        XCTAssertFalse(controller.saveBridgeBaseURL())
        XCTAssertEqual(controller.bridgeStatus, "Invalid bridge URL")
    }

    func testPollOnceFetchesJobThenPostsOutboxReceipt() async {
        let transport = FakeLocalBridgeTransport(nextJob: job(kind: .contextGetActiveWindow, risk: .read, input: .empty))
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let nextDelay = await controller.pollOnce()

        XCTAssertEqual(nextDelay, 3)
        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(transport.replayedResults.count, 1)
        XCTAssertEqual(controller.outboxCount, 0)
        XCTAssertEqual(controller.bridgeStatus, "Connected")
    }

    func testPollOnceBacksOffWhenBridgeFetchFails() async {
        let transport = FakeLocalBridgeTransport(nextJob: nil, fetchError: URLError(.cannotConnectToHost))
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let nextDelay = await controller.pollOnce()

        XCTAssertEqual(nextDelay, 8)
        XCTAssertEqual(controller.bridgeStatus, "Bridge unavailable; retrying in 8s")
    }

    func testQueueContextJobCreatesRemoteReadJobAndRefreshesStats() async {
        let transport = FakeLocalBridgeTransport(nextJob: nil)
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let job = await controller.queueContextJob()

        XCTAssertEqual(job?.kind, .contextGetActiveWindow)
        XCTAssertEqual(job?.risk, .read)
        XCTAssertEqual(transport.createdRequests.first?.deviceID, "mac_test")
        XCTAssertEqual(transport.createdRequests.first?.kind, .contextGetActiveWindow)
        XCTAssertEqual(controller.lastQueuedJob?.jobID, job?.jobID)
        XCTAssertEqual(controller.bridgeStats, BridgeStats(queuedJobs: 1, results: 2))
    }

    func testQueueSetTextJobCreatesRemoteReversibleJob() async {
        let transport = FakeLocalBridgeTransport(nextJob: nil)
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let job = await controller.queueSetTextJob(text: " Hello from composer ")

        XCTAssertEqual(job?.kind, .uiSetText)
        XCTAssertEqual(job?.risk, .reversible)
        XCTAssertEqual(transport.createdRequests.first?.input.text, "Hello from composer")
        XCTAssertEqual(controller.bridgeStatus, "Job queued")
    }

    func testQueueSetTextJobRejectsEmptyTextBeforeNetwork() async {
        let transport = FakeLocalBridgeTransport(nextJob: nil)
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let job = await controller.queueSetTextJob(text: "   ")

        XCTAssertNil(job)
        XCTAssertTrue(transport.createdRequests.isEmpty)
        XCTAssertEqual(controller.bridgeMessage, "Enter text before queueing a text job")
    }

    func testRefreshRemoteActivityLoadsStatsQueuedJobsAndResults() async {
        let transport = FakeLocalBridgeTransport(nextJob: nil)
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )
        _ = await controller.queueContextJob()

        let refreshed = await controller.refreshRemoteActivity()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(controller.bridgeStats, BridgeStats(queuedJobs: 1, results: 2))
        XCTAssertEqual(controller.remoteQueuedJobs.map(\.jobID), ["job_created_1"])
        XCTAssertEqual(controller.remoteResults.map(\.jobID), ["job_result_1", "job_result_2"])
        XCTAssertEqual(controller.bridgeMessage, "Bridge activity refreshed")
    }

    func testFetchPressKeyJobExposesAutomationApproval() async {
        let transport = FakeLocalBridgeTransport(
            nextJob: job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        )
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            keyPressExecutor: FakeControllerKeyPressExecutor(),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )

        let result = await controller.fetchNextRemoteJob()

        XCTAssertEqual(result?.status, .pendingApproval)
        XCTAssertEqual(controller.pendingAutomationApproval?.kind, .uiPressKey)
        XCTAssertEqual(controller.bridgeMessage, "Fetched job; waiting for approval")
    }

    func testCompletePendingPressKeyJobQueuesSucceededReceipt() async {
        let executor = FakeControllerKeyPressExecutor()
        let transport = FakeLocalBridgeTransport(
            nextJob: job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        )
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            keyPressExecutor: executor,
            store: InMemoryBridgeResultStore(),
            transport: transport
        )
        _ = await controller.fetchNextRemoteJob()

        controller.completePendingAutomationJob()

        XCTAssertNil(controller.pendingJob)
        XCTAssertEqual(controller.latestResult?.status, .succeeded)
        XCTAssertEqual(controller.latestResult?.output?.keyPress?.key, "escape")
        XCTAssertEqual(executor.executedKeys, ["escape"])
        XCTAssertEqual(controller.outboxCount, 1)
    }

    func testCancelPendingJobQueuesRejectedReceipt() async {
        let transport = FakeLocalBridgeTransport(
            nextJob: job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        )
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            keyPressExecutor: FakeControllerKeyPressExecutor(),
            store: InMemoryBridgeResultStore(),
            transport: transport
        )
        _ = await controller.fetchNextRemoteJob()

        controller.cancelPendingJob()

        XCTAssertNil(controller.pendingJob)
        XCTAssertEqual(controller.latestResult?.status, .rejected)
        XCTAssertEqual(controller.latestResult?.error?.code, "user_cancelled")
        XCTAssertEqual(controller.outboxCount, 1)
    }

    private func job(
        kind: BridgeJobKind,
        risk: BridgeRisk,
        input: BridgeJobInput
    ) -> BridgeJobEnvelope {
        BridgeJobEnvelope(
            jobID: "job_controller",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            kind: kind,
            risk: risk,
            input: input,
            expiresAt: Date().addingTimeInterval(30),
            idempotencyKey: "idem_controller"
        )
    }

    private func snapshot() -> ContextSnapshot {
        ContextSnapshot(
            snapshotID: "ctx_test",
            capturedAt: now,
            activeApp: ActiveApplication(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            window: ActiveWindow(id: 42, title: "Draft"),
            focusedElement: FocusedElement(role: "AXTextArea", label: "Body", valuePreview: nil),
            selectedText: nil,
            visibleElements: [],
            screenshotReference: nil,
            redactions: []
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "EclipseMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeLocalBridgeTransport: LocalBridgeTransporting, @unchecked Sendable {
    private let nextJob: BridgeJobEnvelope?
    private let fetchError: Error?
    private(set) var fetchCount = 0
    private(set) var replayedResults: [BridgeJobResultEnvelope] = []
    private(set) var createdRequests: [BridgeCreateJobRequest] = []
    private(set) var createdJobs: [BridgeJobEnvelope] = []

    init(nextJob: BridgeJobEnvelope?, fetchError: Error? = nil) {
        self.nextJob = nextJob
        self.fetchError = fetchError
    }

    func fetchNextJob(deviceID: String) async throws -> BridgeJobEnvelope? {
        fetchCount += 1
        if let fetchError {
            throw fetchError
        }
        return nextJob
    }

    func postResult(_ result: BridgeJobResultEnvelope) async throws -> BridgePostResultResponse {
        BridgePostResultResponse(duplicate: false, result: result)
    }

    func replayOutbox(_ results: [BridgeJobResultEnvelope]) async throws -> BridgeOutboxReplayResponse {
        replayedResults = results
        return BridgeOutboxReplayResponse(accepted: results.count, duplicates: 0, results: results)
    }

    func createJob(_ request: BridgeCreateJobRequest) async throws -> BridgeJobEnvelope {
        createdRequests.append(request)
        let job = BridgeJobEnvelope(
            jobID: "job_created_\(createdRequests.count)",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: request.deviceID,
            kind: request.kind,
            risk: request.risk,
            input: request.input,
            expiresAt: Date().addingTimeInterval(TimeInterval(request.ttlSeconds)),
            idempotencyKey: request.idempotencyKey ?? "idem_created_\(createdRequests.count)"
        )
        createdJobs.append(job)
        return job
    }

    func fetchStats() async throws -> BridgeStats {
        BridgeStats(queuedJobs: createdRequests.count, results: 2)
    }

    func fetchQueuedJobs() async throws -> [BridgeJobEnvelope] {
        createdJobs
    }

    func fetchResults() async throws -> [BridgeJobResultEnvelope] {
        [
            result(jobID: "job_result_1", status: .succeeded),
            result(jobID: "job_result_2", status: .failed)
        ]
    }

    private func result(jobID: String, status: BridgeJobStatus) -> BridgeJobResultEnvelope {
        BridgeJobResultEnvelope(
            jobID: jobID,
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            status: status,
            output: nil,
            error: status == .failed ? BridgeErrorPayload(code: "test", message: "Test failure") : nil,
            completedAt: Date(),
            idempotencyKey: "idem_\(jobID)"
        )
    }
}

@MainActor
private final class FakeControllerContextCollector: ContextCollecting {
    private let snapshot: ContextSnapshot

    init(snapshot: ContextSnapshot) {
        self.snapshot = snapshot
    }

    func capture() throws -> ContextSnapshot {
        snapshot
    }
}

@MainActor
private final class FakeControllerKeyPressExecutor: KeyPressExecuting {
    private(set) var executedKeys: [String] = []

    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date
    ) throws -> BridgeKeyPressResult {
        let key = input.key ?? "missing"
        executedKeys.append(key)
        return BridgeKeyPressResult(
            actionID: approval.actionID,
            key: key,
            modifiers: input.modifiers ?? [],
            completedAt: now
        )
    }
}
