import Foundation

struct SetTextActionPolicy: Sendable {
    let maximumApprovalAge: TimeInterval
    let maximumTextLength: Int

    static let `default` = SetTextActionPolicy(
        maximumApprovalAge: 10,
        maximumTextLength: 4_000
    )

    private static let supportedRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox"
    ]

    func validatePreparation(
        snapshot: ContextSnapshot,
        proposedText: String
    ) throws -> SetTextTargetBinding {
        guard !proposedText.isEmpty else { throw SetTextActionError.emptyText }
        guard proposedText.count <= maximumTextLength else { throw SetTextActionError.textTooLong }
        guard let application = snapshot.activeApp else { throw SetTextActionError.missingApplication }
        guard let window = snapshot.window, let windowID = window.id else {
            throw SetTextActionError.missingWindow
        }
        guard !snapshot.redactions.contains(.blockedApplication),
              !snapshot.redactions.contains(.blockedWindow) else {
            throw SetTextActionError.blockedContext
        }
        guard !snapshot.redactions.contains(.secureFields) else {
            throw SetTextActionError.secureField
        }
        guard let element = snapshot.focusedElement else {
            throw SetTextActionError.missingFocusedElement
        }
        guard Self.supportedRoles.contains(element.role) else {
            throw SetTextActionError.unsupportedElement
        }

        return SetTextTargetBinding(
            snapshotID: snapshot.snapshotID,
            bundleID: application.bundleID,
            applicationName: application.name,
            windowID: windowID,
            windowTitle: window.title,
            elementRole: element.role,
            elementLabel: element.label
        )
    }

    func validateExecution(
        presentation: SetTextActionPresentation,
        currentSnapshot: ContextSnapshot,
        now: Date = Date()
    ) throws {
        let age = now.timeIntervalSince(presentation.createdAt)
        guard age >= 0, age <= maximumApprovalAge else {
            throw SetTextActionError.staleApproval
        }

        let current = try validatePreparation(
            snapshot: currentSnapshot,
            proposedText: presentation.proposedText
        )
        guard current.bundleID == presentation.target.bundleID else {
            throw SetTextActionError.applicationChanged
        }
        guard current.windowID == presentation.target.windowID else {
            throw SetTextActionError.windowChanged
        }
        guard current.elementRole == presentation.target.elementRole else {
            throw SetTextActionError.focusChanged
        }
    }
}
