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
}

private final class FakeLocalBridgeTransport: LocalBridgeTransporting, @unchecked Sendable {
    private let nextJob: BridgeJobEnvelope?
    private(set) var replayedResults: [BridgeJobResultEnvelope] = []

    init(nextJob: BridgeJobEnvelope?) {
        self.nextJob = nextJob
    }

    func fetchNextJob(deviceID: String) async throws -> BridgeJobEnvelope? {
        nextJob
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
