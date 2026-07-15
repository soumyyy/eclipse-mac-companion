import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SetTextActionExecutor {
    private enum Attribute {
        static let focusedElement = "AXFocusedUIElement"
        static let role = "AXRole"
        static let value = "AXValue"
    }

    private let collector: any ContextCollecting
    private let policy: SetTextActionPolicy
    private let workspace: NSWorkspace

    init(
        collector: any ContextCollecting = AccessibilityContextCollector(),
        policy: SetTextActionPolicy = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.collector = collector
        self.policy = policy
        self.workspace = workspace
    }

    func prepare(proposedText: String) throws -> PendingSetTextAction {
        let snapshot = try collector.capture()
        let target = try policy.validatePreparation(
            snapshot: snapshot,
            proposedText: proposedText
        )

        guard let runningApplication = workspace.frontmostApplication,
              runningApplication.bundleIdentifier == target.bundleID else {
            throw SetTextActionError.applicationChanged
        }
        guard let element = focusedElement(for: runningApplication.processIdentifier) else {
            throw SetTextActionError.missingFocusedElement
        }
        guard stringValue(from: element, attribute: Attribute.role) == target.elementRole else {
            throw SetTextActionError.focusChanged
        }

        return PendingSetTextAction(
            presentation: SetTextActionPresentation(
                actionID: "act_\(UUID().uuidString.lowercased())",
                target: target,
                proposedText: proposedText,
                createdAt: Date()
            ),
            processIdentifier: runningApplication.processIdentifier,
            element: element
        )
    }

    func execute(_ pending: PendingSetTextAction) throws -> SetTextActionResult {
        let snapshot = try collector.capture()
        try policy.validateExecution(
            presentation: pending.presentation,
            currentSnapshot: snapshot
        )

        guard let runningApplication = workspace.frontmostApplication,
              runningApplication.processIdentifier == pending.processIdentifier,
              runningApplication.bundleIdentifier == pending.presentation.target.bundleID else {
            throw SetTextActionError.applicationChanged
        }
        guard let currentElement = focusedElement(for: runningApplication.processIdentifier),
              CFEqual(currentElement, pending.element) else {
            throw SetTextActionError.focusChanged
        }

        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            currentElement,
            Attribute.value as CFString,
            &isSettable
        ) == .success, isSettable.boolValue else {
            throw SetTextActionError.elementNotSettable
        }

        let writeError = AXUIElementSetAttributeValue(
            currentElement,
            Attribute.value as CFString,
            pending.presentation.proposedText as CFString
        )
        guard writeError == .success else {
            throw SetTextActionError.writeFailed
        }

        return SetTextActionResult(
            actionID: pending.presentation.actionID,
            snapshotID: pending.presentation.target.snapshotID,
            completedAt: Date(),
            charactersWritten: pending.presentation.proposedText.count
        )
    }

    private func focusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            Attribute.focusedElement as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringValue(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }
}
