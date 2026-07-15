import XCTest
@testable import EclipseMac

final class AssistantStateTests: XCTestCase {
    func testDebugStateCycleReturnsToIdle() {
        var state = AssistantState.idle
        for _ in AssistantState.allCases {
            state = state.nextDebugState
        }
        XCTAssertEqual(state, .idle)
    }

    func testWireValueForApprovalState() {
        XCTAssertEqual(AssistantState.waitingForApproval.rawValue, "waiting_for_approval")
    }
}
