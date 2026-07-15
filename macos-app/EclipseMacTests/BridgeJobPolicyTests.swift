import XCTest
@testable import EclipseMac

final class BridgeJobPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testReadJobAcceptsReadRisk() throws {
        XCTAssertNoThrow(try BridgeJobPolicy.default.validate(job(kind: .contextGetActiveWindow, risk: .read), now: now))
    }

    func testReadJobRejectsReversibleRisk() {
        XCTAssertThrowsError(
            try BridgeJobPolicy.default.validate(job(kind: .contextGetActiveWindow, risk: .reversible), now: now)
        ) { error in
            XCTAssertEqual(error as? BridgeJobPolicyError, .riskMismatch)
        }
    }

    func testExpiredJobIsRejected() {
        XCTAssertThrowsError(
            try BridgeJobPolicy.default.validate(
                job(kind: .uiSetText, risk: .reversible, expiresAt: now.addingTimeInterval(-1)),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? BridgeJobPolicyError, .expiredJob)
        }
    }

    func testSetTextRequiresText() {
        XCTAssertThrowsError(
            try BridgeJobPolicy.default.validate(
                job(kind: .uiSetText, risk: .reversible, input: .empty),
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? BridgeJobPolicyError,
                .invalidInput("ui.set_text requires non-empty input.text")
            )
        }
    }

    private func job(
        kind: BridgeJobKind,
        risk: BridgeRisk,
        input: BridgeJobInput = .setText("Hello"),
        expiresAt: Date? = nil
    ) -> BridgeJobEnvelope {
        BridgeJobEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            kind: kind,
            risk: risk,
            input: kind == .contextGetActiveWindow ? .empty : input,
            expiresAt: expiresAt ?? now.addingTimeInterval(30),
            idempotencyKey: "idem_test"
        )
    }
}
