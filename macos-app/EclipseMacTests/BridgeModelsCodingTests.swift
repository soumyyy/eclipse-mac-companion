import XCTest
@testable import EclipseMac

final class BridgeModelsCodingTests: XCTestCase {
    func testJobEnvelopeUsesProtocolWireKeys() throws {
        let job = BridgeJobEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            kind: .uiSetText,
            risk: .reversible,
            input: .setText("Hello"),
            expiresAt: Date(timeIntervalSince1970: 1_000),
            idempotencyKey: "idem_test"
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any]
        )
        let input = try XCTUnwrap(object["input"] as? [String: Any])

        XCTAssertEqual(object["job_id"] as? String, "job_test")
        XCTAssertEqual(object["protocol_version"] as? String, "0.1")
        XCTAssertEqual(object["device_id"] as? String, "mac_test")
        XCTAssertEqual(object["kind"] as? String, "ui.set_text")
        XCTAssertEqual(object["risk"] as? String, "reversible")
        XCTAssertEqual(input["text"] as? String, "Hello")
        XCTAssertEqual(object["idempotency_key"] as? String, "idem_test")
    }

    func testResultEnvelopeUsesProtocolWireKeys() throws {
        let result = BridgeJobResultEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            status: .pendingApproval,
            output: nil,
            error: nil,
            completedAt: Date(timeIntervalSince1970: 2_000),
            idempotencyKey: "idem_test"
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        )

        XCTAssertEqual(object["job_id"] as? String, "job_test")
        XCTAssertEqual(object["protocol_version"] as? String, "0.1")
        XCTAssertEqual(object["device_id"] as? String, "mac_test")
        XCTAssertEqual(object["status"] as? String, "pending_approval")
        XCTAssertEqual(object["idempotency_key"] as? String, "idem_test")
    }
}
