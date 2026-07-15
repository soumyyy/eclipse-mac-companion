import XCTest
@testable import EclipseMac

final class SetTextActionPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testPreparationBindsExactTarget() throws {
        let target = try SetTextActionPolicy.default.validatePreparation(
            snapshot: snapshot(),
            proposedText: "Hello"
        )

        XCTAssertEqual(target.snapshotID, "ctx_test")
        XCTAssertEqual(target.bundleID, "com.apple.TextEdit")
        XCTAssertEqual(target.windowID, 42)
        XCTAssertEqual(target.elementRole, "AXTextArea")
    }

    func testSecureFieldIsRejected() {
        XCTAssertThrowsError(
            try SetTextActionPolicy.default.validatePreparation(
                snapshot: snapshot(redactions: [.secureFields]),
                proposedText: "Hello"
            )
        ) { error in
            XCTAssertEqual(error as? SetTextActionError, .secureField)
        }
    }

    func testUnsupportedElementIsRejected() {
        XCTAssertThrowsError(
            try SetTextActionPolicy.default.validatePreparation(
                snapshot: snapshot(role: "AXButton"),
                proposedText: "Hello"
            )
        ) { error in
            XCTAssertEqual(error as? SetTextActionError, .unsupportedElement)
        }
    }

    func testExpiredApprovalIsRejected() {
        let presentation = presentation(createdAt: now.addingTimeInterval(-11))

        XCTAssertThrowsError(
            try SetTextActionPolicy.default.validateExecution(
                presentation: presentation,
                currentSnapshot: snapshot(),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? SetTextActionError, .staleApproval)
        }
    }

    func testChangedWindowIsRejected() {
        let presentation = presentation(createdAt: now)

        XCTAssertThrowsError(
            try SetTextActionPolicy.default.validateExecution(
                presentation: presentation,
                currentSnapshot: snapshot(windowID: 99),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? SetTextActionError, .windowChanged)
        }
    }

    private func presentation(createdAt: Date) -> SetTextActionPresentation {
        SetTextActionPresentation(
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
            proposedText: "Hello",
            createdAt: createdAt
        )
    }

    private func snapshot(
        windowID: UInt32 = 42,
        role: String = "AXTextArea",
        redactions: [Redaction] = []
    ) -> ContextSnapshot {
        ContextSnapshot(
            snapshotID: "ctx_test",
            capturedAt: now,
            activeApp: ActiveApplication(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            window: ActiveWindow(id: windowID, title: "Draft"),
            focusedElement: FocusedElement(role: role, label: "Body", valuePreview: nil),
            selectedText: nil,
            visibleElements: [],
            screenshotReference: nil,
            redactions: redactions
        )
    }
}
