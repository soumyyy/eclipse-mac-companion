import XCTest
@testable import EclipseMac

final class ContextSnapshotCodingTests: XCTestCase {
    func testSnapshotUsesProtocolWireKeys() throws {
        let snapshot = ContextSnapshot(
            snapshotID: "ctx_test",
            capturedAt: Date(timeIntervalSince1970: 0),
            activeApp: ActiveApplication(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            window: ActiveWindow(id: 42, title: "Draft"),
            focusedElement: FocusedElement(role: "AXTextArea", label: "Body", valuePreview: "Hello"),
            selectedText: nil,
            visibleElements: [],
            screenshotReference: nil,
            redactions: [.secureFields]
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        let activeApp = try XCTUnwrap(object["active_app"] as? [String: Any])
        let focusedElement = try XCTUnwrap(object["focused_element"] as? [String: Any])

        XCTAssertEqual(object["snapshot_id"] as? String, "ctx_test")
        XCTAssertEqual(activeApp["bundle_id"] as? String, "com.apple.TextEdit")
        XCTAssertEqual(focusedElement["value_preview"] as? String, "Hello")
        XCTAssertNotNil(object["screenshot_ref"] as Any?)
    }
}
