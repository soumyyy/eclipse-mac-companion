import XCTest
@testable import EclipseMac

@MainActor
final class SQLiteBridgeResultStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testPersistsAndReopensResultByIdempotencyKey() throws {
        let path = temporaryDatabasePath()
        let job = makeJob()
        let result = makeResult(status: .succeeded)

        do {
            let store = try SQLiteBridgeResultStore(path: path)
            try store.save(job: job, result: result)
        }

        let reopened = try SQLiteBridgeResultStore(path: path)
        let stored = try XCTUnwrap(try reopened.result(for: "idem_test"))

        XCTAssertEqual(stored.jobID, "job_test")
        XCTAssertEqual(stored.status, .succeeded)
        XCTAssertEqual(stored.idempotencyKey, "idem_test")
    }

    func testOutboxCanMarkResultPosted() throws {
        let store = try SQLiteBridgeResultStore(path: temporaryDatabasePath())
        let job = makeJob()
        try store.save(job: job, result: makeResult(status: .pendingApproval))

        XCTAssertEqual(try store.unpostedResults(limit: 10).map(\.jobID), ["job_test"])

        try store.markPosted(jobID: "job_test")

        XCTAssertTrue(try store.unpostedResults(limit: 10).isEmpty)
    }

    func testReplacingPendingWithFinalReceiptRequeuesOutbox() throws {
        let store = try SQLiteBridgeResultStore(path: temporaryDatabasePath())
        let job = makeJob()
        try store.save(job: job, result: makeResult(status: .pendingApproval))
        try store.markPosted(jobID: "job_test")
        try store.save(job: job, result: makeResult(status: .succeeded))

        let unposted = try store.unpostedResults(limit: 10)

        XCTAssertEqual(unposted.count, 1)
        XCTAssertEqual(unposted.first?.status, .succeeded)
    }

    private func temporaryDatabasePath() -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eclipse-mac-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("bridge.sqlite3").path
    }

    private func makeJob() -> BridgeJobEnvelope {
        BridgeJobEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            kind: .uiSetText,
            risk: .reversible,
            input: .setText("Hello"),
            expiresAt: now.addingTimeInterval(30),
            idempotencyKey: "idem_test"
        )
    }

    private func makeResult(status: BridgeJobStatus) -> BridgeJobResultEnvelope {
        BridgeJobResultEnvelope(
            jobID: "job_test",
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: "mac_test",
            status: status,
            output: nil,
            error: nil,
            completedAt: now,
            idempotencyKey: "idem_test"
        )
    }
}
