import XCTest
@testable import EclipseMac

final class WindowCapturePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testValidSnapshotProducesBoundRequest() throws {
        let request = try WindowCapturePolicy.default.validate(
            snapshot: snapshot(capturedAt: now),
            now: now
        )

        XCTAssertEqual(request.snapshotID, "ctx_test")
        XCTAssertEqual(request.windowID, 42)
        XCTAssertEqual(request.bundleID, "com.apple.TextEdit")
    }

    func testBlockedApplicationIsRejected() {
        XCTAssertThrowsError(
            try WindowCapturePolicy.default.validate(
                snapshot: snapshot(capturedAt: now, redactions: [.blockedApplication]),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? WindowCaptureError, .blockedContext)
        }
    }

    func testStaleSnapshotIsRejected() {
        XCTAssertThrowsError(
            try WindowCapturePolicy.default.validate(
                snapshot: snapshot(capturedAt: now.addingTimeInterval(-11)),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? WindowCaptureError, .staleContext)
        }
    }

    func testPixelSizePreservesAspectRatioAndCapsLargestDimension() {
        let size = ActiveWindowCapturer.pixelSize(
            for: CGSize(width: 3_000, height: 2_000),
            scale: 2,
            maximumDimension: 3_000
        )

        XCTAssertEqual(size.width, 3_000)
        XCTAssertEqual(size.height, 2_000)
    }

    private func snapshot(
        capturedAt: Date,
        redactions: [Redaction] = []
    ) -> ContextSnapshot {
        ContextSnapshot(
            snapshotID: "ctx_test",
            capturedAt: capturedAt,
            activeApp: ActiveApplication(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            window: ActiveWindow(id: 42, title: "Draft"),
            focusedElement: nil,
            selectedText: nil,
            visibleElements: [],
            screenshotReference: nil,
            redactions: redactions
        )
    }
}
