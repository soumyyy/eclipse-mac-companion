import Foundation

@MainActor
final class LocalBridgeProcessor {
    private let deviceID: String
    private let collector: any ContextCollecting
    private let textActions: any SetTextActionControlling
    private let policy: BridgeJobPolicy

    init(
        deviceID: String,
        collector: any ContextCollecting = AccessibilityContextCollector(),
        textActions: any SetTextActionControlling,
        policy: BridgeJobPolicy = .default
    ) {
        self.deviceID = deviceID
        self.collector = collector
        self.textActions = textActions
        self.policy = policy
    }

    func process(_ job: BridgeJobEnvelope, now: Date = Date()) -> BridgeJobResultEnvelope {
        do {
            try policy.validate(job, now: now)

            switch job.kind {
            case .contextGetActiveWindow:
                let snapshot = try collector.capture()
                return result(
                    for: job,
                    status: .succeeded,
                    output: .context(snapshot),
                    completedAt: now
                )

            case .uiSetText:
                let text = try requiredText(from: job)
                try textActions.prepareAction(text: text)
                guard let pending = textActions.pendingPresentation else {
                    throw BridgeProcessorError.missingApprovalPresentation
                }
                let approval = BridgeApprovalRequest(
                    approvalID: "appr_\(UUID().uuidString.lowercased())",
                    actionID: pending.actionID,
                    risk: job.risk,
                    target: pending.target,
                    proposedText: pending.proposedText,
                    expiresAt: pending.createdAt.addingTimeInterval(SetTextActionPolicy.default.maximumApprovalAge)
                )
                return result(
                    for: job,
                    status: .pendingApproval,
                    output: .approval(approval),
                    completedAt: now
                )
            }
        } catch let error as BridgeJobPolicyError {
            return result(
                for: job,
                status: error == .expiredJob ? .expired : .rejected,
                error: BridgeErrorPayload(code: error.bridgeCode, message: error.localizedDescription),
                completedAt: now
            )
        } catch {
            return result(
                for: job,
                status: .failed,
                error: BridgeErrorPayload(code: "processor_error", message: error.localizedDescription),
                completedAt: now
            )
        }
    }

    func completionResult(
        for job: BridgeJobEnvelope,
        actionResult: SetTextActionResult,
        completedAt: Date = Date()
    ) -> BridgeJobResultEnvelope {
        result(
            for: job,
            status: .succeeded,
            output: .actionResult(actionResult),
            completedAt: completedAt
        )
    }

    private func requiredText(from job: BridgeJobEnvelope) throws -> String {
        guard let text = job.input.text else {
            throw BridgeJobPolicyError.invalidInput("ui.set_text requires input.text")
        }
        return text
    }

    private func result(
        for job: BridgeJobEnvelope,
        status: BridgeJobStatus,
        output: BridgeJobOutput? = nil,
        error: BridgeErrorPayload? = nil,
        completedAt: Date
    ) -> BridgeJobResultEnvelope {
        BridgeJobResultEnvelope(
            jobID: job.jobID,
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: deviceID,
            status: status,
            output: output,
            error: error,
            completedAt: completedAt,
            idempotencyKey: job.idempotencyKey
        )
    }
}

enum BridgeProcessorError: LocalizedError {
    case missingApprovalPresentation

    var errorDescription: String? {
        switch self {
        case .missingApprovalPresentation:
            "The text action did not produce an approval presentation."
        }
    }
}
