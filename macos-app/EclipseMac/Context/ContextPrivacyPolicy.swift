import Foundation

struct SanitizedText: Equatable, Sendable {
    let value: String?
    let wasTruncated: Bool
}

struct ContextPrivacyPolicy: Equatable, Sendable {
    let maxTextLength: Int
    let blockedBundleIDs: Set<String>
    let blockedWindowTitleFragments: [String]

    static let `default` = ContextPrivacyPolicy(
        maxTextLength: 500,
        blockedBundleIDs: [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.apple.keychainaccess",
            "com.bitwarden.desktop",
            "com.dashlane.Dashlane",
            "com.lastpass.LastPass"
        ],
        blockedWindowTitleFragments: []
    )

    func blocks(bundleID: String) -> Bool {
        blockedBundleIDs.contains(bundleID)
    }

    func blocks(windowTitle: String?) -> Bool {
        guard let windowTitle else { return false }
        return blockedWindowTitleFragments.contains { fragment in
            windowTitle.localizedCaseInsensitiveContains(fragment)
        }
    }

    func sanitize(_ text: String?) -> SanitizedText {
        guard let text else {
            return SanitizedText(value: nil, wasTruncated: false)
        }

        guard text.count > maxTextLength else {
            return SanitizedText(value: text, wasTruncated: false)
        }

        let endIndex = text.index(text.startIndex, offsetBy: maxTextLength)
        return SanitizedText(
            value: String(text[..<endIndex]) + "…",
            wasTruncated: true
        )
    }
}
