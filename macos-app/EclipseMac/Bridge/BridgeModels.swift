import Foundation

enum BridgeProtocol {
    static let currentVersion = "0.1"
}

enum BridgeJobKind: String, Codable, Equatable, Sendable {
    case contextGetActiveWindow = "context.get_active_window"
    case uiSetText = "ui.set_text"
}

enum BridgeRisk: String, Codable, Equatable, Sendable {
    case read
    case reversible
    case consequential
}

enum BridgeJobStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case rejected
    case expired
    case pendingApproval = "pending_approval"
}

struct BridgeJobInput: Codable, Equatable, Sendable {
    let text: String?

    static let empty = BridgeJobInput(text: nil)

    static func setText(_ text: String) -> BridgeJobInput {
        BridgeJobInput(text: text)
    }
}

struct BridgeJobEnvelope: Codable, Equatable, Sendable {
    let jobID: String
    let protocolVersion: String
    let deviceID: String
    let kind: BridgeJobKind
    let risk: BridgeRisk
    let input: BridgeJobInput
    let expiresAt: Date
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case protocolVersion = "protocol_version"
        case deviceID = "device_id"
        case kind
        case risk
        case input
        case expiresAt = "expires_at"
        case idempotencyKey = "idempotency_key"
    }
}

struct BridgeApprovalRequest: Codable, Equatable, Sendable {
    let approvalID: String
    let actionID: String
    let risk: BridgeRisk
    let target: SetTextTargetBinding
    let proposedText: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case actionID = "action_id"
        case risk
        case target
        case proposedText = "proposed_text"
        case expiresAt = "expires_at"
    }
}

struct BridgeJobOutput: Codable, Equatable, Sendable {
    let context: ContextSnapshot?
    let approval: BridgeApprovalRequest?
    let actionResult: SetTextActionResult?

    enum CodingKeys: String, CodingKey {
        case context
        case approval
        case actionResult = "action_result"
    }

    static func context(_ snapshot: ContextSnapshot) -> BridgeJobOutput {
        BridgeJobOutput(context: snapshot, approval: nil, actionResult: nil)
    }

    static func approval(_ request: BridgeApprovalRequest) -> BridgeJobOutput {
        BridgeJobOutput(context: nil, approval: request, actionResult: nil)
    }

    static func actionResult(_ result: SetTextActionResult) -> BridgeJobOutput {
        BridgeJobOutput(context: nil, approval: nil, actionResult: result)
    }
}

struct BridgeErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

struct BridgeJobResultEnvelope: Codable, Equatable, Sendable {
    let jobID: String
    let protocolVersion: String
    let deviceID: String
    let status: BridgeJobStatus
    let output: BridgeJobOutput?
    let error: BridgeErrorPayload?
    let completedAt: Date
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case protocolVersion = "protocol_version"
        case deviceID = "device_id"
        case status
        case output
        case error
        case completedAt = "completed_at"
        case idempotencyKey = "idempotency_key"
    }
}
