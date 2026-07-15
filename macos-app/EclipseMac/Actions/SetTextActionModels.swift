import ApplicationServices
import Foundation

struct SetTextTargetBinding: Equatable, Sendable {
    let snapshotID: String
    let bundleID: String
    let applicationName: String
    let windowID: UInt32
    let windowTitle: String?
    let elementRole: String
    let elementLabel: String?
}

struct SetTextActionPresentation: Equatable, Sendable {
    let actionID: String
    let target: SetTextTargetBinding
    let proposedText: String
    let createdAt: Date
}

@MainActor
struct PendingSetTextAction {
    let presentation: SetTextActionPresentation
    let processIdentifier: pid_t
    let element: AXUIElement
}

struct SetTextActionResult: Equatable, Sendable {
    let actionID: String
    let snapshotID: String
    let completedAt: Date
    let charactersWritten: Int
}

enum SetTextActionError: LocalizedError, Equatable {
    case emptyText
    case textTooLong
    case missingApplication
    case missingWindow
    case missingFocusedElement
    case unsupportedElement
    case secureField
    case blockedContext
    case staleApproval
    case applicationChanged
    case windowChanged
    case focusChanged
    case elementNotSettable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "Enter text before preparing an action."
        case .textTooLong:
            "The proposed text exceeds the local 4,000-character limit."
        case .missingApplication:
            "The action does not have a known target application."
        case .missingWindow:
            "The action does not have an exact target window."
        case .missingFocusedElement:
            "Focus a text field before preparing the action."
        case .unsupportedElement:
            "The focused element is not a supported editable text field."
        case .secureField:
            "Eclipse Mac never types into secure text fields."
        case .blockedContext:
            "The target application or window is blocked by the local privacy policy."
        case .staleApproval:
            "The approval expired. Prepare the action again against the current field."
        case .applicationChanged:
            "The active application changed, so the action was cancelled."
        case .windowChanged:
            "The active window changed, so the action was cancelled."
        case .focusChanged:
            "Keyboard focus changed, so the action was cancelled."
        case .elementNotSettable:
            "The focused element does not allow its value to be changed."
        case .writeFailed:
            "Accessibility could not set the focused field's text."
        }
    }
}
