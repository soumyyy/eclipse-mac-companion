import Foundation

struct BridgeJobPolicy: Sendable {
    static let `default` = BridgeJobPolicy()

    func validate(_ job: BridgeJobEnvelope, now: Date = Date()) throws {
        guard job.protocolVersion == BridgeProtocol.currentVersion else {
            throw BridgeJobPolicyError.unsupportedProtocolVersion
        }
        guard job.expiresAt >= now else {
            throw BridgeJobPolicyError.expiredJob
        }

        switch job.kind {
        case .contextGetActiveWindow:
            guard job.risk == .read else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard job.input == .empty else {
                throw BridgeJobPolicyError.invalidInput("context.get_active_window does not accept input")
            }
        case .contextCaptureWindow:
            guard job.risk == .read else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard job.input == .empty else {
                throw BridgeJobPolicyError.invalidInput("context.capture_window does not accept input")
            }
        case .notificationShow:
            guard job.risk == .reversible else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard let title = job.input.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                throw BridgeJobPolicyError.invalidInput("notification.show requires non-empty input.title")
            }
            if let body = job.input.body, body.count > 1_000 {
                throw BridgeJobPolicyError.invalidInput("notification.show input.body is too long")
            }
        case .uiPressKey:
            guard job.risk == .reversible else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard let key = job.input.key?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  Self.allowedKeys.contains(key) else {
                throw BridgeJobPolicyError.invalidInput("ui.press_key requires an allowed input.key")
            }
            let modifiers = job.input.modifiers ?? []
            let unsupportedModifiers = modifiers.filter { !Self.allowedModifiers.contains($0.lowercased()) }
            guard unsupportedModifiers.isEmpty else {
                throw BridgeJobPolicyError.invalidInput("ui.press_key contains an unsupported modifier")
            }
        case .uiSetText:
            guard job.risk == .reversible else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard let text = job.input.text, !text.isEmpty else {
                throw BridgeJobPolicyError.invalidInput("ui.set_text requires non-empty input.text")
            }
        case .uiClickElement:
            guard job.risk == .consequential else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard let role = job.input.elementRole?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !role.isEmpty else {
                throw BridgeJobPolicyError.invalidInput("ui.click_element requires input.element_role")
            }
        }
    }

    private static let allowedKeys: Set<String> = [
        "escape",
        "return",
        "enter",
        "tab",
        "space",
        "arrow_left",
        "arrow_right",
        "arrow_up",
        "arrow_down"
    ]

    private static let allowedModifiers: Set<String> = [
        "shift",
        "control",
        "option",
        "command"
    ]
}

enum BridgeJobPolicyError: LocalizedError, Equatable {
    case unsupportedProtocolVersion
    case expiredJob
    case riskMismatch
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion:
            "The job uses an unsupported protocol version."
        case .expiredJob:
            "The job expired before the Mac could process it."
        case .riskMismatch:
            "The job risk does not match the requested capability."
        case .invalidInput(let message):
            message
        }
    }

    var bridgeCode: String {
        switch self {
        case .unsupportedProtocolVersion:
            "unsupported_protocol_version"
        case .expiredJob:
            "expired_job"
        case .riskMismatch:
            "risk_mismatch"
        case .invalidInput:
            "invalid_input"
        }
    }
}
