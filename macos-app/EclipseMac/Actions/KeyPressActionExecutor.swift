import CoreGraphics
import Foundation

@MainActor
protocol KeyPressExecuting: AnyObject {
    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date
    ) throws -> BridgeKeyPressResult
}

@MainActor
final class KeyPressActionExecutor: KeyPressExecuting {
    private let collector: any ContextCollecting
    private let maximumApprovalAge: TimeInterval

    init(
        collector: any ContextCollecting = AccessibilityContextCollector(),
        maximumApprovalAge: TimeInterval = SetTextActionPolicy.default.maximumApprovalAge
    ) {
        self.collector = collector
        self.maximumApprovalAge = maximumApprovalAge
    }

    func execute(
        approval: BridgeAutomationApprovalRequest,
        input: BridgeJobInput,
        now: Date = Date()
    ) throws -> BridgeKeyPressResult {
        guard approval.kind == .uiPressKey else {
            throw KeyPressActionError.unsupportedAction
        }
        guard approval.expiresAt >= now,
              now.timeIntervalSince(approval.expiresAt.addingTimeInterval(-maximumApprovalAge)) <= maximumApprovalAge else {
            throw KeyPressActionError.staleApproval
        }
        guard let key = input.key?.lowercased(),
              let keyCode = Self.keyCodes[key] else {
            throw KeyPressActionError.unsupportedKey
        }

        let snapshot = try collector.capture()
        try validate(snapshot: snapshot, approval: approval)

        let modifiers = (input.modifiers ?? []).map { $0.lowercased() }
        let flags = try Self.flags(for: modifiers)
        try postKey(keyCode: keyCode, flags: flags)

        return BridgeKeyPressResult(
            actionID: approval.actionID,
            key: key,
            modifiers: modifiers,
            completedAt: now
        )
    }

    private func validate(
        snapshot: ContextSnapshot,
        approval: BridgeAutomationApprovalRequest
    ) throws {
        guard let expectedApp = approval.targetApp else {
            throw KeyPressActionError.missingTargetApplication
        }
        guard let currentApp = snapshot.activeApp,
              currentApp.bundleID == expectedApp.bundleID else {
            throw KeyPressActionError.applicationChanged
        }
        guard let expectedWindow = approval.targetWindow,
              let expectedWindowID = expectedWindow.id else {
            throw KeyPressActionError.missingTargetWindow
        }
        guard let currentWindowID = snapshot.window?.id,
              currentWindowID == expectedWindowID else {
            throw KeyPressActionError.windowChanged
        }
        guard !snapshot.redactions.contains(.blockedApplication),
              !snapshot.redactions.contains(.blockedWindow) else {
            throw KeyPressActionError.blockedContext
        }
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeyPressActionError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func flags(for modifiers: [String]) throws -> CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case "command":
                flags.insert(.maskCommand)
            case "option":
                flags.insert(.maskAlternate)
            case "control":
                flags.insert(.maskControl)
            case "shift":
                flags.insert(.maskShift)
            default:
                throw KeyPressActionError.unsupportedModifier
            }
        }
        return flags
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "return": 36,
        "tab": 48,
        "space": 49,
        "escape": 53,
        "enter": 76,
        "arrow_left": 123,
        "arrow_right": 124,
        "arrow_down": 125,
        "arrow_up": 126
    ]
}

enum KeyPressActionError: LocalizedError, Equatable {
    case unsupportedAction
    case staleApproval
    case unsupportedKey
    case unsupportedModifier
    case missingTargetApplication
    case missingTargetWindow
    case applicationChanged
    case windowChanged
    case blockedContext
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAction:
            "Only ui.press_key automation approvals can be executed by the key press executor."
        case .staleApproval:
            "The key press approval expired. Queue the action again."
        case .unsupportedKey:
            "The requested key is not in the allowed key press set."
        case .unsupportedModifier:
            "The requested key modifier is not supported."
        case .missingTargetApplication:
            "The key press approval has no target application."
        case .missingTargetWindow:
            "The key press approval has no target window."
        case .applicationChanged:
            "The active application changed, so the key press was cancelled."
        case .windowChanged:
            "The active window changed, so the key press was cancelled."
        case .blockedContext:
            "The target application or window is blocked by the local privacy policy."
        case .eventCreationFailed:
            "macOS could not create the requested key press event."
        }
    }
}
