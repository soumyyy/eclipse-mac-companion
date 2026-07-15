import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol ClickElementExecuting: AnyObject {
    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date
    ) throws -> BridgeClickResult
}

@MainActor
final class ClickElementActionExecutor: ClickElementExecuting {
    private enum Attribute {
        static let focusedWindow = "AXFocusedWindow"
        static let children = "AXChildren"
        static let role = "AXRole"
        static let title = "AXTitle"
        static let description = "AXDescription"
        static let value = "AXValue"
    }

    private let collector: any ContextCollecting
    private let workspace: NSWorkspace
    private let maximumApprovalAge: TimeInterval
    private let maximumSearchDepth = 8
    private let maximumVisitedElements = 400

    init(
        collector: any ContextCollecting = AccessibilityContextCollector(),
        workspace: NSWorkspace = .shared,
        maximumApprovalAge: TimeInterval = SetTextActionPolicy.default.maximumApprovalAge
    ) {
        self.collector = collector
        self.workspace = workspace
        self.maximumApprovalAge = maximumApprovalAge
    }

    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date = Date()
    ) throws -> BridgeClickResult {
        guard approval.kind == .uiClickElement else {
            throw ClickElementActionError.unsupportedAction
        }
        guard approval.expiresAt >= now,
              now.timeIntervalSince(approval.expiresAt.addingTimeInterval(-maximumApprovalAge)) <= maximumApprovalAge else {
            throw ClickElementActionError.staleApproval
        }
        guard let expectedRole = input.elementRole?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedRole.isEmpty else {
            throw ClickElementActionError.missingRole
        }
        guard let expectedLabel = input.elementLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedLabel.isEmpty else {
            throw ClickElementActionError.missingLabel
        }
        guard !Self.blocks(label: expectedLabel) else {
            throw ClickElementActionError.blockedRiskyLabel
        }

        let snapshot = try collector.capture()
        try validate(snapshot: snapshot, approval: approval)

        guard let runningApplication = workspace.frontmostApplication,
              runningApplication.bundleIdentifier == approval.targetApp?.bundleID else {
            throw ClickElementActionError.applicationChanged
        }
        let applicationElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        guard let windowElement = elementValue(from: applicationElement, attribute: Attribute.focusedWindow) else {
            throw ClickElementActionError.missingWindowElement
        }
        let candidates = matchingElements(
            in: windowElement,
            role: expectedRole,
            label: expectedLabel
        )
        guard candidates.count == 1, let target = candidates.first else {
            throw candidates.isEmpty ? ClickElementActionError.targetNotFound : ClickElementActionError.ambiguousTarget
        }

        let pressError = AXUIElementPerformAction(target, kAXPressAction as CFString)
        guard pressError == .success else {
            throw ClickElementActionError.pressFailed
        }

        return BridgeClickResult(
            actionID: approval.actionID,
            elementRole: expectedRole,
            elementLabel: expectedLabel,
            completedAt: now
        )
    }

    private func validate(
        snapshot: ContextSnapshot,
        approval: BridgeAutomationApprovalRequest
    ) throws {
        guard let expectedApp = approval.targetApp else {
            throw ClickElementActionError.missingTargetApplication
        }
        guard let currentApp = snapshot.activeApp,
              currentApp.bundleID == expectedApp.bundleID else {
            throw ClickElementActionError.applicationChanged
        }
        guard let expectedWindow = approval.targetWindow,
              let expectedWindowID = expectedWindow.id else {
            throw ClickElementActionError.missingTargetWindow
        }
        guard let currentWindowID = snapshot.window?.id,
              currentWindowID == expectedWindowID else {
            throw ClickElementActionError.windowChanged
        }
        guard !snapshot.redactions.contains(.blockedApplication),
              !snapshot.redactions.contains(.blockedWindow) else {
            throw ClickElementActionError.blockedContext
        }
    }

    private func matchingElements(
        in root: AXUIElement,
        role expectedRole: String,
        label expectedLabel: String
    ) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0

        while let (element, depth) = queue.first,
              visited < maximumVisitedElements {
            queue.removeFirst()
            visited += 1

            if stringValue(from: element, attribute: Attribute.role) == expectedRole,
               labels(for: element).contains(where: { $0.localizedCaseInsensitiveCompare(expectedLabel) == .orderedSame }) {
                matches.append(element)
            }

            guard depth < maximumSearchDepth else { continue }
            for child in children(from: element) {
                queue.append((child, depth + 1))
            }
        }

        return matches
    }

    private func labels(for element: AXUIElement) -> [String] {
        [
            stringValue(from: element, attribute: Attribute.title),
            stringValue(from: element, attribute: Attribute.description),
            stringValue(from: element, attribute: Attribute.value)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func children(from element: AXUIElement) -> [AXUIElement] {
        guard let value = copiedValue(from: element, attribute: Attribute.children) else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func copiedValue(from element: AXUIElement, attribute: String) -> CFTypeRef? {
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
        guard let value = copiedValue(from: element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func blocks(label: String) -> Bool {
        let normalized = label.lowercased()
        return [
            "send",
            "delete",
            "purchase",
            "buy",
            "pay",
            "submit",
            "checkout",
            "confirm",
            "transfer",
            "authorize"
        ].contains { normalized.contains($0) }
    }
}

enum ClickElementActionError: LocalizedError, Equatable {
    case unsupportedAction
    case staleApproval
    case missingRole
    case missingLabel
    case blockedRiskyLabel
    case missingTargetApplication
    case missingTargetWindow
    case applicationChanged
    case windowChanged
    case blockedContext
    case missingWindowElement
    case targetNotFound
    case ambiguousTarget
    case pressFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAction:
            "Only ui.click_element automation approvals can be executed by the click executor."
        case .staleApproval:
            "The click approval expired. Queue the action again."
        case .missingRole:
            "Click execution requires input.element_role."
        case .missingLabel:
            "Click execution requires input.element_label to avoid ambiguous clicks."
        case .blockedRiskyLabel:
            "The target label is blocked by local click safety policy."
        case .missingTargetApplication:
            "The click approval has no target application."
        case .missingTargetWindow:
            "The click approval has no target window."
        case .applicationChanged:
            "The active application changed, so the click was cancelled."
        case .windowChanged:
            "The active window changed, so the click was cancelled."
        case .blockedContext:
            "The target application or window is blocked by the local privacy policy."
        case .missingWindowElement:
            "The active window is not available through Accessibility."
        case .targetNotFound:
            "No matching Accessibility element was found for the click target."
        case .ambiguousTarget:
            "More than one matching Accessibility element was found for the click target."
        case .pressFailed:
            "Accessibility could not press the matched element."
        }
    }
}
