import XCTest
@testable import EclipseMac

@MainActor
final class LocalBridgeProcessorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testContextJobReturnsSnapshotResult() {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            textActions: FakeTextActions()
        )

        let result = processor.process(
            job(kind: .contextGetActiveWindow, risk: .read, input: .empty),
            now: now
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.context?.snapshotID, "ctx_test")
        XCTAssertEqual(result.output?.context?.activeApp?.bundleID, "com.apple.TextEdit")
    }

    func testSetTextJobReturnsPendingApprovalWithoutCompletingAction() {
        let textActions = FakeTextActions()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            textActions: textActions
        )

        let result = processor.process(
            job(kind: .uiSetText, risk: .reversible, input: .setText("Hello")),
            now: now
        )

        XCTAssertEqual(result.status, .pendingApproval)
        XCTAssertEqual(textActions.preparedText, "Hello")
        XCTAssertEqual(result.output?.approval?.proposedText, "Hello")
        XCTAssertEqual(result.output?.approval?.target.bundleID, "com.apple.TextEdit")
    }

    func testCompletionResultProducesActionReceipt() {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            textActions: FakeTextActions()
        )
        let job = job(kind: .uiSetText, risk: .reversible, input: .setText("Hello"))
        let actionResult = SetTextActionResult(
            actionID: "act_test",
            snapshotID: "ctx_test",
            completedAt: now,
            charactersWritten: 5
        )

        let result = processor.completionResult(for: job, actionResult: actionResult, completedAt: now)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.actionResult?.charactersWritten, 5)
        XCTAssertEqual(result.idempotencyKey, "idem_test")
    }

    private func job(
        kind: BridgeJobKind,
        risk: BridgeRisk,
        input: BridgeJobInput
    ) -> BridgeJobEnvelope {
        BridgeJobEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            kind: kind,
            risk: risk,
            input: input,
            expiresAt: now.addingTimeInterval(30),
            idempotencyKey: "idem_test"
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

@MainActor
private final class FakeContextCollector: ContextCollecting {
    private let snapshot: ContextSnapshot

    init(snapshot: ContextSnapshot) {
        self.snapshot = snapshot
    }

    func capture() throws -> ContextSnapshot {
        snapshot
    }
}

@MainActor
private final class FakeTextActions: SetTextActionControlling {
    var pendingPresentation: SetTextActionPresentation?
    var preparedText: String?

    func prepareAction(text: String) throws {
        preparedText = text
        pendingPresentation = SetTextActionPresentation(
            actionID: "act_test",
            target: SetTextTargetBinding(
                snapshotID: "ctx_test",
                bundleID: "com.apple.TextEdit",
                applicationName: "TextEdit",
                windowID: 42,
                windowTitle: "Draft",
                elementRole: "AXTextArea",
                elementLabel: "Body"
            ),
            proposedText: text,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
