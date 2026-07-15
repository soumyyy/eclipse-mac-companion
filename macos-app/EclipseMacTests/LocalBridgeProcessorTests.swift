import CoreGraphics
import XCTest
@testable import EclipseMac

@MainActor
final class LocalBridgeProcessorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testContextJobReturnsSnapshotResult() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
            job(kind: .contextGetActiveWindow, risk: .read, input: .empty),
            now: now
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.context?.snapshotID, "ctx_test")
        XCTAssertEqual(result.output?.context?.activeApp?.bundleID, "com.apple.TextEdit")
    }

    func testCaptureWindowJobReturnsMetadataOnly() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
            job(kind: .contextCaptureWindow, risk: .read, input: .empty),
            now: now
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.capture?.captureID, "cap_test")
        XCTAssertEqual(result.output?.capture?.snapshotID, "ctx_test")
        XCTAssertEqual(result.output?.capture?.pixelWidth, 100)
        XCTAssertNil(result.output?.context)
    }

    func testNotificationJobReturnsDeliveryReceipt() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
            job(kind: .notificationShow, risk: .reversible, input: .notification(title: "Heads up", body: "Done")),
            now: now
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.notification?.notificationID, "notif_test")
    }

    func testPressKeyJobReturnsAutomationApproval() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
            job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape")),
            now: now
        )

        XCTAssertEqual(result.status, .pendingApproval)
        XCTAssertEqual(result.output?.automationApproval?.kind, .uiPressKey)
        XCTAssertEqual(result.output?.automationApproval?.targetApp?.bundleID, "com.apple.TextEdit")
    }

    func testClickElementJobReturnsAutomationApproval() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
            job(kind: .uiClickElement, risk: .consequential, input: .clickElement(role: "AXButton", label: "Continue")),
            now: now
        )

        XCTAssertEqual(result.status, .pendingApproval)
        XCTAssertEqual(result.output?.automationApproval?.kind, .uiClickElement)
        XCTAssertEqual(result.output?.automationApproval?.risk, .consequential)
    }

    func testSetTextJobReturnsPendingApprovalWithoutCompletingAction() async {
        let textActions = FakeTextActions()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: textActions,
            store: InMemoryBridgeResultStore()
        )

        let result = await processor.process(
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
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
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

    func testDuplicateSetTextJobReplaysPendingApprovalWithoutPreparingAgain() async {
        let textActions = FakeTextActions()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: textActions,
            store: InMemoryBridgeResultStore()
        )
        let job = job(kind: .uiSetText, risk: .reversible, input: .setText("Hello"))

        let first = await processor.process(job, now: now)
        let second = await processor.process(job, now: now.addingTimeInterval(1))

        XCTAssertEqual(first.status, .pendingApproval)
        XCTAssertEqual(second.status, .pendingApproval)
        XCTAssertEqual(first.output?.approval?.approvalID, second.output?.approval?.approvalID)
        XCTAssertEqual(textActions.prepareCount, 1)
    }

    func testCompletedSetTextJobReplaysFinalReceipt() async {
        let textActions = FakeTextActions()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: textActions,
            store: InMemoryBridgeResultStore()
        )
        let job = job(kind: .uiSetText, risk: .reversible, input: .setText("Hello"))
        _ = await processor.process(job, now: now)
        let actionResult = SetTextActionResult(
            actionID: "act_test",
            snapshotID: "ctx_test",
            completedAt: now,
            charactersWritten: 5
        )
        _ = processor.completionResult(for: job, actionResult: actionResult, completedAt: now)

        let replay = await processor.process(job, now: now.addingTimeInterval(2))

        XCTAssertEqual(replay.status, .succeeded)
        XCTAssertEqual(replay.output?.actionResult?.charactersWritten, 5)
        XCTAssertEqual(textActions.prepareCount, 1)
    }

    func testAutomationCompletionExecutesApprovedKeyPressAndReplacesPendingReceipt() async {
        let executor = FakeKeyPressExecutor()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: executor,
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )
        let job = job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        let pending = await processor.process(job, now: now)
        let approval = try! XCTUnwrap(pending.output?.automationApproval)

        let result = processor.automationCompletionResult(
            for: job,
            approval: approval,
            completedAt: now.addingTimeInterval(1)
        )
        let replay = await processor.process(job, now: now.addingTimeInterval(2))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.keyPress?.key, "escape")
        XCTAssertEqual(executor.executedKeys, ["escape"])
        XCTAssertEqual(replay.status, .succeeded)
        XCTAssertEqual(replay.output?.keyPress?.actionID, approval.actionID)
    }

    func testRejectionResultReplacesPendingApprovalReceipt() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )
        let job = job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        _ = await processor.process(job, now: now)

        let result = processor.rejectionResult(for: job, completedAt: now.addingTimeInterval(1))

        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.error?.code, "user_cancelled")
    }

    func testExpirationResultReplacesPendingApprovalReceipt() async {
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: FakeClickElementExecutor(),
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )
        let job = job(kind: .uiPressKey, risk: .reversible, input: .keyPress(key: "escape"))
        _ = await processor.process(job, now: now)

        let result = processor.expirationResult(for: job, completedAt: now.addingTimeInterval(11))

        XCTAssertEqual(result.status, .expired)
        XCTAssertEqual(result.error?.code, "approval_expired")
    }

    func testAutomationCompletionExecutesApprovedClickAndReplacesPendingReceipt() async {
        let executor = FakeClickElementExecutor()
        let processor = LocalBridgeProcessor(
            deviceID: "mac_test",
            collector: FakeContextCollector(snapshot: snapshot()),
            capturer: FakeWindowCapturer(),
            notifier: FakeNotifier(),
            keyPressExecutor: FakeKeyPressExecutor(),
            clickElementExecutor: executor,
            textActions: FakeTextActions(),
            store: InMemoryBridgeResultStore()
        )
        let job = job(
            kind: .uiClickElement,
            risk: .consequential,
            input: .clickElement(role: "AXButton", label: "Continue")
        )
        let pending = await processor.process(job, now: now)
        let approval = try! XCTUnwrap(pending.output?.automationApproval)

        let result = processor.automationCompletionResult(
            for: job,
            approval: approval,
            completedAt: now.addingTimeInterval(1)
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output?.click?.elementRole, "AXButton")
        XCTAssertEqual(result.output?.click?.elementLabel, "Continue")
        XCTAssertEqual(executor.executedLabels, ["Continue"])
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
private final class FakeWindowCapturer: WindowCapturing {
    func capture(snapshot: ContextSnapshot) async throws -> WindowCaptureResult {
        WindowCaptureResult(
            image: Self.image(),
            metadata: WindowCaptureMetadata(
                captureID: "cap_test",
                snapshotID: snapshot.snapshotID,
                windowID: snapshot.window?.id ?? 0,
                capturedAt: Date(timeIntervalSince1970: 1_000),
                pixelWidth: 100,
                pixelHeight: 50
            )
        )
    }

    private static func image() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

@MainActor
private final class FakeNotifier: LocalNotificationDelivering {
    func deliver(title: String, body: String?) async throws -> BridgeNotificationReceipt {
        BridgeNotificationReceipt(
            notificationID: "notif_test",
            deliveredAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@MainActor
private final class FakeKeyPressExecutor: KeyPressExecuting {
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

@MainActor
private final class FakeClickElementExecutor: ClickElementExecuting {
    private(set) var executedLabels: [String] = []

    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date
    ) throws -> BridgeClickResult {
        let label = input.elementLabel ?? "missing"
        executedLabels.append(label)
        return BridgeClickResult(
            actionID: approval.actionID,
            elementRole: input.elementRole ?? "missing",
            elementLabel: label,
            completedAt: now
        )
    }
}

@MainActor
private final class FakeTextActions: SetTextActionControlling {
    var pendingPresentation: SetTextActionPresentation?
    var preparedText: String?
    var prepareCount = 0

    func prepareAction(text: String) throws {
        prepareCount += 1
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
