import XCTest
@testable import EclipseMac

@MainActor
final class ClickElementActionExecutorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testExecuteRequiresLabelBeforeTouchingAccessibility() {
        let executor = ClickElementActionExecutor(collector: FakeClickContextCollector())

        XCTAssertThrowsError(
            try executor.execute(
                approval: approval(),
                input: .clickElement(role: "AXButton", label: nil),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? ClickElementActionError, .missingLabel)
        }
    }

    func testExecuteBlocksRiskyLabelsBeforeTouchingAccessibility() {
        let executor = ClickElementActionExecutor(collector: FakeClickContextCollector())

        XCTAssertThrowsError(
            try executor.execute(
                approval: approval(),
                input: .clickElement(role: "AXButton", label: "Send payment"),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? ClickElementActionError, .blockedRiskyLabel)
        }
    }

    private func approval() -> BridgeAutomationApprovalRequest {
        BridgeAutomationApprovalRequest(
            approvalID: "appr_test",
            actionID: "act_test",
            kind: .uiClickElement,
            risk: .consequential,
            summary: "Click AXButton labeled Continue",
            targetApp: ActiveApplication(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            targetWindow: ActiveWindow(id: 42, title: "Draft"),
            expiresAt: now.addingTimeInterval(10)
        )
    }
}

@MainActor
private final class FakeClickContextCollector: ContextCollecting {
    func capture() throws -> ContextSnapshot {
        XCTFail("Safety validation should fail before collecting Accessibility context")
        throw ContextCollectorError.accessibilityReadFailed
    }
}
