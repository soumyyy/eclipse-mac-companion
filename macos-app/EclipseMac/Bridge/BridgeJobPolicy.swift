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
        case .uiSetText:
            guard job.risk == .reversible else {
                throw BridgeJobPolicyError.riskMismatch
            }
            guard let text = job.input.text, !text.isEmpty else {
                throw BridgeJobPolicyError.invalidInput("ui.set_text requires non-empty input.text")
            }
        }
    }
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
