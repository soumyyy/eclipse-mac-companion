import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
protocol ContextCollecting {
    func capture() throws -> ContextSnapshot
}

enum ContextCollectorError: LocalizedError, Equatable {
    case accessibilityPermissionRequired
    case noActiveApplication
    case accessibilityReadFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to inspect the active window."
        case .noActiveApplication:
            "No active application is available."
        case .accessibilityReadFailed:
            "The active application did not expose a readable Accessibility window."
        }
    }
}

@MainActor
final class AccessibilityContextCollector: ContextCollecting {
    private enum Attribute {
        static let focusedWindow = "AXFocusedWindow"
        static let focusedElement = "AXFocusedUIElement"
        static let title = "AXTitle"
        static let role = "AXRole"
        static let subrole = "AXSubrole"
        static let description = "AXDescription"
        static let placeholder = "AXPlaceholderValue"
        static let value = "AXValue"
        static let selectedText = "AXSelectedText"
    }

    private let policy: ContextPrivacyPolicy
    private let workspace: NSWorkspace

    init(
        policy: ContextPrivacyPolicy = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.policy = policy
        self.workspace = workspace
    }

    func capture() throws -> ContextSnapshot {
        guard AXIsProcessTrusted() else {
            throw ContextCollectorError.accessibilityPermissionRequired
        }
        guard let runningApplication = workspace.frontmostApplication else {
            throw ContextCollectorError.noActiveApplication
        }

        let bundleID = runningApplication.bundleIdentifier ?? "unknown"
        let application = ActiveApplication(
            bundleID: bundleID,
            name: runningApplication.localizedName ?? bundleID
        )

        if policy.blocks(bundleID: bundleID) {
            return snapshot(
                application: application,
                window: nil,
                focusedElement: nil,
                selectedText: nil,
                redactions: [.blockedApplication]
            )
        }

        let applicationElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        guard let windowElement = elementValue(
            from: applicationElement,
            attribute: Attribute.focusedWindow
        ) else {
            throw ContextCollectorError.accessibilityReadFailed
        }

        var redactions: [Redaction] = []
        let rawWindowTitle = stringValue(from: windowElement, attribute: Attribute.title)
        let windowTitle = policy.sanitize(rawWindowTitle)
        if windowTitle.wasTruncated {
            redactions.append(.truncatedText)
        }

        let windowID = activeWindowID(processIdentifier: runningApplication.processIdentifier)
        if policy.blocks(windowTitle: rawWindowTitle) {
            redactions.append(.blockedWindow)
            return snapshot(
                application: application,
                window: ActiveWindow(id: windowID, title: nil),
                focusedElement: nil,
                selectedText: nil,
                redactions: redactions
            )
        }

        let focusedElement = elementValue(
            from: applicationElement,
            attribute: Attribute.focusedElement
        )

        let focusedContext = collectFocusedElement(focusedElement, redactions: &redactions)

        return snapshot(
            application: application,
            window: ActiveWindow(id: windowID, title: windowTitle.value),
            focusedElement: focusedContext.element,
            selectedText: focusedContext.selectedText,
            redactions: redactions
        )
    }

    private func collectFocusedElement(
        _ element: AXUIElement?,
        redactions: inout [Redaction]
    ) -> (element: FocusedElement?, selectedText: String?) {
        guard let element else { return (nil, nil) }

        let role = stringValue(from: element, attribute: Attribute.role) ?? "AXUnknown"
        let subrole = stringValue(from: element, attribute: Attribute.subrole)
        let isSecure = role == "AXSecureTextField" || subrole == "AXSecureTextField"

        let rawLabel = stringValue(from: element, attribute: Attribute.title)
            ?? stringValue(from: element, attribute: Attribute.description)
            ?? stringValue(from: element, attribute: Attribute.placeholder)
        let label = policy.sanitize(rawLabel)

        if label.wasTruncated {
            redactions.appendIfMissing(.truncatedText)
        }

        guard !isSecure else {
            redactions.appendIfMissing(.secureFields)
            return (
                FocusedElement(role: role, label: label.value, valuePreview: nil),
                nil
            )
        }

        let value = policy.sanitize(stringValue(from: element, attribute: Attribute.value))
        let selectedText = policy.sanitize(
            stringValue(from: element, attribute: Attribute.selectedText)
        )
        if value.wasTruncated || selectedText.wasTruncated {
            redactions.appendIfMissing(.truncatedText)
        }

        return (
            FocusedElement(role: role, label: label.value, valuePreview: value.value),
            selectedText.value
        )
    }

    private func snapshot(
        application: ActiveApplication,
        window: ActiveWindow?,
        focusedElement: FocusedElement?,
        selectedText: String?,
        redactions: [Redaction]
    ) -> ContextSnapshot {
        ContextSnapshot(
            snapshotID: "ctx_\(UUID().uuidString.lowercased())",
            capturedAt: Date(),
            activeApp: application,
            window: window,
            focusedElement: focusedElement,
            selectedText: selectedText,
            visibleElements: [],
            screenshotReference: nil,
            redactions: redactions
        )
    }

    private func copiedValue(
        from element: AXUIElement,
        attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringValue(from element: AXUIElement, attribute: String) -> String? {
        copiedValue(from: element, attribute: attribute) as? String
    }

    private func elementValue(from element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = copiedValue(from: element, attribute: attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func activeWindowID(processIdentifier: pid_t) -> UInt32? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return windows.first { window in
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            let layer = window[kCGWindowLayer as String] as? Int
            return ownerPID == processIdentifier && layer == 0
        }.flatMap { window in
            (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }
}

private extension Array where Element: Equatable {
    mutating func appendIfMissing(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}
