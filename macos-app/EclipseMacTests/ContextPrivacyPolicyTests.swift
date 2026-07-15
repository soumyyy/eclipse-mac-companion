import XCTest
@testable import EclipseMac

final class ContextPrivacyPolicyTests: XCTestCase {
    func testDefaultPolicyBlocksPasswordManagers() {
        XCTAssertTrue(ContextPrivacyPolicy.default.blocks(bundleID: "com.1password.1password"))
        XCTAssertTrue(ContextPrivacyPolicy.default.blocks(bundleID: "com.bitwarden.desktop"))
        XCTAssertFalse(ContextPrivacyPolicy.default.blocks(bundleID: "com.apple.TextEdit"))
    }

    func testSanitizeTruncatesAtConfiguredLimit() {
        let policy = ContextPrivacyPolicy(
            maxTextLength: 5,
            blockedBundleIDs: [],
            blockedWindowTitleFragments: []
        )

        XCTAssertEqual(
            policy.sanitize("123456"),
            SanitizedText(value: "12345…", wasTruncated: true)
        )
        XCTAssertEqual(
            policy.sanitize("12345"),
            SanitizedText(value: "12345", wasTruncated: false)
        )
    }

    func testWindowBlocklistIsCaseInsensitive() {
        let policy = ContextPrivacyPolicy(
            maxTextLength: 100,
            blockedBundleIDs: [],
            blockedWindowTitleFragments: ["private workspace"]
        )

        XCTAssertTrue(policy.blocks(windowTitle: "My PRIVATE WORKSPACE"))
        XCTAssertFalse(policy.blocks(windowTitle: "Public workspace"))
    }
}
