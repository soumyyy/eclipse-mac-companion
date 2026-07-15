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
        let controller = LocalBridgeController(
            deviceID: "mac_test",
            setTextActions: SetTextActionController(),
            collector: FakeControllerContextCollector(snapshot: snapshot()),
            store: InMemoryBridgeResultStore(),
            configurationStore: LocalBridgeConfigurationStore(defaults: defaults),
            transport: FakeLocalBridgeTransport(nextJob: nil)
        )
        controller.bridgeBaseURLString = " https://bridge.example.test "
        controller.bridgeBearerToken = " dev-token "

        XCTAssertTrue(controller.saveBridgeBaseURL())
        XCTAssertEqual(controller.bridgeBaseURLString, "https://bridge.example.test")
        XCTAssertEqual(controller.bridgeBearerToken, "dev-token")
        XCTAssertEqual(defaults.string(forKey: "localBridge.baseURL"), "https://bridge.example.test")
        XCTAssertEqual(defaults.string(forKey: "localBridge.bearerToken"), "dev-token")
        XCTAssertEqual(controller.bridgeStatus, "Bridge URL saved")
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
