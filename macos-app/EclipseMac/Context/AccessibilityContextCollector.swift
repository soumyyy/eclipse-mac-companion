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
    private let ownProcessIdentifier: pid_t

    init(
        policy: ContextPrivacyPolicy = .default,
        workspace: NSWorkspace = .shared,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.policy = policy
        self.workspace = workspace
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    func capture() throws -> ContextSnapshot {
        guard AXIsProcessTrusted() else {
            throw ContextCollectorError.accessibilityPermissionRequired
        }
        guard let target = contextTarget() else {
            throw ContextCollectorError.noActiveApplication
        }
        let runningApplication = target.application

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
            if let targetWindow = target.window {
                return fallbackSnapshot(
                    application: application,
                    targetWindow: targetWindow
                )
            }
            throw ContextCollectorError.accessibilityReadFailed
        }

        var redactions: [Redaction] = []
        let rawWindowTitle = stringValue(from: windowElement, attribute: Attribute.title)
            ?? target.window?.title
        let windowTitle = policy.sanitize(rawWindowTitle)
        if windowTitle.wasTruncated {
            redactions.append(.truncatedText)
        }

        let windowID = activeWindowID(
            for: windowElement,
            processIdentifier: runningApplication.processIdentifier
        ) ?? target.window?.id
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

    private struct WindowStackTarget {
        let application: NSRunningApplication
        let window: ActiveWindow?
    }

    private func contextTarget() -> WindowStackTarget? {
        guard let frontmostApplication = workspace.frontmostApplication else {
            return nil
        }
        let frontmostTarget = WindowStackTarget(application: frontmostApplication, window: nil)
        guard shouldIgnoreForUnderlyingContext(frontmostApplication) else {
            return frontmostTarget
        }
        return topVisibleNonEclipseWindowTarget() ?? frontmostTarget
    }

    private func shouldIgnoreForUnderlyingContext(_ application: NSRunningApplication) -> Bool {
        if application.processIdentifier == ownProcessIdentifier {
            return true
        }
        let bundleID = application.bundleIdentifier ?? ""
        if bundleID == Bundle.main.bundleIdentifier {
            return true
        }
        return bundleID.hasPrefix("com.soumya.eclipse-mac")
    }

    private func topVisibleNonEclipseWindowTarget() -> WindowStackTarget? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownProcessIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let runningApplication = NSRunningApplication(processIdentifier: ownerPID),
                  !shouldIgnoreForUnderlyingContext(runningApplication),
                  isVisibleContextWindow(window) else {
                continue
            }

            let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            let windowTitle = window[kCGWindowName as String] as? String
            return WindowStackTarget(
                application: runningApplication,
                window: ActiveWindow(id: windowID, title: windowTitle)
            )
        }
        return nil
    }

    private func isVisibleContextWindow(_ window: [String: Any]) -> Bool {
        if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 {
            return false
        }
        guard let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
            return false
        }
        return bounds.width >= 80 && bounds.height >= 40
    }

    private func fallbackSnapshot(
        application: ActiveApplication,
        targetWindow: ActiveWindow
    ) -> ContextSnapshot {
        var redactions: [Redaction] = []
        let windowTitle = policy.sanitize(targetWindow.title)
        if windowTitle.wasTruncated {
            redactions.append(.truncatedText)
        }
        if policy.blocks(windowTitle: targetWindow.title) {
            redactions.append(.blockedWindow)
            return snapshot(
                application: application,
                window: ActiveWindow(id: targetWindow.id, title: nil),
                focusedElement: nil,
                selectedText: nil,
                redactions: redactions
            )
        }
        return snapshot(
            application: application,
            window: ActiveWindow(id: targetWindow.id, title: windowTitle.value),
            focusedElement: nil,
            selectedText: nil,
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

    private func activeWindowID(
        for windowElement: AXUIElement,
        processIdentifier: pid_t
    ) -> UInt32? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let applicationWindows = windows.filter { window in
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            let layer = window[kCGWindowLayer as String] as? Int
            return ownerPID == processIdentifier && layer == 0
        }

        let focusedFrame = windowFrame(from: windowElement)
        let matchingWindow = focusedFrame.flatMap { focusedFrame in
            applicationWindows.first { window in
                guard let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
                    return false
                }
                return bounds.approximatelyEquals(focusedFrame)
            }
        }

        let resolvedWindow = matchingWindow ?? (applicationWindows.count == 1 ? applicationWindows[0] : nil)
        return resolvedWindow.flatMap { window in
            (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }

    private func windowFrame(from windowElement: AXUIElement) -> CGRect? {
        guard let position = pointValue(from: windowElement, attribute: kAXPositionAttribute),
              let size = sizeValue(from: windowElement, attribute: kAXSizeAttribute) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func pointValue(from element: AXUIElement, attribute: String) -> CGPoint? {
        guard let value = copiedValue(from: element, attribute: attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(accessibilityValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(accessibilityValue, .cgPoint, &point) ? point : nil
    }

    private func sizeValue(from element: AXUIElement, attribute: String) -> CGSize? {
        guard let value = copiedValue(from: element, attribute: attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(accessibilityValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(accessibilityValue, .cgSize, &size) ? size : nil
    }
}

private extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}

private extension Array where Element: Equatable {
    mutating func appendIfMissing(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}
