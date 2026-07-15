import Foundation

enum BridgeProtocol {
    static let currentVersion = "0.1"
}

enum BridgeJobKind: String, Codable, Equatable, Sendable {
    case contextGetActiveWindow = "context.get_active_window"
    case contextCaptureWindow = "context.capture_window"
    case notificationShow = "notification.show"
    case uiPressKey = "ui.press_key"
    case uiClickElement = "ui.click_element"
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
    let title: String?
    let body: String?
    let key: String?
    let modifiers: [String]?
    let elementRole: String?
    let elementLabel: String?

    enum CodingKeys: String, CodingKey {
        case text
        case title
        case body
        case key
        case modifiers
        case elementRole = "element_role"
        case elementLabel = "element_label"
    }

    static let empty = BridgeJobInput(
        text: nil,
        title: nil,
        body: nil,
        key: nil,
        modifiers: nil,
        elementRole: nil,
        elementLabel: nil
    )

    static func setText(_ text: String) -> BridgeJobInput {
        BridgeJobInput(
            text: text,
            title: nil,
            body: nil,
            key: nil,
            modifiers: nil,
            elementRole: nil,
            elementLabel: nil
        )
    }

    static func notification(title: String, body: String?) -> BridgeJobInput {
        BridgeJobInput(
            text: nil,
            title: title,
            body: body,
            key: nil,
            modifiers: nil,
            elementRole: nil,
            elementLabel: nil
        )
    }

    static func keyPress(key: String, modifiers: [String] = []) -> BridgeJobInput {
        BridgeJobInput(
            text: nil,
            title: nil,
            body: nil,
            key: key,
            modifiers: modifiers,
            elementRole: nil,
            elementLabel: nil
        )
    }

    static func clickElement(role: String? = nil, label: String? = nil) -> BridgeJobInput {
        BridgeJobInput(
            text: nil,
            title: nil,
            body: nil,
            key: nil,
            modifiers: nil,
            elementRole: role,
            elementLabel: label
        )
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

struct BridgeAutomationApprovalRequest: Codable, Equatable, Sendable {
    let approvalID: String
    let actionID: String
    let kind: BridgeJobKind
    let risk: BridgeRisk
    let summary: String
    let targetApp: ActiveApplication?
    let targetWindow: ActiveWindow?
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case actionID = "action_id"
        case kind
        case risk
        case summary
        case targetApp = "target_app"
        case targetWindow = "target_window"
        case expiresAt = "expires_at"
    }
}

struct BridgeWindowCaptureMetadata: Codable, Equatable, Sendable {
    let captureID: String
    let snapshotID: String
    let windowID: UInt32
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int

    enum CodingKeys: String, CodingKey {
        case captureID = "capture_id"
        case snapshotID = "snapshot_id"
        case windowID = "window_id"
        case capturedAt = "captured_at"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
    }
}

struct BridgeNotificationReceipt: Codable, Equatable, Sendable {
    let notificationID: String
    let deliveredAt: Date

    enum CodingKeys: String, CodingKey {
        case notificationID = "notification_id"
        case deliveredAt = "delivered_at"
    }
}

struct BridgeJobOutput: Codable, Equatable, Sendable {
    let context: ContextSnapshot?
    let approval: BridgeApprovalRequest?
    let automationApproval: BridgeAutomationApprovalRequest?
    let actionResult: SetTextActionResult?
    let capture: BridgeWindowCaptureMetadata?
    let notification: BridgeNotificationReceipt?

    enum CodingKeys: String, CodingKey {
        case context
        case approval
        case automationApproval = "automation_approval"
        case actionResult = "action_result"
        case capture
        case notification
    }

    static func context(_ snapshot: ContextSnapshot) -> BridgeJobOutput {
        BridgeJobOutput(
            context: snapshot,
            approval: nil,
            automationApproval: nil,
            actionResult: nil,
            capture: nil,
            notification: nil
        )
    }

    static func approval(_ request: BridgeApprovalRequest) -> BridgeJobOutput {
        BridgeJobOutput(
            context: nil,
            approval: request,
            automationApproval: nil,
            actionResult: nil,
            capture: nil,
            notification: nil
        )
    }

    static func automationApproval(_ request: BridgeAutomationApprovalRequest) -> BridgeJobOutput {
        BridgeJobOutput(
            context: nil,
            approval: nil,
            automationApproval: request,
            actionResult: nil,
            capture: nil,
            notification: nil
        )
    }

    static func actionResult(_ result: SetTextActionResult) -> BridgeJobOutput {
        BridgeJobOutput(
            context: nil,
            approval: nil,
            automationApproval: nil,
            actionResult: result,
            capture: nil,
            notification: nil
        )
    }

    static func capture(_ metadata: WindowCaptureMetadata) -> BridgeJobOutput {
        BridgeJobOutput(
            context: nil,
            approval: nil,
            automationApproval: nil,
            actionResult: nil,
            capture: BridgeWindowCaptureMetadata(
                captureID: metadata.captureID,
                snapshotID: metadata.snapshotID,
                windowID: metadata.windowID,
                capturedAt: metadata.capturedAt,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight
            ),
            notification: nil
        )
    }

    static func notification(_ receipt: BridgeNotificationReceipt) -> BridgeJobOutput {
        BridgeJobOutput(
            context: nil,
            approval: nil,
            automationApproval: nil,
            actionResult: nil,
            capture: nil,
            notification: receipt
        )
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
